# edgecube_api_client.model.RunStatus

## Load the model package
```dart
import 'package:edgecube_api_client/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**status** | [**InstanceStatus**](InstanceStatus.md) |  | 
**pid** | **int** | 真实游戏进程 PID(PTY 握手获得) | [optional] 
**exitCode** | **int** | 上次退出码 | [optional] 
**serverPort** | **int** |  | [optional] 
**onlineMode** | **bool** |  | [optional] 
**onlinePlayers** | **BuiltList&lt;String&gt;** | 当前在线玩家名 | [optional] 
**logSeq** | **int** | 当前日志行序号(供 /log?since= 续拉) | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


