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
INDICES_TO_IMPORT=()
IMPORT_ALL=false
IMPORT_AND_DELETE=false

# 显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo
    echo "安全地导入 Elasticsearch 的 Dangling 索引 (Re-import Dangling Indices)"
    echo
    echo "环境变量:"
    echo "  ES_HOST            Elasticsearch 主机地址 (默认: localhost)"
    echo "  ES_PORT            Elasticsearch 端口 (默认: 9200)"
    echo "  ES_USER            Elasticsearch 用户名"
    echo "  ES_PASS            Elasticsearch 密码"
    echo
    echo "选项:"
    echo "  --indices <list>   要导入的索引名称列表，用逗号分隔"
    echo "  --all              导入所有检测到的 Dangling 索引"
    echo "  --waiting <sec>    导入后等待检查集群健康的时间（秒），默认 10"
    echo "  --import-and-delete 导入成功且状态正常后，立即删除该索引 (用于清理)"
    echo "  --no-confirm       跳过人工确认步骤"
    echo "  --dry-run          仅打印将要执行的命令，不实际执行"
    echo "  --help             显示此帮助信息"
    echo
    echo "输入:"
    echo "  可以通过标准输入 (stdin) 提供索引名称列表，每行一个"
    echo
    echo "示例:"
    echo "  # 导入所有 dangling 索引"
    echo "  $0 --all"
    echo
    echo "  # 导入指定索引"
    echo "  $0 --indices my-index-1,my-index-2"
    echo
}

# 校验索引名是否合法
validate_index_name() {
    local name="$1"
    if [[ -z "$name" ]]; then return 1; fi
    if [[ "$name" =~ [[:space:],\"*+/\|] ]]; then return 1; fi
    return 0
}

# 检查集群健康状态 (复用 strict 逻辑)
check_cluster_health() {
    local health_url="http://${ES_HOST}:${ES_PORT}/_cluster/health"
    local response
    
    if [ "$DRY_RUN" = true ]; then
        echo "[Dry Run] 检查集群健康状态 (由于是 Dry Run，假定健康)..."
        return 0
    fi

    echo "正在检查集群健康状态..."
    while true; do
        response=$(curl -X GET $AUTH -s "$health_url")
        status=$(echo "$response" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
        relocating=$(echo "$response" | grep -o '"relocating_shards":[0-9]*' | cut -d':' -f2)
        initializing=$(echo "$response" | grep -o '"initializing_shards":[0-9]*' | cut -d':' -f2)
        pending=$(echo "$response" | grep -o '"number_of_pending_tasks":[0-9]*' | cut -d':' -f2)
        
        # 严格健康检查：Green，无搬迁，无初始化，低Pending
        if [ "$status" = "green" ] && [ "$relocating" -eq 0 ] && [ "$initializing" -eq 0 ] && [ "$pending" -lt 50 ]; then
            echo "集群健康状态良好: Status=$status, Relocating=$relocating, Initializing=$initializing, PendingTasks=$pending"
            return 0
        else
            echo "集群状态未就绪 (Status=$status, Relocating=$relocating, Initializing=$initializing, Pending=$pending)。等待恢复..."
            sleep 5
        fi
    done
}

# 检查 Master 响应能力 (不关注集群颜色或分片状态，只确保 Master 不忙)
# 用于 --import-and-delete 场景，避免因导入的坏索引导致 Red 状态而死锁无法删除
check_master_responsive() {
    local health_url="http://${ES_HOST}:${ES_PORT}/_cluster/health"
    local response
    
    if [ "$DRY_RUN" = true ]; then return 0; fi

    echo "正在检查 Master 负载状态..."
    while true; do
        response=$(curl -X GET $AUTH -s "$health_url")
        # 只检查 pending tasks
        pending=$(echo "$response" | grep -o '"number_of_pending_tasks":[0-9]*' | cut -d':' -f2)
        
        # 只要任务队列不积压，就认为可以执行删除操作
        if [ "$pending" -lt 50 ]; then
            echo "Master 负载正常 (PendingTasks=$pending)。"
            return 0
        else
            echo "Master 繁忙 (Pending=$pending)。等待..."
            sleep 3
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
        --all)
            IMPORT_ALL=true
            shift
            ;;
        --import-and-delete)
            IMPORT_AND_DELETE=true
            shift
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

# 获取 Dangling 索引列表并解析
echo "正在获取 Dangling 索引列表..."
DANGLING_RESP=$(curl -X GET $AUTH -s "http://${ES_HOST}:${ES_PORT}/_dangling")

# 使用 grep/sed 简单解析 JSON 获取 Name 和 UUID 对应关系
parse_dangling_python() {
    python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
    items = []
    # 递归查找 dangling_indices key，或者尝试直接访问
    # 结构通常是 {"dangling_indices": [ ... ]} 或者包含 _nodes 等信息的完整结构
    
    if isinstance(data, dict):
        if "dangling_indices" in data:
            items = data["dangling_indices"]
        else:
             # 如果没有直接找到，也许是直接的列表？
             items = []
    elif isinstance(data, list):
        items = data
    
    for item in items:
        # 确保也是字典
        if isinstance(item, dict):
            name = item.get("index_name")
            uuid = item.get("index_uuid")
            if name and uuid:
                print(f"{name} {uuid}")
except Exception as e:
    # 打印到 stderr 防止污染 stdout 管道
    print(f"JSON Parse Error: {e}", file=sys.stderr)
    pass
'
}

# 构建 Name -> UUID 映射 (使用双数组代替 map，兼容 bash 3.2)
AVAILABLE_NAMES=()
AVAILABLE_UUIDS=()

# 解析 JSON 并将结果存入变量，避免 Process Substitution 在某些环境下的问题
PARSED_OUTPUT=$(echo "$DANGLING_RESP" | parse_dangling_python)

# 处理输入到数组 (使用 Here String <<<)
while read -r name uuid; do
    if [ -n "$name" ] && [ -n "$uuid" ]; then
        AVAILABLE_NAMES+=("$name")
        AVAILABLE_UUIDS+=("$uuid")
    fi
done <<< "$PARSED_OUTPUT"

TOTAL_DANGLING=${#AVAILABLE_NAMES[@]}
echo "发现 $TOTAL_DANGLING 个 Dangling 索引。"

if [ "$TOTAL_DANGLING" -eq 0 ]; then
    echo "没有发现任何 Dangling 索引。"
    exit 0
fi

# 确定要导入的目标列表
TARGET_NAMES=()

if [ "$IMPORT_ALL" = true ]; then
    TARGET_NAMES=("${AVAILABLE_NAMES[@]}")
elif [ -n "$INDICES_ARG" ]; then
    IFS=',' read -ra ADDR <<< "$INDICES_ARG"
    for i in "${ADDR[@]}"; do
        if validate_index_name "$i"; then
            TARGET_NAMES+=("$i")
        fi
    done
else
    # 检查标准输入
    if [ -t 0 ]; then
        echo "错误: 未指定 --indices 或 --all，且没有标准输入"
        show_help
        exit 1
    fi
    while IFS= read -r line; do
        line=$(echo "$line" | xargs)
        if validate_index_name "$line"; then
            TARGET_NAMES+=("$line")
        fi
    done
fi

# 验证目标索引是否存在于 Dangling 列表中，获取 UUID
for name in "${TARGET_NAMES[@]}"; do
    found_uuid=""
    # 在 parallel arrays 中查找
    for (( i=0; i<${#AVAILABLE_NAMES[@]}; i++ )); do
        if [ "${AVAILABLE_NAMES[$i]}" = "$name" ]; then
            found_uuid="${AVAILABLE_UUIDS[$i]}"
            break
        fi
    done
    
    if [ -n "$found_uuid" ]; then
        INDICES_TO_IMPORT+=("$name:$found_uuid")
    else
        echo "警告: 索引 '$name' 不在 Dangling 列表中，跳过。"
    fi
done

if [ ${#INDICES_TO_IMPORT[@]} -eq 0 ]; then
    echo "没有待处理的有效索引。"
    exit 0
fi

# 步骤 1: 全局确认
echo "即将导入以下 ${#INDICES_TO_IMPORT[@]} 个索引:"
for item in "${INDICES_TO_IMPORT[@]}"; do
    echo "  - ${item%%:*} (UUID: ${item#*:})"
done
echo

if [ "$NO_CONFIRM" = false ]; then
    if [ -t 0 ]; then
        read -p "确认要导入以上所有索引吗? (y/N) " confirm_all
    elif [ -c /dev/tty ]; then
        echo -n "确认要导入以上所有索引吗? (y/N) " > /dev/tty
        read confirm_all < /dev/tty
    else
        echo "错误: 无法获取用户输入确认"
        exit 1
    fi
    
    confirm_all=$(echo "$confirm_all" | xargs)
    if [[ ! "$confirm_all" =~ ^[Yy]$ ]]; then
        echo "操作已取消。"
        exit 0
    fi
else
    echo "已跳过确认 (--no-confirm)，准备开始导入。"
fi

# 捕捉 Ctrl+C
trap 'echo -e "\n操作被用户中断"; exit 1' SIGINT

# 步骤 2: 逐个导入
count=0
total=${#INDICES_TO_IMPORT[@]}

for item in "${INDICES_TO_IMPORT[@]}"; do
    index_name="${item%%:*}"
    index_uuid="${item#*:}"
    ((count++))
    
    echo "[$count/$total] 处理索引: $index_name (UUID: $index_uuid)"

    # 单个确认
    if [ "$NO_CONFIRM" = false ]; then
        if [ -t 0 ]; then
             read -p "确认导入索引 '$index_name'? (y/N) " confirm_idx
        elif [ -c /dev/tty ]; then
             echo -n "确认导入索引 '$index_name'? (y/N) " > /dev/tty
             read confirm_idx < /dev/tty
        else
             confirm_idx="n"
        fi
        
        confirm_idx=$(echo "$confirm_idx" | xargs)
        if [[ ! "$confirm_idx" =~ ^[Yy]$ ]]; then
            echo "跳过索引 $index_name"
            continue
        fi
    fi

    # 步骤 2.1: 导入前检查集群健康
    check_cluster_health

    # 执行导入
    if [ "$DRY_RUN" = true ]; then
        echo "[Dry Run] curl -X POST $AUTH \"http://${ES_HOST}:${ES_PORT}/_dangling/${index_uuid}?accept_data_loss=true\""
    else
        echo "正在导入 $index_name ..."
        http_code=$(curl -X POST $AUTH -s -o /dev/null -w "%{http_code}" "http://${ES_HOST}:${ES_PORT}/_dangling/${index_uuid}?accept_data_loss=true")
        
        if [ "$http_code" == "200" ]; then
            echo "索引 $index_name 导入成功。"
            
            # 导入并删除逻辑
            if [ "$IMPORT_AND_DELETE" = true ]; then
                 echo "正在等待导入动作完成..."
                 sleep 2
                 
                 # 改用轻量级检查，避免因导入的索引是 RED 而导致死锁
                 check_master_responsive
                 
                 echo "准备删除已导入的索引: $index_name (忽略索引健康状态)"
                 echo "正在删除 $index_name ..."
                 
                 del_code=$(curl -X DELETE $AUTH -s -o /dev/null -w "%{http_code}" "http://${ES_HOST}:${ES_PORT}/$index_name")
                 if [ "$del_code" == "200" ]; then
                     echo "索引 $index_name 已成功删除。"
                 else
                     echo "删除 $index_name 失败，HTTP: $del_code"
                 fi
            fi
            
        else
            echo "导入 $index_name 失败，HTTP 状态码: $http_code"
            echo "警告: 操作可能未成功。"
        fi

        # 导入后等待
        if [ "$count" -lt "$total" ]; then
             echo "操作冷却，等待 $WAIT_TIME 秒..."
             sleep "$WAIT_TIME"
        fi
    fi
    echo "----------------------------------------"
done

echo "所有操作完成。"
