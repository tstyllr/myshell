#!/bin/bash

echo "开始生成中国 IP 路由规则..."

# 下载最新的中国 IP 段列表
echo "正在下载中国 IP 段数据..."
curl -L https://raw.githubusercontent.com/misakaio/chnroutes2/master/chnroutes.txt -o chnroutes.txt

if [ ! -f chnroutes.txt ]; then
    echo "下载失败，尝试备用源..."
    curl -L https://raw.githubusercontent.com/QiuSimons/Chnroute/master/dist/chnroute/chnroute.txt -o chnroutes.txt
fi

if [ ! -f chnroutes.txt ]; then
    echo "错误: 无法下载中国 IP 段数据"
    exit 1
fi

echo "下载完成，开始转换格式..."

# 生成 OpenVPN 配置片段
cat > chnroutes-openvpn.txt << 'EOF'
# ============================================
# 中国大陆 IP 路由规则 - OpenVPN 配置
# 生成时间: $(date)
# 用途: 让中国大陆 IP 不走 VPN，其他流量走 VPN
# ============================================

# 让所有流量默认走 VPN
redirect-gateway def1

# 以下是中国大陆的 IP 段，使用本地网关（不走 VPN）
# net_gateway 表示使用原始的默认网关

EOF

# 转换 CIDR 为 OpenVPN 路由格式
python3 << 'PYTHON_SCRIPT'
import sys

def cidr_to_netmask(prefix_len):
    """将 CIDR 前缀长度转换为子网掩码"""
    mask = (0xffffffff >> (32 - prefix_len)) << (32 - prefix_len)
    return f"{(mask >> 24) & 0xff}.{(mask >> 16) & 0xff}.{(mask >> 8) & 0xff}.{mask & 0xff}"

count = 0
with open('chnroutes.txt', 'r') as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        
        try:
            ip, prefix = line.split('/')
            prefix = int(prefix)
            netmask = cidr_to_netmask(prefix)
            print(f"route {ip} {netmask} net_gateway")
            count += 1
        except Exception as e:
            print(f"# 警告: 无法解析 {line}: {e}", file=sys.stderr)

print(f"# 共添加 {count} 条中国 IP 路由规则", file=sys.stderr)
PYTHON_SCRIPT

echo ""
echo "转换完成！"
echo "生成的文件: chnroutes-openvpn.txt"
echo ""