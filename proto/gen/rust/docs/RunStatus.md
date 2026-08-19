# RunStatus

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**status** | [**models::InstanceStatus**](InstanceStatus.md) |  | 
**pid** | Option<**i32**> | 真实游戏进程 PID(PTY 握手获得) | [optional]
**exit_code** | Option<**i32**> | 上次退出码 | [optional]
**server_port** | Option<**i32**> |  | [optional]
**online_mode** | Option<**bool**> |  | [optional]
**online_players** | Option<**Vec<String>**> | 当前在线玩家名 | [optional]
**log_seq** | Option<**i64**> | 当前日志行序号(供 /log?since= 续拉) | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


