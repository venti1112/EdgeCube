# edgecube_api_client.api.ServerCoreApi

## Load the API package
```dart
import 'package:edgecube_api_client/api.dart';
```

All URIs are relative to *http://127.0.0.1:8760/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**checkServerCoreUpdate**](ServerCoreApi.md#checkservercoreupdate) | **GET** /instances/{instanceId}/core-update/check | 检查服务端核心是否有新版本(Paper 系)
[**updateServerCore**](ServerCoreApi.md#updateservercore) | **POST** /instances/{instanceId}/core-update | 更新服务端核心(jar 替换,Paper 系)


# **checkServerCoreUpdate**
> ServerCoreUpdateCheck checkServerCoreUpdate(instanceId)

检查服务端核心是否有新版本(Paper 系)

daemon 代理 PaperMC 官方 API:对 java 实例按其启动命令中的核心 jar (server.jar/paper-*.jar 等)与版本目录推导当前服务端,若为 Paper 系 (Paper/Purpur/Spigot/CraftBukkit 由版本目录识别,识别不了按最新版判断) 则返回最新版本/构建/下载地址与当前版本对比结果。非 java 实例或不支持 更新来源时返回 `source: unknown / supported: false`。 

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getServerCoreApi();
final String instanceId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 实例 id(uuid)

try {
    final response = api.checkServerCoreUpdate(instanceId);
    print(response);
} on DioException catch (e) {
    print('Exception when calling ServerCoreApi->checkServerCoreUpdate: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **instanceId** | **String**| 实例 id(uuid) | 

### Return type

[**ServerCoreUpdateCheck**](ServerCoreUpdateCheck.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **updateServerCore**
> JobAccepted updateServerCore(instanceId, serverCoreUpdateRequest)

更新服务端核心(jar 替换,Paper 系)

按检查结果下载最新核心 jar 并替换现有 jar(旧 jar 重命名为 `.disabled`)。 实例必须处于 Stopped;任务进度经 GET /tasks/{jobId} 轮询,完成后 GET /instances/{instanceId}/core-update/check 的 currentVersion 即更新。 

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getServerCoreApi();
final String instanceId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 实例 id(uuid)
final ServerCoreUpdateRequest serverCoreUpdateRequest = ; // ServerCoreUpdateRequest | 

try {
    final response = api.updateServerCore(instanceId, serverCoreUpdateRequest);
    print(response);
} on DioException catch (e) {
    print('Exception when calling ServerCoreApi->updateServerCore: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **instanceId** | **String**| 实例 id(uuid) | 
 **serverCoreUpdateRequest** | [**ServerCoreUpdateRequest**](ServerCoreUpdateRequest.md)|  | 

### Return type

[**JobAccepted**](JobAccepted.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

