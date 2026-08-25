
# InstanceSummary

## Properties
| Name | Type | Description | Notes |
| ------------ | ------------- | ------------- | ------------- |
| **id** | [**java.util.UUID**](java.util.UUID.md) |  |  |
| **name** | **kotlin.String** |  |  |
| **status** | [**InstanceStatus**](InstanceStatus.md) |  |  |
| **type** | [**InstanceType**](InstanceType.md) |  |  |
| **pid** | **kotlin.Int** |  |  [optional] |
| **runningSince** | [**java.time.OffsetDateTime**](java.time.OffsetDateTime.md) |  |  [optional] |
| **autoRestart** | **kotlin.Boolean** |  |  [optional] |
| **autoStartOnBoot** | **kotlin.Boolean** |  |  [optional] |
| **port** | **kotlin.Int** | 附加层解析出的服务端监听端口 |  [optional] |
| **onlinePlayers** | **kotlin.Int** | 附加层解析出的在线人数 |  [optional] |



