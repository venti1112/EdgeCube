# edgecube_api_client.api.TransferApi

## Load the API package
```dart
import 'package:edgecube_api_client/api.dart';
```

All URIs are relative to *http://127.0.0.1:8760/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**downloadInstanceExport**](TransferApi.md#downloadinstanceexport) | **GET** /instances/{instanceId}/export/download | 下载已完成的导出归档
[**importInstance**](TransferApi.md#importinstance) | **POST** /instances/import | 导入实例(从导出归档还原为新实例)


# **downloadInstanceExport**
> Uint8List downloadInstanceExport(instanceId, exportTaskId)

下载已完成的导出归档

按导出任务 id 下载归档文件(application/octet-stream 流式返回)。 归档同时包含实例配置(config.json)与 `files` 目录内容,可用 POST /instances/import 在任意设备还原。文件在导出目录中保留 24 小时,过期或被新导出覆盖后返回 404。 

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getTransferApi();
final String instanceId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 实例 id(uuid)
final String exportTaskId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 导出任务 id(即 POST /instances/{id}/export 返回的 jobId,用于定位导出的归档文件)

try {
    final response = api.downloadInstanceExport(instanceId, exportTaskId);
    print(response);
} on DioException catch (e) {
    print('Exception when calling TransferApi->downloadInstanceExport: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **instanceId** | **String**| 实例 id(uuid) | 
 **exportTaskId** | **String**| 导出任务 id(即 POST /instances/{id}/export 返回的 jobId,用于定位导出的归档文件) | 

### Return type

[**Uint8List**](Uint8List.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/octet-stream, application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **importInstance**
> JobAccepted importInstance(importRequest)

导入实例(从导出归档还原为新实例)

归档文件须先经 /fs/upload-* 上传到某实例的 cwd(sourceInstanceId 指定该实例), 导入时 daemon 校验归档结构(须含 config.json 与 files/ 目录)后创建新实例: 新实例 id 重新生成,cwd 落到新工作目录,配置中的 name 与 runtime 等 字段按需映射。返回 202 受理(JobAccepted),任务完成 (GET /tasks/{jobId} = succeeded)后新实例出现在实例列表。 

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getTransferApi();
final ImportRequest importRequest = ; // ImportRequest | 

try {
    final response = api.importInstance(importRequest);
    print(response);
} on DioException catch (e) {
    print('Exception when calling TransferApi->importInstance: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **importRequest** | [**ImportRequest**](ImportRequest.md)|  | 

### Return type

[**JobAccepted**](JobAccepted.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

