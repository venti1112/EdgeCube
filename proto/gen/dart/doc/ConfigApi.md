# edgecube_api_client.api.ConfigApi

## Load the API package
```dart
import 'package:edgecube_api_client/api.dart';
```

All URIs are relative to *http://127.0.0.1:8760/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**getConfigEntry**](ConfigApi.md#getconfigentry) | **GET** /config/{key} | 读取设置项
[**updateConfigEntry**](ConfigApi.md#updateconfigentry) | **PUT** /config/{key} | 写入设置项


# **getConfigEntry**
> ConfigEntry getConfigEntry(key)

读取设置项

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getConfigApi();
final String key = network; // String | 

try {
    final response = api.getConfigEntry(key);
    print(response);
} on DioException catch (e) {
    print('Exception when calling ConfigApi->getConfigEntry: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **key** | **String**|  | 

### Return type

[**ConfigEntry**](ConfigEntry.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **updateConfigEntry**
> ConfigEntry updateConfigEntry(key, configEntry)

写入设置项

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getConfigApi();
final String key = network; // String | 
final ConfigEntry configEntry = ; // ConfigEntry | 

try {
    final response = api.updateConfigEntry(key, configEntry);
    print(response);
} on DioException catch (e) {
    print('Exception when calling ConfigApi->updateConfigEntry: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **key** | **String**|  | 
 **configEntry** | [**ConfigEntry**](ConfigEntry.md)|  | 

### Return type

[**ConfigEntry**](ConfigEntry.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

