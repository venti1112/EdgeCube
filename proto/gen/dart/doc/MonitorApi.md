# edgecube_api_client.api.MonitorApi

## Load the API package
```dart
import 'package:edgecube_api_client/api.dart';
```

All URIs are relative to *http://127.0.0.1:8760/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**getMonitorSnapshot**](MonitorApi.md#getmonitorsnapshot) | **GET** /monitor/snapshot | 系统监控快照(实时曲线走 WS monitor/stats)


# **getMonitorSnapshot**
> MonitorSnapshot getMonitorSnapshot()

系统监控快照(实时曲线走 WS monitor/stats)

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getMonitorApi();

try {
    final response = api.getMonitorSnapshot();
    print(response);
} on DioException catch (e) {
    print('Exception when calling MonitorApi->getMonitorSnapshot: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**MonitorSnapshot**](MonitorSnapshot.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

