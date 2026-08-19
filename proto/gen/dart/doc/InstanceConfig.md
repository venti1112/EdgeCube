# edgecube_api_client.model.InstanceConfig

## Load the model package
```dart
import 'package:edgecube_api_client/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | **String** | 服务端生成 | [optional] 
**name** | **String** |  | 
**startCommand** | **String** | 命令行字符串(支持引号/转义,解析为参数数组 spawn,不经 shell) | 
**stopCommand** | **String** | 优雅停止命令;^C 表示发送 Ctrl+C | [optional] [default to '^C']
**stopTimeoutSeconds** | **int** | 优雅停止超时,超时升级强杀 | [optional] [default to 600]
**workingDirectory** | **String** | 工作目录(实例 cwd,文件沙箱根) | 
**environment** | **BuiltMap&lt;String, String&gt;** | 额外环境变量 | [optional] 
**inputEncoding** | [**Encoding**](Encoding.md) |  | [optional] 
**outputEncoding** | [**Encoding**](Encoding.md) |  | [optional] 
**autoRestart** | **bool** | 异常/正常退出后自动重启 | [optional] [default to false]
**autoRestartMaxTimes** | **int** | 重启次数上限;-1 无限 | [optional] [default to -1]
**autoStartOnBoot** | **bool** | daemon 启动时自动拉起 | [optional] [default to false]
**terminal** | [**InstanceConfigTerminal**](InstanceConfigTerminal.md) |  | [optional] 
**type** | [**InstanceType**](InstanceType.md) |  | [optional] 
**createdAt** | [**DateTime**](DateTime.md) |  | [optional] 
**updatedAt** | [**DateTime**](DateTime.md) |  | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


