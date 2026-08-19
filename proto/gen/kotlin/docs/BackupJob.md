
# BackupJob

## Properties
| Name | Type | Description | Notes |
| ------------ | ------------- | ------------- | ------------- |
| **id** | **kotlin.String** |  |  |
| **name** | **kotlin.String** |  |  |
| **instanceId** | **kotlin.String** | 备份哪个实例 |  |
| **scheduleCron** | **kotlin.String** | 定时表达式(如 \&quot;0 4 * * *\&quot;);null 为仅手动 |  [optional] |
| **targetIds** | **kotlin.collections.List&lt;kotlin.String&gt;** | 备份目标;空为仅本地 |  [optional] |
| **enabled** | **kotlin.Boolean** |  |  [optional] |
| **maxKeep** | **kotlin.Int** | 保留最近 N 份 |  [optional] |
| **includeDirs** | **kotlin.collections.List&lt;kotlin.String&gt;** | 相对 cwd 的附加目录;空为整个工作目录 |  [optional] |
| **lastRunAt** | [**java.time.OffsetDateTime**](java.time.OffsetDateTime.md) |  |  [optional] [readonly] |
| **lastResult** | [**inline**](#LastResult) |  |  [optional] [readonly] |


<a id="LastResult"></a>
## Enum: lastResult
| Name | Value |
| ---- | ----- |
| lastResult | success, failed, running |



