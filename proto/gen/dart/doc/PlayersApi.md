# edgecube_api_client.api.PlayersApi

## Load the API package
```dart
import 'package:edgecube_api_client/api.dart';
```

All URIs are relative to *http://127.0.0.1:8760/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**getInstancePlayers**](PlayersApi.md#getinstanceplayers) | **GET** /instances/{instanceId}/players | 获取玩家管理聚合快照(在线玩家 + 白名单/封禁/IP封禁/OP 名单)


# **getInstancePlayers**
> PlayerSnapshot getInstancePlayers(instanceId)

获取玩家管理聚合快照(在线玩家 + 白名单/封禁/IP封禁/OP 名单)

返回当前实例的在线玩家名与四类名单快照,以及实例运行状态 (前端据此决定仅运行时才允许的增删操作)。 

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getPlayersApi();
final String instanceId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 实例 id(uuid)

try {
    final response = api.getInstancePlayers(instanceId);
    print(response);
} on DioException catch (e) {
    print('Exception when calling PlayersApi->getInstancePlayers: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **instanceId** | **String**| 实例 id(uuid) | 

### Return type

[**PlayerSnapshot**](PlayerSnapshot.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

