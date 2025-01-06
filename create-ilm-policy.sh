#!/bin/bash

# 显示帮助信息的函数
show_help() {
    echo "功能: 创建或更新 Elasticsearch 索引生命周期管理(ILM)策略"
    echo "      可以配置热/暖/冷/删除等不同阶段的触发条件"
    echo
    echo "用法: $0 [选项] <policy-name>"
    echo
    echo "选项:"
    echo "  --help                显示此帮助信息"
    echo "  --disable-rollover    禁用 rollover"
    echo "  --hot-max-size       热阶段最大存储大小 (例如: 50gb)"
    echo "  --hot-max-primary-size 热阶段最大主分片大小 (例如: 50gb)"
    echo "  --hot-max-age        热阶段最大时间 (例如: 30d)"
    echo "  --warm-min-age       暖阶段最小时间 (例如: 60d)"
    echo "  --delete-min-age     删除阶段最小时间 (例如: 90d)"
    echo "  --dry-run             仅打印将要执行的命令，不实际执行"
    echo
    echo "环境变量:"
    echo "  ES_HOST              Elasticsearch 主机地址 (默认: localhost)"
    echo "  ES_PORT              Elasticsearch 端口 (默认: 9200)"
    echo "  ES_USER              Elasticsearch 用户名"
    echo "  ES_PASS              Elasticsearch 密码"
    echo
    echo "示例:"
    echo "  1. 启用 rollover，设置主分片大小限制:"
    echo "     $0 \\"
    echo "       --hot-max-size 50gb \\"
    echo "       --hot-max-primary-size 25gb \\"
    echo "       --hot-max-age 30d \\"
    echo "       my-policy"
    echo
    echo "  2. 禁用 rollover:"
    echo "     $0 \\"
    echo "       --disable-rollover \\"
    echo "       --warm-min-age 45d \\"
    echo "       --delete-min-age 90d \\"
    echo "       my-policy"
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
POLICY_NAME=""
HOT_MAX_SIZE=""
HOT_MAX_PRIMARY_SIZE=""
HOT_MAX_AGE=""
WARM_MIN_AGE=""
DELETE_MIN_AGE=""
DISABLE_ROLLOVER=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            show_help
            ;;
        --disable-rollover)
            DISABLE_ROLLOVER="true"
            shift
            ;;
        --hot-max-size)
            HOT_MAX_SIZE="$2"
            shift 2
            ;;
        --hot-max-primary-size)
            HOT_MAX_PRIMARY_SIZE="$2"
            shift 2
            ;;
        --hot-max-age)
            HOT_MAX_AGE="$2"
            shift 2
            ;;
        --warm-min-age)
            WARM_MIN_AGE="$2"
            shift 2
            ;;
        --delete-min-age)
            DELETE_MIN_AGE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            POLICY_NAME="$1"
            shift
            ;;
    esac
done

# 验证必需参数
if [ -z "$POLICY_NAME" ]; then
    echo "错误: 必须指定 policy 名称"
    show_help
fi

# 显示策略信息
echo "策略配置:"
echo "  策略名称: ${POLICY_NAME}"
if [ -z "$DISABLE_ROLLOVER" ]; then
    echo "  Rollover: 启用"
    echo "  热阶段最大存储: ${HOT_MAX_SIZE:-50gb}"
    echo "  热阶段最大主分片大小: ${HOT_MAX_PRIMARY_SIZE:-未设置}"
    echo "  热阶段最大时间: ${HOT_MAX_AGE:-30d}"
else
    echo "  Rollover: 禁用"
fi
echo "  暖阶段最小时间: ${WARM_MIN_AGE:-60d}"
echo "  删除阶段最小时间: ${DELETE_MIN_AGE:-90d}"
echo

# 构建 policy JSON
if [ -z "$DISABLE_ROLLOVER" ]; then
    # 启用 rollover 的配置
    POLICY_JSON=$(cat << EOF
{
  "policy": {
    "phases": {
      "hot": {
        "actions": {
          "rollover": {
            "max_size": "${HOT_MAX_SIZE:-50gb}",
            "max_primary_shard_size": "${HOT_MAX_PRIMARY_SIZE}",
            "max_age": "${HOT_MAX_AGE:-30d}"
          }
        }
      },
      "warm": {
        "min_age": "${WARM_MIN_AGE:-60d}",
        "actions": {
          "shrink": {
            "number_of_shards": 1
          },
          "forcemerge": {
            "max_num_segments": 1
          }
        }
      },
      "delete": {
        "min_age": "${DELETE_MIN_AGE:-90d}",
        "actions": {
          "delete": {}
        }
      }
    }
  }
}
EOF
)
else
    # 禁用 rollover 的配置
    POLICY_JSON=$(cat << EOF
{
  "policy": {
    "phases": {
      "hot": {
        "actions": {}
      },
      "warm": {
        "min_age": "${WARM_MIN_AGE:-60d}",
        "actions": {
          "shrink": {
            "number_of_shards": 1
          },
          "forcemerge": {
            "max_num_segments": 1
          }
        }
      },
      "delete": {
        "min_age": "${DELETE_MIN_AGE:-90d}",
        "actions": {
          "delete": {}
        }
      }
    }
  }
}
EOF
)
fi

# 修改发送请求部分
echo "正在创建/更新 ILM 策略..."
CURL_CMD="curl -X PUT ${AUTH} -H \"Content-Type: application/json\" \
    \"http://${ES_HOST}:${ES_PORT}/_ilm/policy/${POLICY_NAME}\" \
    -d '${POLICY_JSON}'"

if [ "$DRY_RUN" = true ]; then
    echo "模拟运行模式，将执行以下命令（使用环境变量）："
    # 替换认证信息为环境变量
    echo "$CURL_CMD" | sed 's/-u [^[:space:]]* /-u $ES_USER:$ES_PASS /g'
else
    eval "$CURL_CMD" -s | jq '.' || echo "请求失败: $?"
fi 