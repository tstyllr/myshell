#!/bin/zsh
  
# 设置输出文件路径和名称  
output_file="project_typescript_code.txt"  
  
# 获取项目根目录路径  
project_root="/Users/yangzhicong/code/EkingErpApp/src"  
  
# 获取所有.ts和.tsx文件的路径并输出到指定文件  
find "$project_root" -type f -name "*.ts" -o -name "*.tsx" > "$output_file"  
  
echo "代码已成功输出到$output_file"