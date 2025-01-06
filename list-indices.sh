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
        *)
            echo "错误: 未知参数 $1"
            show_help
            exit 1
            ;;
    esac
done

# 构建获取索引列表的 curl 命令（简单格式）
INDICES_CURL_CMD_SIMPLE="curl -X GET ${AUTH} -H \"Content-Type: application/json\" \
    \"http://${ES_HOST}:${ES_PORT}/_cat/indices?h=index\" \
    -s | sort"

# 构建获取索引详细信息的 curl 命令（表格格式）
INDICES_CURL_CMD_TABLE="curl -X GET ${AUTH} -H \"Content-Type: application/json\" \
    \"http://${ES_HOST}:${ES_PORT}/_cat/indices?h=index,status,health,docs.count,store.size,creation.date.string&s=index\" \
    -s"

# 打印表格头部的函数
print_table_header() {
    printf "%-40s | %-8s | %-7s | %-12s | %-10s | %-20s\n" \
        "索引名称" "状态" "健康值" "文档数" "存储大小" "创建时间"
    printf "%s\n" "----------------------------------------+----------+---------+--------------+------------+----------------------"
}

if [ "$DRY_RUN" = true ]; then
    echo "模拟运行模式，将执行以下命令（使用环境变量）："
    if [ "$TABLE_FORMAT" = true ]; then
        echo "$INDICES_CURL_CMD_TABLE" | sed 's/-u [^[:space:]]* /-u $ES_USER:$ES_PASS /g'
    else
        echo "$INDICES_CURL_CMD_SIMPLE" | sed 's/-u [^[:space:]]* /-u $ES_USER:$ES_PASS /g'
    fi
else
    if [ "$TABLE_FORMAT" = true ]; then
        echo "正在获取索引详细信息..."
        echo
        print_table_header
        eval "$INDICES_CURL_CMD_TABLE" | while read -r index status health docs_count size creation_date; do
            printf "%-40s | %-8s | %-7s | %12s | %10s | %-20s\n" \
                "$index" "$status" "$health" "$docs_count" "$size" "$creation_date"
        done
        echo
    else
        echo "正在获取索引列表..."
        echo "----------------------------------------"
        eval "$INDICES_CURL_CMD_SIMPLE"
        echo "----------------------------------------"
    fi
fi 