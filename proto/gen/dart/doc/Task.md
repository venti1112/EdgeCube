# edgecube_api_client.model.Task

## Load the model package
```dart
import 'package:edgecube_api_client/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | **String** | 任务 id(= JobAccepted.jobId) | 
**kind** | [**TaskKind**](TaskKind.md) |  | 
**displayName** | **String** | 用户可读展示标题(如「模组名 v1.2」,download_single_file 等使用);无时为 null | [optional] 
**instanceId** | **String** | 关联实例;全局任务(下载运行时等)为 null | [optional] 
**status** | [**TaskStatus**](TaskStatus.md) |  | 
**phase** | **String** | 执行阶段描述(如 start 的 launching / 下载的 fetching);无阶段概念时为 null | [optional] 
**progress** | [**TaskProgress**](TaskProgress.md) |  | [optional] 
**error** | [**TaskError**](TaskError.md) |  | [optional] 
**createdAt** | [**DateTime**](DateTime.md) |  | 
**startedAt** | [**DateTime**](DateTime.md) |  | [optional] 
**finishedAt** | [**DateTime**](DateTime.md) |  | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


