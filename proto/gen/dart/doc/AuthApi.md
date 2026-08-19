# edgecube_api_client.api.AuthApi

## Load the API package
```dart
import 'package:edgecube_api_client/api.dart';
```

All URIs are relative to *http://127.0.0.1:8760/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**getPairingCode**](AuthApi.md#getpairingcode) | **GET** /auth/pairing-code | 获取当前配对码
[**listDevices**](AuthApi.md#listdevices) | **GET** /auth/tokens | 已配对设备列表
[**pairDevice**](AuthApi.md#pairdevice) | **POST** /auth/pair | 对码配对,换取长期 token
[**revokeDevice**](AuthApi.md#revokedevice) | **DELETE** /auth/tokens/{deviceId} | 吊销指定设备的 token
[**rotatePairingCode**](AuthApi.md#rotatepairingcode) | **POST** /auth/pairing-code | 轮换配对码


# **getPairingCode**
> PairingCode getPairingCode()

获取当前配对码

返回当前生效的 6 位配对码。配对码用于本地/局域网设备换取 token; 未配对设备无需鉴权即可访问本端点(仅局域网可绑定)。 

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getAuthApi();

try {
    final response = api.getPairingCode();
    print(response);
} on DioException catch (e) {
    print('Exception when calling AuthApi->getPairingCode: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**PairingCode**](PairingCode.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **listDevices**
> BuiltList<DeviceInfo> listDevices()

已配对设备列表

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getAuthApi();

try {
    final response = api.listDevices();
    print(response);
} on DioException catch (e) {
    print('Exception when calling AuthApi->listDevices: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**BuiltList&lt;DeviceInfo&gt;**](DeviceInfo.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **pairDevice**
> PairResponse pairDevice(pairRequest)

对码配对,换取长期 token

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getAuthApi();
final PairRequest pairRequest = ; // PairRequest | 

try {
    final response = api.pairDevice(pairRequest);
    print(response);
} on DioException catch (e) {
    print('Exception when calling AuthApi->pairDevice: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **pairRequest** | [**PairRequest**](PairRequest.md)|  | 

### Return type

[**PairResponse**](PairResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **revokeDevice**
> revokeDevice(deviceId)

吊销指定设备的 token

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getAuthApi();
final String deviceId = deviceId_example; // String | 配对设备 id

try {
    api.revokeDevice(deviceId);
} on DioException catch (e) {
    print('Exception when calling AuthApi->revokeDevice: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **deviceId** | **String**| 配对设备 id | 

### Return type

void (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **rotatePairingCode**
> PairingCode rotatePairingCode()

轮换配对码

使当前配对码失效并生成新码。

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getAuthApi();

try {
    final response = api.rotatePairingCode();
    print(response);
} on DioException catch (e) {
    print('Exception when calling AuthApi->rotatePairingCode: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**PairingCode**](PairingCode.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

