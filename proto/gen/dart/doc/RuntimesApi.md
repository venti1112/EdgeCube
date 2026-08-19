# edgecube_api_client.api.RuntimesApi

## Load the API package
```dart
import 'package:edgecube_api_client/api.dart';
```

All URIs are relative to *http://127.0.0.1:8760/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**deleteRuntime**](RuntimesApi.md#deleteruntime) | **DELETE** /runtimes/{runtimeId} | 卸载运行时
[**getRuntimeCatalog**](RuntimesApi.md#getruntimecatalog) | **GET** /runtimes/catalog | 可安装版本清单(官方源)
[**installRuntime**](RuntimesApi.md#installruntime) | **POST** /runtimes/install | 安装运行时(官方源下载,进度走 WS download/progress)
[**listRuntimes**](RuntimesApi.md#listruntimes) | **GET** /runtimes | 已安装运行时列表


# **deleteRuntime**
> deleteRuntime(runtimeId)

卸载运行时

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getRuntimesApi();
final String runtimeId = runtimeId_example; // String | 

try {
    api.deleteRuntime(runtimeId);
} on DioException catch (e) {
    print('Exception when calling RuntimesApi->deleteRuntime: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **runtimeId** | **String**|  | 

### Return type

void (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getRuntimeCatalog**
> RuntimeCatalog getRuntimeCatalog(type)

可安装版本清单(官方源)

拉取对应官方渠道的可用版本(java: Adoptium API;php: 权威预编译源;frpc: GitHub Releases)。

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getRuntimesApi();
final RuntimeType type = ; // RuntimeType | 

try {
    final response = api.getRuntimeCatalog(type);
    print(response);
} on DioException catch (e) {
    print('Exception when calling RuntimesApi->getRuntimeCatalog: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **type** | [**RuntimeType**](.md)|  | 

### Return type

[**RuntimeCatalog**](RuntimeCatalog.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **installRuntime**
> JobAccepted installRuntime(runtimeInstallRequest)

安装运行时(官方源下载,进度走 WS download/progress)

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getRuntimesApi();
final RuntimeInstallRequest runtimeInstallRequest = ; // RuntimeInstallRequest | 

try {
    final response = api.installRuntime(runtimeInstallRequest);
    print(response);
} on DioException catch (e) {
    print('Exception when calling RuntimesApi->installRuntime: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **runtimeInstallRequest** | [**RuntimeInstallRequest**](RuntimeInstallRequest.md)|  | 

### Return type

[**JobAccepted**](JobAccepted.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **listRuntimes**
> BuiltList<RuntimeInfo> listRuntimes()

已安装运行时列表

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getRuntimesApi();

try {
    final response = api.listRuntimes();
    print(response);
} on DioException catch (e) {
    print('Exception when calling RuntimesApi->listRuntimes: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**BuiltList&lt;RuntimeInfo&gt;**](RuntimeInfo.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

