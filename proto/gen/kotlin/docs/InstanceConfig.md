
# InstanceConfig

## Properties
| Name | Type | Description | Notes |
| ------------ | ------------- | ------------- | ------------- |
| **name** | **kotlin.String** |  |  |
| **startCommand** | **kotlin.String** | 命令行字符串(支持引号/转义,解析为参数数组 spawn,不经 shell) |  |
| **workingDirectory** | **kotlin.String** | 工作目录(实例 cwd,文件沙箱根) |  |
| **id** | [**java.util.UUID**](java.util.UUID.md) | 服务端生成 |  [optional] [readonly] |
| **stopCommand** | **kotlin.String** | 优雅停止命令;^C 表示发送 Ctrl+C |  [optional] |
| **stopTimeoutSeconds** | **kotlin.Int** | 优雅停止超时,超时升级强杀 |  [optional] |
| **environment** | **kotlin.collections.Map&lt;kotlin.String, kotlin.String&gt;** | 额外环境变量 |  [optional] |
| **inputEncoding** | [**Encoding**](Encoding.md) |  |  [optional] |
| **outputEncoding** | [**Encoding**](Encoding.md) |  |  [optional] |
| **autoRestart** | **kotlin.Boolean** | 异常/正常退出后自动重启 |  [optional] |
| **autoRestartMaxTimes** | **kotlin.Int** | 重启次数上限;-1 无限 |  [optional] |
| **autoStartOnBoot** | **kotlin.Boolean** | daemon 启动时自动拉起 |  [optional] |
| **terminal** | [**InstanceConfigTerminal**](InstanceConfigTerminal.md) |  |  [optional] |
| **type** | [**InstanceType**](InstanceType.md) |  |  [optional] |
| **createdAt** | [**java.time.OffsetDateTime**](java.time.OffsetDateTime.md) |  |  [optional] [readonly] |
| **updatedAt** | [**java.time.OffsetDateTime**](java.time.OffsetDateTime.md) |  |  [optional] [readonly] |



