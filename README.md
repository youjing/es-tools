# Elasticsearch Tools for Operation

这是一组用于 Elasticsearch 运维管理的实用脚本工具集。目前主要功能包括创建索引模板、管理索引生命周期策略(ILM)以及分析现有索引模式等。

## 环境要求
- bash 环境
- curl 命令行工具
- jq 命令行 JSON 处理工具


## 注意事项
- 在执行脚本前，请确保已经备份重要数据
- 建议在测试环境验证脚本效果后再在生产环境使用
- 请确保具有足够的 Elasticsearch 操作权限


## 环境变量

本工程中的脚本依赖于下列环境变量，请确保环境变量正确设置：

- ES_HOST - Elasticsearch 主机地址 (默认: localhost)
- ES_PORT - Elasticsearch 端口 (默认: 9200)
- ES_USER - Elasticsearch 用户名
- ES_PASS -  Elasticsearch 密码

## 脚本用法

### 1. create-index-template.sh
创建或更新 Elasticsearch 索引模板。索引模板可以预先定义索引的设置和映射，当创建新的匹配索引时会自动应用这些设置。

示例:

```bash
  # 创建基本索引模板
  ./create-index-template.sh logs-template 'logs-*'

  # 创建带有 ILM 策略的索引模板
  ./create-index-template.sh --policy-name hot-warm-delete logs-template 'logs-*'

  # 创建自定义分片和副本数的索引模板
  ./create-index-template.sh --shards 3 --replicas 2 metrics-template 'metrics-*'
```

### 2. create-ilm-policy.sh
创建或更新索引生命周期管理(ILM)策略。ILM 可以自动管理索引的生命周期，包括滚动更新、迁移到冷存储以及删除旧索引等操作。

示例: 

```bash
# 启用 rollover，设置主分片大小限制
./create-ilm-policy.sh --hot-max-size 50gb --hot-max-primary-size 25gb --hot-max-age 30d my-policy

# 禁用 rollover
./create-ilm-policy.sh --disable-rollover --warm-min-age 45d --delete-min-age 90d my-policy
```

### 3. apply-ilm-policy.sh
将 ILM 策略应用到指定的索引模式或模板上。这样可以让符合特定模式的索引自动应用生命周期管理策略。

示例：

```bash
# 为所有日志索引应用 ILM 策略
./apply-ilm-policy.sh hot-warm-delete 'logs-*'

# 应用 ILM 策略并创建别名
./apply-ilm-policy.sh --alias logs hot-warm-delete 'logs-2024-*'
```

### 4. list-template-patterns.sh
列出所有索引模板及其对应的索引模式。这对于了解当前系统中的模板配置非常有帮助。

示例：

```bash
# 使用默认配置
./list-template-patterns.sh

# 使用表格格式显示
./list-template-patterns.sh --table
```

### 5. list-indices.sh
列出当前集群中的所有索引信息。可以帮助了解索引的基本状态和配置。

示例：

```bash
# 列出所有索引名称
./list-indices.sh

# 显示索引的详细信息
./list-indices.sh --table
```

### 6. analyze_index_pattern.sh
分析现有索引名称，总结出可能的索引模式。这个工具对于整理和规范化现有索引模式特别有用。

示例：
```bash
# 从文件读取索引列表, indices.txt 为 list-indices.sh 的输出文件
./analyze_index_pattern.sh indices.txt

# 从 list-indices.sh 的输出中读取
./list-indices.sh | ./analyze_index_pattern.sh

# 保存分析结果到文件
./analyze_index_pattern.sh indices.txt > patterns.txt


# 输出如下

分析得到的 index patterns:
----------------------------------------
elastalert
elastalert_error
elastalert_past
elastalert_silence
elastalert_status
elastalert_status_error
elastalert_status_past
elastalert_status_silence
elastalert_status_status
k8s-log_ingress-nginx_dev_*
k8s-log_ingress-nginx_dev_access_*
k8s-log_ingress-nginx_dev_raw_*
k8s-log_jfrog-test1_cluster_*
k8s-log_jfrog-test1_dev_*
k8s-log_kube-system_dev_*
k8s-log_mysql-operator_dev_*
----------------------------------------
```