#!/bin/bash

# 从环境变量获取配置
ES_HOST=${ES_HOST:-"localhost"}
ES_PORT=${ES_PORT:-"9200"}
AUTH=""
if [ ! -z "$ES_USER" ] && [ ! -z "$ES_PASS" ]; then
    AUTH="-u $ES_USER:$ES_PASS"
fi
DRY_RUN=false
TABLE_FORMAT=false

# 显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo
    echo "列出 Elasticsearch 中的所有索引及其详细信息"
    echo
    echo "环境变量:"
    echo "  ES_HOST            Elasticsearch 主机地址 (默认: localhost)"
    echo "  ES_PORT            Elasticsearch 端口 (默认: 9200)"
    echo "  ES_USER            Elasticsearch 用户名"
    echo "  ES_PASS            Elasticsearch 密码"
    echo
    echo "选项:"
    echo "  --help             显示此帮助信息"
    echo "  --dry-run         仅打印将要执行的命令，不实际执行"
    echo "  --table           以表格格式显示详细信息（包括大小、文档数等）"
    echo "  --pattern <pat>   按名称模式过滤 (例如: 2025.05)"
    echo "  --max-size <size> 按存储大小过滤 (例如: 30mb, 1gb)"
    echo
    echo "示例:"
    echo "  # 列出所有索引名称"
    echo "  $0"
    echo
    echo "  # 显示索引的详细信息"
    echo "  $0 --table"
    echo
    echo "  # 使用环境变量指定连接信息"
    echo "  ES_HOST=elasticsearch.example.com ES_PORT=9200 \\"
    echo "  ES_USER=elastic ES_PASS=password $0"
    echo
    echo "  # 过滤特定模式且大小小于 30mb 的索引"
    echo "  $0 --pattern 2025.05 --max-size 30mb"
    echo
}

# 参数解析
while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            show_help
            exit 0
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --table)
            TABLE_FORMAT=true
            shift
            ;;
        --pattern)
            if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                PATTERN="$2"
                shift 2
            else
                echo "错误: --pattern 需要一个参数"
                exit 1
            fi
            ;;
        --max-size)
            if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                MAX_SIZE_LIMIT="$2"
                shift 2
            else
                echo "错误: --max-size 需要一个参数"
                exit 1
            fi
            ;;
        *)
            echo "错误: 未知参数 $1"
            show_help
            exit 1
            ;;
    esac
done

# 处理模式
if [ -z "$PATTERN" ]; then
    PATTERN="*"
elif [[ "$PATTERN" != *"*"* ]]; then
    # 如果不包含通配符，默认进行包含匹配
    PATTERN="*${PATTERN}*"
fi

# 大小转换函数
parse_size() {
    local input=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    local number=$(echo "$input" | sed 's/[^0-9]*//g')
    local unit=$(echo "$input" | sed 's/[0-9]*//g')
    
    if [ -z "$number" ]; then echo 0; return; fi

    case "$unit" in
        k|kb) echo "$((number * 1024))" ;;
        m|mb) echo "$((number * 1024 * 1024))" ;;
        g|gb) echo "$((number * 1024 * 1024 * 1024))" ;;
        *) echo "$number" ;;
    esac
}

# 格式化大小函数
human_size() {
    local bytes=$1
    if [ "$bytes" -lt 1024 ]; then
        echo "${bytes}b"
    elif [ "$bytes" -lt 1048576 ]; then
        echo "$((bytes / 1024))kb"
    elif [ "$bytes" -lt 1073741824 ]; then
        echo "$((bytes / 1048576))mb"
    else
        echo "$((bytes / 1073741824))gb"
    fi
}

# 如果指定了大小限制，计算字节数
MAX_BYTES=0
if [ -n "$MAX_SIZE_LIMIT" ]; then
    MAX_BYTES=$(parse_size "$MAX_SIZE_LIMIT")
fi

# 构建基础 URL
BASE_URL="http://${ES_HOST}:${ES_PORT}/_cat/indices/${PATTERN}"

# 构建命令
if [ -n "$MAX_SIZE_LIMIT" ] || [ "$TABLE_FORMAT" = true ]; then
    # 如果需要过滤大小或者是表格模式，我们需要详细信息
    # 如果要过滤大小，强制使用 bytes=b 以便比较
    PARAMS="h=index,status,health,docs.count,store.size,creation.date.string&s=index"
    
    if [ -n "$MAX_SIZE_LIMIT" ]; then
        PARAMS="${PARAMS}&bytes=b"
    fi

    CMD="curl -X GET ${AUTH} -H \"Content-Type: application/json\" \"${BASE_URL}?${PARAMS}\" -s"
else
    # 简单模式且无大小限制，只获取名字
    CMD="curl -X GET ${AUTH} -H \"Content-Type: application/json\" \"${BASE_URL}?h=index\" -s | sort"
fi

# 打印表格头部的函数
print_table_header() {
    printf "%-40s | %-8s | %-7s | %-12s | %-10s | %-20s\n" \
        "索引名称" "状态" "健康值" "文档数" "存储大小" "创建时间"
    printf "%s\n" "----------------------------------------+----------+---------+--------------+------------+----------------------"
}

if [ "$DRY_RUN" = true ]; then
    echo "模拟运行模式，将执行以下命令（使用环境变量）："
    echo "$CMD" | sed 's/-u [^[:space:]]* /-u $ES_USER:$ES_PASS /g'
else
    if [ "$TABLE_FORMAT" = true ]; then
        echo "正在获取索引详细信息..."
        echo
        print_table_header
        
        eval "$CMD" | while read -r index status health docs_count size creation_date; do
            # 大小过滤
            if [ -n "$MAX_SIZE_LIMIT" ]; then
                # size 现在是字节，需要确保是数字
                if [[ ! "$size" =~ ^[0-9]+$ ]]; then
                    continue
                fi
                
                if [ "$size" -ge "$MAX_BYTES" ]; then
                    continue
                fi
                # 转换回人类可读格式用于显示
                display_size=$(human_size "$size")
            else
                display_size="$size"
            fi
            
            printf "%-40s | %-8s | %-7s | %12s | %10s | %-20s\n" \
                "$index" "$status" "$health" "$docs_count" "$display_size" "$creation_date"
        done
        echo
    else
        # 简单模式
        if [ -n "$MAX_SIZE_LIMIT" ]; then
            # 需要过滤大小，但只显示名字
            eval "$CMD" | while read -r index status health docs_count size creation_date; do
                if [[ "$size" =~ ^[0-9]+$ ]] && [ "$size" -lt "$MAX_BYTES" ]; then
                    echo "$index"
                fi
            done
        else
            echo "正在获取索引列表..."
            echo "----------------------------------------"
            eval "$CMD"
            echo "----------------------------------------"
        fi
    fi
fi 