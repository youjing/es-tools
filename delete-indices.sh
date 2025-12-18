#!/bin/bash

# 从环境变量获取配置
ES_HOST=${ES_HOST:-"localhost"}
ES_PORT=${ES_PORT:-"9200"}
AUTH=""
if [ ! -z "$ES_USER" ] && [ ! -z "$ES_PASS" ]; then
    AUTH="-u $ES_USER:$ES_PASS"
fi

# 默认配置
WAIT_TIME=10
NO_CONFIRM=false
DRY_RUN=false
INDICES_ARG=""
INDICES_TO_DELETE=()

# 显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo
    echo "安全地删除 Elasticsearch 索引"
    echo
    echo "环境变量:"
    echo "  ES_HOST            Elasticsearch 主机地址 (默认: localhost)"
    echo "  ES_PORT            Elasticsearch 端口 (默认: 9200)"
    echo "  ES_USER            Elasticsearch 用户名"
    echo "  ES_PASS            Elasticsearch 密码"
    echo
    echo "选项:"
    echo "  --indices <list>   要删除的索引列表，用逗号分隔"
    echo "  --waiting <sec>    删除后等待检查集群健康的时间（秒），默认 10"
    echo "  --no-confirm       跳过人工确认步骤（包括删除前的操作确认和每个索引的删除确认）"
    echo "  --dry-run          仅打印将要执行的命令，不实际执行"
    echo "  --help             显示此帮助信息"
    echo
    echo "输入:"
    echo "  可以通过标准输入 (stdin) 提供索引列表，每行一个索引名"
    echo
    echo "示例:"
    echo "  # 删除指定索引"
    echo "  $0 --indices index1,index2"
    echo
    echo "  # 从 list-indices.sh 的输出中删除"
    echo "  ./list-indices.sh --pattern 'test-*' | $0"
    echo
}

# 校验索引名是否合法
validate_index_name() {
    local name="$1"
    # 简单的非空校验，且不能包含非法字符 (ES索引不能包含: , ", *, +, /, <, >, |, space, comma)
    # 这里只做基础校验，防止空行或明显错误
    if [[ -z "$name" ]]; then
        return 1
    fi
    if [[ "$name" =~ [[:space:],\"*+/\|] ]]; then
        return 1
    fi
    return 0
}

# 检查集群健康状态
check_cluster_health() {
    local health_url="http://${ES_HOST}:${ES_PORT}/_cluster/health"
    local response
    
    if [ "$DRY_RUN" = true ]; then
        echo "[Dry Run] 检查集群健康状态..."
        return 0
    fi

    echo "正在检查集群健康状态..."
    while true; do
        response=$(curl -X GET $AUTH -s "$health_url")
        status=$(echo "$response" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
        relocating=$(echo "$response" | grep -o '"relocating_shards":[0-9]*' | cut -d':' -f2)
        initializing=$(echo "$response" | grep -o '"initializing_shards":[0-9]*' | cut -d':' -f2)
        pending=$(echo "$response" | grep -o '"number_of_pending_tasks":[0-9]*' | cut -d':' -f2)
        
        # 严格的健康检查条件
        # 1. 状态必须为 green (或者 yellow, 如果允许的话，但通常 green 最安全)
        # 2. 没有正在搬迁的分片 (relocating_shards == 0)
        # 3. 没有正在初始化的分片 (initializing_shards == 0)
        # 4. 挂起任务数较低 (例如 < 50，防止主节点过载)
        
        if [ "$status" = "green" ] && [ "$relocating" -eq 0 ] && [ "$initializing" -eq 0 ] && [ "$pending" -lt 50 ]; then
            echo "集群健康状态良好: Status=$status, Relocating=$relocating, Initializing=$initializing, PendingTasks=$pending"
            return 0
        else
            echo "集群状态未就绪 (Status=$status, Relocating=$relocating, Initializing=$initializing, Pending=$pending)。等待恢复..."
            sleep 5
        fi
    done
}

# 参数解析
while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            show_help
            exit 0
            ;;
        --indices)
            if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                INDICES_ARG="$2"
                shift 2
            else
                echo "错误: --indices 需要一个参数"
                exit 1
            fi
            ;;
        --waiting)
            if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                WAIT_TIME="$2"
                shift 2
            else
                echo "错误: --waiting 需要一个参数"
                exit 1
            fi
            ;;
        --no-confirm)
            NO_CONFIRM=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            echo "错误: 未知参数 $1"
            show_help
            exit 1
            ;;
    esac
done

# 获取需要删除的索引列表
if [ -n "$INDICES_ARG" ]; then
    IFS=',' read -ra ADDR <<< "$INDICES_ARG"
    for i in "${ADDR[@]}"; do
        if validate_index_name "$i"; then
            INDICES_TO_DELETE+=("$i")
        else
            echo "警告:忽略无效的索引名 '$i'"
        fi
    done
else
    # 检查是否有 stdin 输入
    if [ -t 0 ]; then
        echo "错误: 未指定 --indices 且没有标准输入"
        show_help
        exit 1
    fi
    
    # 读取标准输入
    while IFS= read -r line; do
        # 去除前后空白
        line=$(echo "$line" | xargs)
        if validate_index_name "$line"; then
            INDICES_TO_DELETE+=("$line")
        elif [ -n "$line" ]; then
             echo "警告:忽略无效的索引名 '$line'"
        fi
    done
fi

if [ ${#INDICES_TO_DELETE[@]} -eq 0 ]; then
    echo "没有找到需要删除的有效索引。"
    exit 0
fi

# 步骤 1: 全局确认
echo "即将删除以下 ${#INDICES_TO_DELETE[@]} 个索引:"
for index in "${INDICES_TO_DELETE[@]}"; do
    echo "  - $index"
done
echo

if [ "$NO_CONFIRM" = false ]; then
    if [ -t 0 ]; then
        read -p "确认要删除以上所有索引吗? (y/N) " confirm_all
    elif [ -c /dev/tty ]; then
        echo -n "确认要删除以上所有索引吗? (y/N) " > /dev/tty
        read confirm_all < /dev/tty
    else
        echo "错误: 无法获取用户输入进行确认 (非交互式终端且未指定 --no-confirm)"
        exit 1
    fi

    # 去除空白
    confirm_all=$(echo "$confirm_all" | xargs)

    if [[ ! "$confirm_all" =~ ^[Yy]$ ]]; then
        echo "操作已取消。"
        exit 0
    fi
else
    echo "已跳过确认 (--no-confirm)，准备开始删除。"
fi

# 捕捉 Ctrl+C
trap 'echo -e "\n操作被用户中断"; exit 1' SIGINT

# 步骤 2: 逐个删除
count=0
total=${#INDICES_TO_DELETE[@]}

for index in "${INDICES_TO_DELETE[@]}"; do
    ((count++))
    echo "[$count/$total] 处理索引: $index"

    # 单个索引确认
    if [ "$NO_CONFIRM" = false ]; then
        if [ -t 0 ]; then
            read -p "确认删除索引 '$index'? (y/N) " confirm_index
        elif [ -c /dev/tty ]; then
            echo -n "确认删除索引 '$index'? (y/N) " > /dev/tty
            read confirm_index < /dev/tty
        else
            confirm_index="n"
        fi
        
        # 去除空白
        confirm_index=$(echo "$confirm_index" | xargs)

        if [[ ! "$confirm_index" =~ ^[Yy]$ ]]; then
            echo "跳过索引 $index"
            continue
        fi
    fi

    # 步骤 2.1: 执行前先检查集群状态
    # 确保当前集群能够承载删除操作带来的元数据更新压力
    check_cluster_health

    # 执行删除
    if [ "$DRY_RUN" = true ]; then
        echo "[Dry Run] curl -X DELETE $AUTH \"http://${ES_HOST}:${ES_PORT}/$index\""
    else
        echo "正在删除 $index ..."
        http_code=$(curl -X DELETE $AUTH -s -o /dev/null -w "%{http_code}" "http://${ES_HOST}:${ES_PORT}/$index")
        
        if [ "$http_code" == "200" ]; then
            echo "索引 $index 删除成功。"
        elif [ "$http_code" == "404" ]; then
             echo "索引 $index 不存在 (404)。"
        else
            echo "删除 $index 失败，HTTP 状态码: $http_code"
            echo "警告: 删除操作可能未成功。"
        fi
        
        # 删除后等待，让集群有喘息之机，处理刚刚产生的变更
        if [ "$count" -lt "$total" ]; then
             echo "操作冷却，等待 $WAIT_TIME 秒..."
             sleep "$WAIT_TIME"
        fi
    fi
    
    echo "----------------------------------------"
done
