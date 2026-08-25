# edgecube_api_client.model.BackupJob

## Load the model package
```dart
import 'package:edgecube_api_client/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | **String** |  | 
**name** | **String** |  | 
**instanceId** | **String** | 备份哪个实例 | 
**scheduleCron** | **String** | 定时表达式(如 \"0 4 * * *\");null 为仅手动 | [optional] 
**targetIds** | **BuiltList&lt;String&gt;** | 备份目标;空为仅本地 | [optional] 
**enabled** | **bool** |  | [optional] [default to true]
**maxKeep** | **int** | 保留最近 N 份 | [optional] [default to 10]
**includeDirs** | **BuiltList&lt;String&gt;** | 相对 cwd 的附加目录;空为整个工作目录 | [optional] 
**lastRunAt** | [**DateTime**](DateTime.md) |  | [optional] 
**lastResult** | **String** |  | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


