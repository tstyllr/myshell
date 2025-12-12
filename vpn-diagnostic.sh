#!/bin/bash

echo "=== VPN 接口信息 ==="
ifconfig | grep -A 10 utun

echo -e "\n=== 路由表 ==="
netstat -rn | grep utun

echo -e "\n=== 默认网关 ==="
netstat -rn | grep default

echo -e "\n=== DNS 配置 ==="
scutil --dns | grep nameserver | head -5