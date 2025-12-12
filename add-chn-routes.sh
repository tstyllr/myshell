#!/bin/bash

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
    echo "错误: 此脚本需要 root 权限"
    echo "请使用: sudo $0"
    exit 1
fi

CHN_ROUTES_FILE="./chnroutes.txt"

echo "=== 添加中国路由规则 ==="

# 获取原始默认网关 - 改进版
OLD_GW=$(netstat -rn | grep default | grep -E "en[0-9]+" | awk '{print $2}' | head -1)

if [ -z "$OLD_GW" ]; then
    echo "警告: 无法通过 netstat 获取网关，尝试其他方法..."
    OLD_GW=$(route -n get default 2>/dev/null | grep gateway | awk '{print $2}')
fi

if [ -z "$OLD_GW" ]; then
    echo "错误: 无法获取原始网关"
    exit 1
fi

echo "原始网关: $OLD_GW"

if [ ! -f "$CHN_ROUTES_FILE" ]; then
    echo "错误: 找不到 $CHN_ROUTES_FILE"
    exit 1
fi

# 保存网关地址供 down 脚本使用
echo "$OLD_GW" > /tmp/openvpn-old-gateway.txt

echo "开始添加路由（这可能需要几分钟）..."

count=0
errors=0

# 导出环境变量供 Python 脚本使用
export OLD_GW
export CHN_ROUTES_FILE

# 使用 Python 处理路由
python3 << 'PYTHON_SCRIPT'
import subprocess
import sys
import os

def cidr_to_netmask(prefix_len):
    """将 CIDR 前缀长度转换为子网掩码"""
    mask = (0xffffffff >> (32 - prefix_len)) << (32 - prefix_len)
    return f"{(mask >> 24) & 0xff}.{(mask >> 16) & 0xff}.{(mask >> 8) & 0xff}.{mask & 0xff}"

# 从环境变量获取网关地址
old_gw = os.environ.get('OLD_GW')
routes_file = os.environ.get('CHN_ROUTES_FILE')

if not old_gw:
    print("错误: 未设置网关地址", file=sys.stderr)
    sys.exit(1)

if not routes_file:
    print("错误: 未设置路由文件路径", file=sys.stderr)
    sys.exit(1)

count = 0
errors = 0
error_details = []

try:
    with open(routes_file, 'r') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line or line.startswith('#'):
                continue

            try:
                ip, prefix = line.split('/')
                prefix = int(prefix)
                netmask = cidr_to_netmask(prefix)

                # macOS route 命令正确语法: route add -net <network> -netmask <mask> <gateway>
                cmd = ['route', '-n', 'add', '-net', ip, '-netmask', netmask, old_gw]
                result = subprocess.run(cmd, capture_output=True, text=True)

                if result.returncode == 0:
                    count += 1
                    if count % 500 == 0:
                        print(f"已添加 {count} 条路由...", flush=True)
                elif "File exists" not in result.stderr and "route already" not in result.stderr.lower():
                    errors += 1
                    if len(error_details) < 10:  # 保存前10个错误详情
                        error_details.append(f"行 {line_num}: {line} - {result.stderr.strip()}")

            except ValueError as e:
                errors += 1
                if len(error_details) < 10:
                    error_details.append(f"行 {line_num}: {line} - 格式错误: {e}")
            except Exception as e:
                errors += 1
                if len(error_details) < 10:
                    error_details.append(f"行 {line_num}: {line} - {e}")

except FileNotFoundError:
    print(f"错误: 找不到文件 {routes_file}", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"错误: {e}", file=sys.stderr)
    sys.exit(1)

# 输出结果
print(f"\n完成！成功添加 {count} 条路由，{errors} 个错误")

if error_details:
    print("\n错误详情（最多显示10个）:", file=sys.stderr)
    for detail in error_details:
        print(f"  {detail}", file=sys.stderr)

sys.exit(0 if errors == 0 else 0)  # 即使有错误也返回0，因为部分错误是可接受的（如已存在的路由）
PYTHON_SCRIPT

echo "=== 路由添加完成 ==="