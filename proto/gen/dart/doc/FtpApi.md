# edgecube_api_client.api.FtpApi

## Load the API package
```dart
import 'package:edgecube_api_client/api.dart';
```

All URIs are relative to *http://127.0.0.1:8760/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**getFtpStatus**](FtpApi.md#getftpstatus) | **GET** /ftp | FTP 服务状态与配置
[**updateFtpConfig**](FtpApi.md#updateftpconfig) | **PUT** /ftp | 更新 FTP 配置(启用/端口/账号/根目录)


# **getFtpStatus**
> FtpStatus getFtpStatus()

FTP 服务状态与配置

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getFtpApi();

try {
    final response = api.getFtpStatus();
    print(response);
} on DioException catch (e) {
    print('Exception when calling FtpApi->getFtpStatus: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**FtpStatus**](FtpStatus.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **updateFtpConfig**
> FtpStatus updateFtpConfig(ftpConfig)

更新 FTP 配置(启用/端口/账号/根目录)

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getFtpApi();
final FtpConfig ftpConfig = ; // FtpConfig | 

try {
    final response = api.updateFtpConfig(ftpConfig);
    print(response);
} on DioException catch (e) {
    print('Exception when calling FtpApi->updateFtpConfig: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **ftpConfig** | [**FtpConfig**](FtpConfig.md)|  | 

### Return type

[**FtpStatus**](FtpStatus.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

