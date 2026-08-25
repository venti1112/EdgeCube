
# RunStatus

## Properties
| Name | Type | Description | Notes |
| ------------ | ------------- | ------------- | ------------- |
| **status** | [**InstanceStatus**](InstanceStatus.md) |  |  |
| **pid** | **kotlin.Int** | 真实游戏进程 PID(PTY 握手获得) |  [optional] |
| **exitCode** | **kotlin.Int** | 上次退出码 |  [optional] |
| **serverPort** | **kotlin.Int** |  |  [optional] |
| **onlineMode** | **kotlin.Boolean** |  |  [optional] |
| **onlinePlayers** | **kotlin.collections.List&lt;kotlin.String&gt;** | 当前在线玩家名 |  [optional] |
| **logSeq** | **kotlin.Long** | 当前日志行序号(供 /log?since&#x3D; 续拉) |  [optional] |



