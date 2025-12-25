#!/bin/bash
# shadowsocks-deploy.sh - 纯SS部署脚本

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}================================${NC}"
echo -e "${GREEN}  Shadowsocks一键部署脚本${NC}"
echo -e "${BLUE}================================${NC}"

# 检查root权限
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}请使用root用户运行${NC}"
   exit 1
fi

# 停止Xray服务（如果在运行）
echo -e "${YELLOW}[1/8] 停止现有服务...${NC}"
if systemctl is-active --quiet xray; then
    systemctl stop xray
    systemctl disable xray
    echo -e "${GREEN}已停止Xray服务${NC}"
fi

# 更新系统
echo -e "${YELLOW}[2/8] 更新系统...${NC}"
apt update -y

# 安装依赖
echo -e "${YELLOW}[3/8] 安装依赖包...${NC}"
apt install -y wget curl git build-essential autoconf libtool libssl-dev libpcre3-dev libev-dev asciidoc xmlto automake

# 安装Shadowsocks-libev（官方版本，性能最好）
echo -e "${YELLOW}[4/8] 安装Shadowsocks-libev...${NC}"
apt install -y shadowsocks-libev

# 生成配置参数
echo -e "${YELLOW}[5/8] 生成配置...${NC}"
SERVER_IP=$(curl -s https://api.ipify.org)
SS_PORT=8388
SS_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
SS_METHOD="chacha20-ietf-poly1305"  # 推荐加密方式

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}服务器IP: ${SERVER_IP}${NC}"
echo -e "${GREEN}端口: ${SS_PORT}${NC}"
echo -e "${GREEN}密码: ${SS_PASSWORD}${NC}"
echo -e "${GREEN}加密方式: ${SS_METHOD}${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# 创建配置文件
echo -e "${YELLOW}[6/8] 创建配置文件...${NC}"
cat > /etc/shadowsocks-libev/config.json << SSEOF
{
    "server": "0.0.0.0",
    "server_port": ${SS_PORT},
    "password": "${SS_PASSWORD}",
    "timeout": 300,
    "method": "${SS_METHOD}",
    "fast_open": true,
    "nameserver": "8.8.8.8",
    "mode": "tcp_and_udp"
}
SSEOF

# 优化系统参数
echo -e "${YELLOW}[7/8] 优化系统参数...${NC}"
cat >> /etc/sysctl.conf << EOF

# Shadowsocks优化
fs.file-max = 51200
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 4096
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.ip_local_port_range = 10000 65000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mem = 25600 51200 102400
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
EOF

sysctl -p > /dev/null 2>&1

# 配置防火墙
echo -e "${YELLOW}[8/8] 配置防火墙...${NC}"
if command -v ufw &> /dev/null; then
    ufw allow ${SS_PORT}/tcp
    ufw allow ${SS_PORT}/udp
    ufw reload
    echo -e "${GREEN}防火墙规则已添加${NC}"
fi

# 启动服务
echo -e "${YELLOW}启动Shadowsocks服务...${NC}"
systemctl enable shadowsocks-libev
systemctl restart shadowsocks-libev

# 等待服务启动
sleep 2

# 检查服务状态
if systemctl is-active --quiet shadowsocks-libev; then
    echo -e "${GREEN}✓ Shadowsocks服务运行正常${NC}"
else
    echo -e "${RED}✗ Shadowsocks服务启动失败${NC}"
    journalctl -u shadowsocks-libev -n 20 --no-pager
    exit 1
fi

# 检查端口监听
PORT_LISTENING=$(netstat -tlnp | grep ${SS_PORT})
if [ ! -z "$PORT_LISTENING" ]; then
    echo -e "${GREEN}✓ 端口 ${SS_PORT} 正在监听${NC}"
else
    echo -e "${RED}✗ 端口监听失败${NC}"
    exit 1
fi

# 生成SS链接
SS_LINK_RAW="${SS_METHOD}:${SS_PASSWORD}@${SERVER_IP}:${SS_PORT}"
SS_LINK_BASE64=$(echo -n "${SS_LINK_RAW}" | base64 -w 0)
SS_LINK="ss://${SS_LINK_BASE64}#Hostinger-SS"

# 生成二维码
if command -v qrencode &> /dev/null; then
    echo ""
    echo -e "${YELLOW}SS二维码（扫码导入）:${NC}"
    echo "$SS_LINK" | qrencode -t ANSIUTF8
    echo "$SS_LINK" | qrencode -o /root/ss-qrcode.png
    echo -e "${GREEN}二维码已保存: /root/ss-qrcode.png${NC}"
else
    apt install -y qrencode
    echo "$SS_LINK" | qrencode -t ANSIUTF8
    echo "$SS_LINK" | qrencode -o /root/ss-qrcode.png
fi

# 保存配置信息
cat > /root/shadowsocks-info.txt << INFOEOF
========================================
Shadowsocks服务器信息
========================================
安装时间: $(date)
服务器IP: ${SERVER_IP}
端口: ${SS_PORT}
密码: ${SS_PASSWORD}
加密方式: ${SS_METHOD}

========================================
SS链接（一键导入）
========================================
${SS_LINK}

========================================
管理命令
========================================
启动服务: systemctl start shadowsocks-libev
停止服务: systemctl stop shadowsocks-libev
重启服务: systemctl restart shadowsocks-libev
查看状态: systemctl status shadowsocks-libev
查看日志: journalctl -u shadowsocks-libev -f

========================================
配置文件位置
========================================
配置文件: /etc/shadowsocks-libev/config.json
二维码: /root/ss-qrcode.png

========================================
测试命令
========================================
检查端口: netstat -tlnp | grep ${SS_PORT}
查看进程: ps aux | grep ss-server

========================================
iOS客户端配置
========================================
1. 下载Shadowrocket（小火箭）
2. 点击右上角 + 号
3. 类型选择 "Shadowsocks"
4. 扫描二维码或手动填写以下信息：
   - 服务器: ${SERVER_IP}
   - 端口: ${SS_PORT}
   - 密码: ${SS_PASSWORD}
   - 算法: ${SS_METHOD}
   - 备注: Hostinger-SS

或直接粘贴SS链接导入

========================================
macOS/Windows客户端配置
========================================
macOS: 
- ShadowsocksX-NG
- ClashX (导入下方配置)

Windows:
- Shadowsocks-Windows
- Clash Verge (导入下方配置)

========================================
BBR状态
========================================
$(sysctl net.ipv4.tcp_congestion_control)
========================================
INFOEOF

# 生成Clash配置
cat > /root/clash-ss-config.yaml << CLASHEOF
# Clash配置文件 - Shadowsocks版本
mixed-port: 7890
allow-lan: false
mode: rule
log-level: info

proxies:
  - name: "Hostinger-SS"
    type: ss
    server: ${SERVER_IP}
    port: ${SS_PORT}
    cipher: ${SS_METHOD}
    password: "${SS_PASSWORD}"
    udp: true

proxy-groups:
  - name: "🚀 节点选择"
    type: select
    proxies:
      - "Hostinger-SS"
      - DIRECT

  - name: "🇨🇳 国内直连"
    type: select
    proxies:
      - DIRECT
      - "🚀 节点选择"

  - name: "🌍 国际代理"
    type: select
    proxies:
      - "🚀 节点选择"
      - DIRECT

rules:
  # 局域网
  - DOMAIN-SUFFIX,local,DIRECT
  - IP-CIDR,127.0.0.0/8,DIRECT
  - IP-CIDR,192.168.0.0/16,DIRECT
  - IP-CIDR,10.0.0.0/8,DIRECT
  - IP-CIDR,172.16.0.0/12,DIRECT

  # 国内网站
  - DOMAIN-SUFFIX,cn,🇨🇳 国内直连
  - DOMAIN-KEYWORD,baidu,🇨🇳 国内直连
  - DOMAIN-SUFFIX,qq.com,🇨🇳 国内直连
  - DOMAIN-SUFFIX,taobao.com,🇨🇳 国内直连
  - DOMAIN-SUFFIX,jd.com,🇨🇳 国内直连
  - DOMAIN-SUFFIX,alipay.com,🇨🇳 国内直连
  - DOMAIN-SUFFIX,weixin.com,🇨🇳 国内直连
  - DOMAIN-SUFFIX,bilibili.com,🇨🇳 国内直连

  # 国际网站
  - DOMAIN-SUFFIX,google.com,🌍 国际代理
  - DOMAIN-SUFFIX,youtube.com,🌍 国际代理
  - DOMAIN-SUFFIX,facebook.com,🌍 国际代理
  - DOMAIN-SUFFIX,twitter.com,🌍 国际代理
  - DOMAIN-SUFFIX,github.com,🌍 国际代理
  - DOMAIN-SUFFIX,openai.com,🌍 国际代理

  # GeoIP
  - GEOIP,CN,🇨🇳 国内直连
  
  # 默认
  - MATCH,🚀 节点选择
CLASHEOF

# 显示最终信息
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}          🎉 Shadowsocks部署完成！🎉${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}服务器信息:${NC}"
echo -e "  IP地址: ${GREEN}${SERVER_IP}${NC}"
echo -e "  端口: ${GREEN}${SS_PORT}${NC}"
echo -e "  密码: ${GREEN}${SS_PASSWORD}${NC}"
echo -e "  加密: ${GREEN}${SS_METHOD}${NC}"
echo ""
echo -e "${YELLOW}SS链接:${NC}"
echo -e "  ${BLUE}${SS_LINK}${NC}"
echo ""
echo -e "${YELLOW}配置文件:${NC}"
echo -e "  详细信息: ${GREEN}/root/shadowsocks-info.txt${NC}"
echo -e "  Clash配置: ${GREEN}/root/clash-ss-config.yaml${NC}"
echo -e "  二维码: ${GREEN}/root/ss-qrcode.png${NC}"
echo ""
echo -e "${YELLOW}下载配置:${NC}"
echo -e "  ${BLUE}scp root@${SERVER_IP}:/root/ss-qrcode.png ~/Desktop/${NC}"
echo -e "  ${BLUE}scp root@${SERVER_IP}:/root/clash-ss-config.yaml ~/Desktop/${NC}"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
