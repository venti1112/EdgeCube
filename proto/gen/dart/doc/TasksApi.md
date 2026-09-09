# edgecube_api_client.api.TasksApi

## Load the API package
```dart
import 'package:edgecube_api_client/api.dart';
```

All URIs are relative to *http://127.0.0.1:8760/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**cancelTask**](TasksApi.md#canceltask) | **DELETE** /tasks/{jobId} | 取消任务
[**getTask**](TasksApi.md#gettask) | **GET** /tasks/{jobId} | 查询单个任务
[**listTasks**](TasksApi.md#listtasks) | **GET** /tasks | 任务列表(进行中优先 + 最近完成)


# **cancelTask**
> Task cancelTask(jobId)

取消任务

queued 任务直接移除;running 任务置取消标志,由执行体尽快中断。 已结束(succeeded/failed/cancelled)任务不可取消,返回 409。 取消结果回显最终 Task(status=cancelled)。 

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getTasksApi();
final String jobId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 任务 id(即 Task.id,异步操作 202 响应中的 jobId)

try {
    final response = api.cancelTask(jobId);
    print(response);
} on DioException catch (e) {
    print('Exception when calling TasksApi->cancelTask: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **jobId** | **String**| 任务 id(即 Task.id,异步操作 202 响应中的 jobId) | 

### Return type

[**Task**](Task.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getTask**
> Task getTask(jobId)

查询单个任务

返回任务详情;下载类任务运行时 progress 携带实时进度 (已下载/总大小/速度/预计剩余时间)。 

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getTasksApi();
final String jobId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 任务 id(即 Task.id,异步操作 202 响应中的 jobId)

try {
    final response = api.getTask(jobId);
    print(response);
} on DioException catch (e) {
    print('Exception when calling TasksApi->getTask: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **jobId** | **String**| 任务 id(即 Task.id,异步操作 202 响应中的 jobId) | 

### Return type

[**Task**](Task.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **listTasks**
> TaskList listTasks(instanceId, status, page, pageSize)

任务列表(进行中优先 + 最近完成)

进行中(queued/running)任务在前,其余按创建时间倒序。 可选按 instanceId / status 过滤。 

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getTasksApi();
final String instanceId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 按实例过滤;缺省返回全部
final TaskStatus status = ; // TaskStatus | 按状态过滤
final int page = 56; // int | 页码,从 1 开始
final int pageSize = 56; // int | 

try {
    final response = api.listTasks(instanceId, status, page, pageSize);
    print(response);
} on DioException catch (e) {
    print('Exception when calling TasksApi->listTasks: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **instanceId** | **String**| 按实例过滤;缺省返回全部 | [optional] 
 **status** | [**TaskStatus**](.md)| 按状态过滤 | [optional] 
 **page** | **int**| 页码,从 1 开始 | [optional] [default to 1]
 **pageSize** | **int**|  | [optional] [default to 20]

### Return type

[**TaskList**](TaskList.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

