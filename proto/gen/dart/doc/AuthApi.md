# edgecube_api_client.api.AuthApi

## Load the API package
```dart
import 'package:edgecube_api_client/api.dart';
```

All URIs are relative to *http://127.0.0.1:8760/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**changePassword**](AuthApi.md#changepassword) | **POST** /auth/change-password | 修改密码
[**changeUsername**](AuthApi.md#changeusername) | **POST** /auth/change-username | 修改用户名
[**issueLocalLoginChallenge**](AuthApi.md#issuelocalloginchallenge) | **POST** /auth/local-login/challenge | 发起本机免密登录挑战(一次性,短时效)
[**listDevices**](AuthApi.md#listdevices) | **GET** /auth/tokens | 已登录设备列表
[**localLogin**](AuthApi.md#locallogin) | **POST** /auth/local-login | 本机免密登录,换取长期 token
[**login**](AuthApi.md#login) | **POST** /auth/login | 用户名密码登录,换取长期 token
[**revokeDevice**](AuthApi.md#revokedevice) | **DELETE** /auth/tokens/{deviceId} | 吊销指定设备的 token


# **changePassword**
> changePassword(changePasswordRequest)

修改密码

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getAuthApi();
final ChangePasswordRequest changePasswordRequest = ; // ChangePasswordRequest | 

try {
    api.changePassword(changePasswordRequest);
} on DioException catch (e) {
    print('Exception when calling AuthApi->changePassword: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **changePasswordRequest** | [**ChangePasswordRequest**](ChangePasswordRequest.md)|  | 

### Return type

void (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **changeUsername**
> changeUsername(changeUsernameRequest)

修改用户名

需提供当前密码进行二次验证。

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getAuthApi();
final ChangeUsernameRequest changeUsernameRequest = ; // ChangeUsernameRequest | 

try {
    api.changeUsername(changeUsernameRequest);
} on DioException catch (e) {
    print('Exception when calling AuthApi->changeUsername: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **changeUsernameRequest** | [**ChangeUsernameRequest**](ChangeUsernameRequest.md)|  | 

### Return type

void (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **issueLocalLoginChallenge**
> LocalLoginChallenge issueLocalLoginChallenge()

发起本机免密登录挑战(一次性,短时效)

直连 daemon 的本机客户端免密登录: 返回一次性 challenge(5 分钟过期,使用后作废),客户端读取数据目录 `local.key`, 计算 `signature = lowercase(hex(HMAC-SHA256(localKey, challenge)))` 后提交 `/auth/local-login`。未登录设备无需鉴权(同 /auth/login)。 

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getAuthApi();

try {
    final response = api.issueLocalLoginChallenge();
    print(response);
} on DioException catch (e) {
    print('Exception when calling AuthApi->issueLocalLoginChallenge: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**LocalLoginChallenge**](LocalLoginChallenge.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **listDevices**
> BuiltList<DeviceInfo> listDevices()

已登录设备列表

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

# **localLogin**
> LoginResponse localLogin(localLoginRequest)

本机免密登录,换取长期 token

提交 /auth/local-login/challenge 返回的 challenge 及对应 HMAC 签名。 签名验证通过即视为本机进程(持有 local.key),签发与 /auth/login 相同的长期 token。 challenge 一次性使用,重放返回 401。 

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getAuthApi();
final LocalLoginRequest localLoginRequest = ; // LocalLoginRequest | 

try {
    final response = api.localLogin(localLoginRequest);
    print(response);
} on DioException catch (e) {
    print('Exception when calling AuthApi->localLogin: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **localLoginRequest** | [**LocalLoginRequest**](LocalLoginRequest.md)|  | 

### Return type

[**LoginResponse**](LoginResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **login**
> LoginResponse login(loginRequest)

用户名密码登录,换取长期 token

使用用户名和密码登录。daemon 首次启动时生成随机凭证并打印到控制台; 未登录设备无需鉴权即可访问本端点(仅局域网可绑定)。 

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getAuthApi();
final LoginRequest loginRequest = ; // LoginRequest | 

try {
    final response = api.login(loginRequest);
    print(response);
} on DioException catch (e) {
    print('Exception when calling AuthApi->login: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **loginRequest** | [**LoginRequest**](LoginRequest.md)|  | 

### Return type

[**LoginResponse**](LoginResponse.md)

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

