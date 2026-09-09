# \PlayersApi

All URIs are relative to *http://127.0.0.1:8760/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**get_instance_players**](PlayersApi.md#get_instance_players) | **GET** /instances/{instanceId}/players | 获取玩家管理聚合快照(在线玩家 + 白名单/封禁/IP封禁/OP 名单)



## get_instance_players

> models::PlayerSnapshot get_instance_players(instance_id)
获取玩家管理聚合快照(在线玩家 + 白名单/封禁/IP封禁/OP 名单)

返回当前实例的在线玩家名与四类名单快照,以及实例运行状态 (前端据此决定仅运行时才允许的增删操作)。 

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**instance_id** | **uuid::Uuid** | 实例 id(uuid) | [required] |

### Return type

[**models::PlayerSnapshot**](PlayerSnapshot.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

