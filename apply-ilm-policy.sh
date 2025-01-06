#!/bin/bash

# 显示帮助信息的函数
show_help() {
    echo "功能: 为已存在的索引应用 ILM 策略"
    echo "      可以将 ILM 策略应用到匹配特定模式的所有索引"
    echo
    echo "用法: $0 [选项] <policy-name> <index-pattern>"
    echo
    echo "选项:"
    echo "  --help                显示此帮助信息"
    echo "  --alias              创建别名 (可选)"
    echo
    echo "环境变量:"
    echo "  ES_HOST              Elasticsearch 主机地址 (默认: localhost)"
    echo "  ES_PORT              Elasticsearch 端口 (默认: 9200)"
    echo "  ES_USER              Elasticsearch 用户名"
    echo "  ES_PASS              Elasticsearch 密码"
    echo
    echo "示例:"
    echo "  # 为所有日志索引应用 ILM 策略"
    echo "  $0 hot-warm-delete 'logs-*'"
    echo
    echo "  # 应用 ILM 策略并创建别名"
    echo "  $0 --alias logs hot-warm-delete 'logs-2024-*'"
    echo
    echo "  # 在远程 ES 上应用 ILM 策略"
    echo "  ES_HOST=es.example.com ES_PORT=9200 \\"
    echo "  ES_USER=admin ES_PASS=secret \\"
    echo "  $0 hot-warm-delete 'metrics-*'"
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
INDEX_PATTERN=""
POLICY_NAME=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            show_help
            ;;
        *)
            if [ -z "$INDEX_PATTERN" ]; then
                INDEX_PATTERN="$1"
            elif [ -z "$POLICY_NAME" ]; then
                POLICY_NAME="$1"
            fi
            shift
            ;;
    esac
done

# 验证必需参数
if [ -z "$INDEX_PATTERN" ] || [ -z "$POLICY_NAME" ]; then
    echo "错误: 必须指定索引模式和 policy 名称"
    show_help
fi

# 显示应用信息
echo "应用配置:"
echo "  索引模式: ${INDEX_PATTERN}"
echo "  ILM策略: ${POLICY_NAME}"
echo

# 构建更新 JSON
UPDATE_JSON=$(cat << EOF
{
  "lifecycle": {
    "name": "${POLICY_NAME}"
  }
}
EOF
)

# 修改发送请求部分
CURL_CMD="curl -X PUT ${AUTH} -H \"Content-Type: application/json\" \
    \"http://${ES_HOST}:${ES_PORT}/${INDEX_PATTERN}/_settings\" \
    -d '{\"index.lifecycle.name\":\"${POLICY_NAME}\"}'"

if [ "$DRY_RUN" = true ]; then
    echo "模拟运行模式，将执行以下命令（使用环境变量）："
    # 替换认证信息为环境变量
    echo "$CURL_CMD" | sed 's/-u [^[:space:]]* /-u $ES_USER:$ES_PASS /g'
else
    eval "$CURL_CMD" -s | jq '.' || echo "请求失败: $?"
fi 