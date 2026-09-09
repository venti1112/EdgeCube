# \FrpApi

All URIs are relative to *http://127.0.0.1:8760/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**create_frp_tunnel**](FrpApi.md#create_frp_tunnel) | **POST** /frp/tunnels | 创建隧道
[**delete_frp_tunnel**](FrpApi.md#delete_frp_tunnel) | **DELETE** /frp/tunnels/{tunnelId} | 删除隧道
[**get_frp_logs**](FrpApi.md#get_frp_logs) | **GET** /frp/logs | frpc 日志(最近 tail 行)
[**get_frp_status**](FrpApi.md#get_frp_status) | **GET** /frp/status | frpc 运行状态
[**get_frp_tunnel**](FrpApi.md#get_frp_tunnel) | **GET** /frp/tunnels/{tunnelId} | 隧道详情
[**list_frp_tunnels**](FrpApi.md#list_frp_tunnels) | **GET** /frp/tunnels | 隧道列表
[**start_frpc**](FrpApi.md#start_frpc) | **POST** /frp/start | 启动 frpc(全局唯一)
[**stop_frpc**](FrpApi.md#stop_frpc) | **POST** /frp/stop | 停止 frpc
[**update_frp_tunnel**](FrpApi.md#update_frp_tunnel) | **PUT** /frp/tunnels/{tunnelId} | 更新隧道(全量替换)



## create_frp_tunnel

> models::TunnelInfo create_frp_tunnel(tunnel_input)
创建隧道

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**tunnel_input** | [**TunnelInput**](TunnelInput.md) |  | [required] |

### Return type

[**models::TunnelInfo**](TunnelInfo.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_frp_tunnel

> delete_frp_tunnel(tunnel_id)
删除隧道

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**tunnel_id** | **uuid::Uuid** |  | [required] |

### Return type

 (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_frp_logs

> Vec<String> get_frp_logs(tail)
frpc 日志(最近 tail 行)

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**tail** | Option<**i32**> |  |  |[default to 200]

### Return type

**Vec<String>**

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_frp_status

> models::FrpStatus get_frp_status()
frpc 运行状态

### Parameters

This endpoint does not need any parameter.

### Return type

[**models::FrpStatus**](FrpStatus.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_frp_tunnel

> models::TunnelInfo get_frp_tunnel(tunnel_id)
隧道详情

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**tunnel_id** | **uuid::Uuid** |  | [required] |

### Return type

[**models::TunnelInfo**](TunnelInfo.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_frp_tunnels

> Vec<models::TunnelInfo> list_frp_tunnels()
隧道列表

隧道列表(不含运行状态,运行状态见 GET /frp/status)

### Parameters

This endpoint does not need any parameter.

### Return type

[**Vec<models::TunnelInfo>**](TunnelInfo.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## start_frpc

> start_frpc(start_frpc_request)
启动 frpc(全局唯一)

渲染指定隧道的 TOML 并启动全局唯一的 frpc 进程;已有 frpc 运行 → 409 frpc_busy;未安装 frpc 运行时 → 409 frpc_runtime_missing。 

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**start_frpc_request** | [**StartFrpcRequest**](StartFrpcRequest.md) |  | [required] |

### Return type

 (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## stop_frpc

> stop_frpc()
停止 frpc

### Parameters

This endpoint does not need any parameter.

### Return type

 (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## update_frp_tunnel

> models::TunnelInfo update_frp_tunnel(tunnel_id, tunnel_input)
更新隧道(全量替换)

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**tunnel_id** | **uuid::Uuid** |  | [required] |
**tunnel_input** | [**TunnelInput**](TunnelInput.md) |  | [required] |

### Return type

[**models::TunnelInfo**](TunnelInfo.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

