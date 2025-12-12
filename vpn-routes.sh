#!/bin/bash

# 需要走VPN的网站列表
DOMAINS=(
    "google.com"
    "youtube.com"
    "twitter.com"
    "facebook.com"
    "instagram.com"
)

# 查找有 IPv4 地址的 utun 接口
VPN_INTERFACE=""
for iface in $(ifconfig | grep -o 'utun[0-9]*'); do
    if ifconfig $iface | grep -q 'inet '; then
        VPN_INTERFACE=$iface
        break
    fi
done

if [ -z "$VPN_INTERFACE" ]; then
    echo "错误: 未找到有效的VPN接口"
    exit 1
fi

VPN_GW=$(ifconfig $VPN_INTERFACE | grep 'inet ' | awk '{print $4}')

echo "VPN Interface: $VPN_INTERFACE"
echo "VPN Gateway: $VPN_GW"
echo "---"

if [ -z "$VPN_GW" ]; then
    echo "错误: 无法获取VPN网关地址"
    exit 1
fi

for domain in "${DOMAINS[@]}"; do
    echo "Adding route for $domain..."
    # 使用 Google DNS (8.8.8.8) 来解析，避免 DNS 污染
    IPS=$(dig @8.8.8.8 +short $domain | grep -E '^[0-9.]+$')
    
    if [ -z "$IPS" ]; then
        echo "  警告: 无法解析 $domain，跳过"
        continue
    fi
    
    for ip in $IPS; do
        echo "  -> $ip"
        # 检查路由是否已存在
        if ! netstat -rn | grep -q "^$ip "; then
            sudo route add -host $ip $VPN_GW 2>/dev/null
            if [ $? -eq 0 ]; then
                echo "     ✓ 添加成功"
            else
                echo "     ✗ 添加失败"
            fi
        else
            echo "     - 已存在"
        fi
    done
done

echo "---"
echo "路由添加完成！"
echo ""
echo "当前路由（仅显示通过VPN的）："
netstat -rn | grep $VPN_INTERFACE | grep -v fe80 | grep UGHS