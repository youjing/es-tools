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
    echo "从 Elasticsearch 的索引模板(包括 Legacy 和 Composable)中提取所有的 index patterns"
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
    echo "  --table           以表格格式显示输出结果"
    echo
    echo "示例:"
    echo "  # 使用默认配置"
    echo "  $0"
    echo
    echo "  # 使用表格格式显示"
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

# 构建获取 Legacy 模板的 curl 命令
LEGACY_CURL_CMD="curl -X GET ${AUTH} -H \"Content-Type: application/json\" \
    \"http://${ES_HOST}:${ES_PORT}/_template\" \
    -s | jq -r 'to_entries | .[] | .value.index_patterns[]'"

# 构建获取 Composable 模板的 curl 命令
COMPOSABLE_CURL_CMD="curl -X GET ${AUTH} -H \"Content-Type: application/json\" \
    \"http://${ES_HOST}:${ES_PORT}/_index_template\" \
    -s | jq -r '.index_templates[].index_template.index_patterns[]'"

if [ "$DRY_RUN" = true ]; then
    echo "模拟运行模式，将执行以下命令（使用环境变量）："
    echo "# 获取 Legacy 模板的 patterns:"
    echo "$LEGACY_CURL_CMD" | sed 's/-u [^[:space:]]* /-u $ES_USER:$ES_PASS /g'
    echo
    echo "# 获取 Composable 模板的 patterns:"
    echo "$COMPOSABLE_CURL_CMD" | sed 's/-u [^[:space:]]* /-u $ES_USER:$ES_PASS /g'
else
    echo "正在获取所有 index patterns..."
    echo "----------------------------------------"
    echo "从 Legacy 模板中获取的 patterns:"
    eval "$LEGACY_CURL_CMD" || echo "Legacy 模板请求失败: $?"
    echo
    echo "从 Composable 模板中获取的 patterns:"
    eval "$COMPOSABLE_CURL_CMD" || echo "Composable 模板请求失败: $?"
    echo "----------------------------------------"
    
    # 合并并去重所有 patterns
    echo
    echo "所有唯一的 patterns:"
    {
        eval "$LEGACY_CURL_CMD"
        eval "$COMPOSABLE_CURL_CMD"
    } | sort -u
    echo "----------------------------------------"
fi 