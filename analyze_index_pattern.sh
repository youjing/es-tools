#!/bin/bash

# 显示帮助信息
show_help() {
    echo "用法: $0 [文件名]"
    echo
    echo "分析 Elasticsearch 索引列表，提取出可能的 index pattern"
    echo "可以从文件读取索引列表，或者通过管道从标准输入接收"
    echo
    echo "参数:"
    echo "  文件名            包含索引列表的文件（可选）"
    echo "                   如果未提供文件名，则从标准输入读取"
    echo
    echo "示例:"
    echo "  # 从文件读取索引列表"
    echo "  $0 indices.txt"
    echo
    echo "  # 从 list-indices.sh 的输出中读取"
    echo "  ./list-indices.sh | $0"
    echo
    echo "  # 保存分析结果到文件"
    echo "  $0 indices.txt > patterns.txt"
    echo
}

# 检查是否有输入
check_input() {
    # 如果没有参数且标准输入是终端（即没有通过管道传入数据）
    if [ $# -eq 0 ] && [ -t 0 ]; then
        echo "错误: 未提供输入。请提供文件名或通过管道传入数据。" >&2
        echo >&2
        show_help
        exit 1
    fi
}

# 处理索引名称并提取模式的函数
process_indices() {
    # 创建临时文件存储输入
    local temp_file=$(mktemp)
    cat > "$temp_file"

    # 如果文件为空
    if [ ! -s "$temp_file" ]; then
        rm "$temp_file"
        echo "错误: 没有接收到任何输入数据。" >&2
        echo >&2
        show_help
        exit 1
    fi

    # 读取输入并过滤掉非索引行（忽略横线和提示信息）
    grep -v '^-\+$' "$temp_file" | grep -v '^正在获取索引列表\.\.\.$' | \
    while read -r index; do
        # 跳过空行
        [ -z "$index" ] && continue
        
        # 处理索引名称以提取模式
        pattern=$(echo "$index" | \
            # 替换变量占位符为通配符
            sed 's/%{[^}]*}/*/' | \
            # 替换年份范围和时间戳格式
            sed -E 's/_[0-9]{4}\.[0-9]{2,}-[0-9]{4}\.[0-9]{2,}/_*/' | \
            # 替换其他数字模式
            sed -E 's/_[0-9]{4}\.[0-9]{2,}/_*/' | \
            # 清理多余的通配符（如 *-* 变为 *）
            sed -E 's/\*-\*/\*/' | \
            # 清理末尾的时间戳模式
            sed -E 's/_[0-9]{4}-[0-9]{4}$/_*/' | \
            # 清理可能剩余的重复通配符
            sed -E 's/\*+/\*/')

        echo "$pattern"
    done | sort -u # 排序并去重

    # 清理临时文件
    rm "$temp_file"
}

# 参数解析
case $1 in
    --help)
        show_help
        exit 0
        ;;
esac

# 检查输入
check_input "$@"

# 主程序
echo "分析得到的 index patterns:"
echo "----------------------------------------"

if [ $# -eq 0 ]; then
    # 从标准输入读取
    process_indices
else
    # 从文件读取
    if [ ! -f "$1" ]; then
        echo "错误: 文件 '$1' 不存在" >&2
        exit 1
    fi
    cat "$1" | process_indices
fi

echo "----------------------------------------" 