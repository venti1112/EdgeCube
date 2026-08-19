# edgecube_api_client.api.SshApi

## Load the API package
```dart
import 'package:edgecube_api_client/api.dart';
```

All URIs are relative to *http://127.0.0.1:8760/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**getSshStatus**](SshApi.md#getsshstatus) | **GET** /ssh | SSH 服务状态与配置
[**updateSshConfig**](SshApi.md#updatesshconfig) | **PUT** /ssh | 更新 SSH 配置(启用/端口/账号/根目录)


# **getSshStatus**
> SshStatus getSshStatus()

SSH 服务状态与配置

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getSshApi();

try {
    final response = api.getSshStatus();
    print(response);
} on DioException catch (e) {
    print('Exception when calling SshApi->getSshStatus: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**SshStatus**](SshStatus.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **updateSshConfig**
> SshStatus updateSshConfig(sshConfig)

更新 SSH 配置(启用/端口/账号/根目录)

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getSshApi();
final SshConfig sshConfig = ; // SshConfig | 

try {
    final response = api.updateSshConfig(sshConfig);
    print(response);
} on DioException catch (e) {
    print('Exception when calling SshApi->updateSshConfig: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **sshConfig** | [**SshConfig**](SshConfig.md)|  | 

### Return type

[**SshStatus**](SshStatus.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

