# edgecube_api_client.api.HealthApi

## Load the API package
```dart
import 'package:edgecube_api_client/api.dart';
```

All URIs are relative to *http://127.0.0.1:8760/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**getHealth**](HealthApi.md#gethealth) | **GET** /health | 健康检查(未配对可访问)


# **getHealth**
> HealthResponse getHealth()

健康检查(未配对可访问)

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getHealthApi();

try {
    final response = api.getHealth();
    print(response);
} on DioException catch (e) {
    print('Exception when calling HealthApi->getHealth: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**HealthResponse**](HealthResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

