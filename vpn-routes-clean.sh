#!/bin/bash

DOMAINS=(
    "google.com"
    "youtube.com"
    "twitter.com"
    "facebook.com"
    "instagram.com"
)

echo "清理路由..."
for domain in "${DOMAINS[@]}"; do
    echo "Removing routes for $domain..."
    IPS=$(dig +short $domain | grep -E '^[0-9.]+$')
    
    for ip in $IPS; do
        echo "  -> $ip"
        sudo route delete -host $ip 2>/dev/null
    done
done

echo "路由清理完成！"