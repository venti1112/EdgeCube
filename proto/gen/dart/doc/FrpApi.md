# edgecube_api_client.api.FrpApi

## Load the API package
```dart
import 'package:edgecube_api_client/api.dart';
```

All URIs are relative to *http://127.0.0.1:8760/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**createFrpTunnel**](FrpApi.md#createfrptunnel) | **POST** /frp/tunnels | 创建隧道
[**deleteFrpTunnel**](FrpApi.md#deletefrptunnel) | **DELETE** /frp/tunnels/{tunnelId} | 删除隧道
[**getFrpLogs**](FrpApi.md#getfrplogs) | **GET** /frp/logs | frpc 日志(最近 tail 行)
[**getFrpStatus**](FrpApi.md#getfrpstatus) | **GET** /frp/status | frpc 运行状态
[**getFrpTunnel**](FrpApi.md#getfrptunnel) | **GET** /frp/tunnels/{tunnelId} | 隧道详情
[**listFrpTunnels**](FrpApi.md#listfrptunnels) | **GET** /frp/tunnels | 隧道列表
[**startFrpc**](FrpApi.md#startfrpc) | **POST** /frp/start | 启动 frpc(全局唯一)
[**stopFrpc**](FrpApi.md#stopfrpc) | **POST** /frp/stop | 停止 frpc
[**updateFrpTunnel**](FrpApi.md#updatefrptunnel) | **PUT** /frp/tunnels/{tunnelId} | 更新隧道(全量替换)


# **createFrpTunnel**
> TunnelInfo createFrpTunnel(tunnelInput)

创建隧道

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getFrpApi();
final TunnelInput tunnelInput = ; // TunnelInput | 

try {
    final response = api.createFrpTunnel(tunnelInput);
    print(response);
} on DioException catch (e) {
    print('Exception when calling FrpApi->createFrpTunnel: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **tunnelInput** | [**TunnelInput**](TunnelInput.md)|  | 

### Return type

[**TunnelInfo**](TunnelInfo.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **deleteFrpTunnel**
> deleteFrpTunnel(tunnelId)

删除隧道

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getFrpApi();
final String tunnelId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    api.deleteFrpTunnel(tunnelId);
} on DioException catch (e) {
    print('Exception when calling FrpApi->deleteFrpTunnel: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **tunnelId** | **String**|  | 

### Return type

void (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getFrpLogs**
> BuiltList<String> getFrpLogs(tail)

frpc 日志(最近 tail 行)

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getFrpApi();
final int tail = 56; // int | 

try {
    final response = api.getFrpLogs(tail);
    print(response);
} on DioException catch (e) {
    print('Exception when calling FrpApi->getFrpLogs: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **tail** | **int**|  | [optional] [default to 200]

### Return type

**BuiltList&lt;String&gt;**

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getFrpStatus**
> FrpStatus getFrpStatus()

frpc 运行状态

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getFrpApi();

try {
    final response = api.getFrpStatus();
    print(response);
} on DioException catch (e) {
    print('Exception when calling FrpApi->getFrpStatus: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**FrpStatus**](FrpStatus.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getFrpTunnel**
> TunnelInfo getFrpTunnel(tunnelId)

隧道详情

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getFrpApi();
final String tunnelId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final response = api.getFrpTunnel(tunnelId);
    print(response);
} on DioException catch (e) {
    print('Exception when calling FrpApi->getFrpTunnel: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **tunnelId** | **String**|  | 

### Return type

[**TunnelInfo**](TunnelInfo.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **listFrpTunnels**
> BuiltList<TunnelInfo> listFrpTunnels()

隧道列表

隧道列表(不含运行状态,运行状态见 GET /frp/status)

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getFrpApi();

try {
    final response = api.listFrpTunnels();
    print(response);
} on DioException catch (e) {
    print('Exception when calling FrpApi->listFrpTunnels: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**BuiltList&lt;TunnelInfo&gt;**](TunnelInfo.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **startFrpc**
> startFrpc(startFrpcRequest)

启动 frpc(全局唯一)

渲染指定隧道的 TOML 并启动全局唯一的 frpc 进程;已有 frpc 运行 → 409 frpc_busy;未安装 frpc 运行时 → 409 frpc_runtime_missing。 

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getFrpApi();
final StartFrpcRequest startFrpcRequest = ; // StartFrpcRequest | 

try {
    api.startFrpc(startFrpcRequest);
} on DioException catch (e) {
    print('Exception when calling FrpApi->startFrpc: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **startFrpcRequest** | [**StartFrpcRequest**](StartFrpcRequest.md)|  | 

### Return type

void (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **stopFrpc**
> stopFrpc()

停止 frpc

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getFrpApi();

try {
    api.stopFrpc();
} on DioException catch (e) {
    print('Exception when calling FrpApi->stopFrpc: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

void (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **updateFrpTunnel**
> TunnelInfo updateFrpTunnel(tunnelId, tunnelInput)

更新隧道(全量替换)

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getFrpApi();
final String tunnelId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final TunnelInput tunnelInput = ; // TunnelInput | 

try {
    final response = api.updateFrpTunnel(tunnelId, tunnelInput);
    print(response);
} on DioException catch (e) {
    print('Exception when calling FrpApi->updateFrpTunnel: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **tunnelId** | **String**|  | 
 **tunnelInput** | [**TunnelInput**](TunnelInput.md)|  | 

### Return type

[**TunnelInfo**](TunnelInfo.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

