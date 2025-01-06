#!/bin/bash

# 显示帮助信息的函数
show_help() {
    echo "功能: 创建或更新 Elasticsearch 索引模板"
    echo "      可以设置分片数、副本数，并可选择性地关联 ILM 策略"
    echo
    echo "用法: $0 [选项] <template-name> <index-pattern>"
    echo
    echo "选项:"
    echo "  --help                显示此帮助信息"
    echo "  --policy-name         ILM policy 名称"
    echo "  --shards              主分片数量 (默认: 1)"
    echo "  --replicas            副本数量 (默认: 1)"
    echo "  --dry-run             仅打印将要执行的命令，不实际执行"
    echo
    echo "环境变量:"
    echo "  ES_HOST              Elasticsearch 主机地址 (默认: localhost)"
    echo "  ES_PORT              Elasticsearch 端口 (默认: 9200)"
    echo "  ES_USER              Elasticsearch 用户名"
    echo "  ES_PASS              Elasticsearch 密码"
    echo
    echo "示例:"
    echo "  # 创建基本索引模板"
    echo "  $0 logs-template 'logs-*'"
    echo
    echo "  # 创建带有 ILM 策略的索引模板"
    echo "  $0 --policy-name hot-warm-delete logs-template 'logs-*'"
    echo
    echo "  # 创建自定义分片和副本数的索引模板"
    echo "  $0 --shards 3 --replicas 2 metrics-template 'metrics-*'"
    echo
    echo "  # 使用环境变量连接远程 ES"
    echo "  ES_HOST=es.example.com ES_PORT=9200 \\"
    echo "  ES_USER=admin ES_PASS=secret \\"
    echo "  $0 logs-template 'logs-*'"
    exit 1
}

# 设置默认值
ES_HOST=${ES_HOST:-localhost}
ES_PORT=${ES_PORT:-9200}
AUTH=""

# 显示连接信息
echo "连接信息:"
echo "  ES 地址: ${ES_HOST}:${ES_PORT}"
[ ! -z "$ES_USER" ] && echo "  用户名: ${ES_USER}"
echo

# 如果设置了用户名和密码，添加认证信息
if [ ! -z "$ES_USER" ] && [ ! -z "$ES_PASS" ]; then
    AUTH="-u ${ES_USER}:${ES_PASS}"
fi

# 解析命令行参数
TEMPLATE_NAME=""
INDEX_PATTERN=""
POLICY_NAME=""
SHARDS="1"
REPLICAS="1"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            show_help
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --policy-name)
            POLICY_NAME="$2"
            shift 2
            ;;
        --shards)
            SHARDS="$2"
            shift 2
            ;;
        --replicas)
            REPLICAS="$2"
            shift 2
            ;;
        *)
            if [ -z "$TEMPLATE_NAME" ]; then
                TEMPLATE_NAME="$1"
            elif [ -z "$INDEX_PATTERN" ]; then
                INDEX_PATTERN="$1"
            fi
            shift
            ;;
    esac
done

# 验证必需参数
if [ -z "$TEMPLATE_NAME" ] || [ -z "$INDEX_PATTERN" ]; then
    echo "错误: 必须指定 template 名称和索引模式"
    show_help
fi

# 显示模板信息
echo "模板配置:"
echo "  模板名称: ${TEMPLATE_NAME}"
echo "  索引模式: ${INDEX_PATTERN}"
echo "  主分片数: ${SHARDS}"
echo "  副本数量: ${REPLICAS}"
[ ! -z "$POLICY_NAME" ] && echo "  ILM策略: ${POLICY_NAME}"
echo

# 构建 template JSON
TEMPLATE_JSON=$(cat << EOF
{
  "index_patterns": ["${INDEX_PATTERN}"],
  "settings": {
    "number_of_shards": ${SHARDS},
    "number_of_replicas": ${REPLICAS}
EOF
)

if [ ! -z "$POLICY_NAME" ]; then
    TEMPLATE_JSON+=",
    \"lifecycle\": {
      \"name\": \"${POLICY_NAME}\"
    }"
fi

TEMPLATE_JSON+="}
}"

# 发送请求到 Elasticsearch
echo "正在创建/更新索引模板..."
CURL_CMD="curl -X PUT ${AUTH} -H \"Content-Type: application/json\" \
    \"http://${ES_HOST}:${ES_PORT}/_template/${TEMPLATE_NAME}\" \
    -d '${TEMPLATE_JSON}'"

if [ "$DRY_RUN" = true ]; then
    echo "模拟运行模式，将执行以下命令（使用环境变量）："
    echo "$CURL_CMD" | sed 's/-u [^[:space:]]* /-u $ES_USER:$ES_PASS /g'
else
    eval "$CURL_CMD" -s | jq '.' || echo "请求失败: $?"
fi 