# \RuntimesApi

All URIs are relative to *http://127.0.0.1:8760/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**delete_runtime**](RuntimesApi.md#delete_runtime) | **DELETE** /runtimes/{runtimeId} | 卸载运行时
[**get_runtime_catalog**](RuntimesApi.md#get_runtime_catalog) | **GET** /runtimes/catalog | 可安装版本清单(官方源)
[**install_runtime**](RuntimesApi.md#install_runtime) | **POST** /runtimes/install | 安装运行时(官方源下载,进度走 WS download/progress)
[**list_runtimes**](RuntimesApi.md#list_runtimes) | **GET** /runtimes | 已安装运行时列表



## delete_runtime

> delete_runtime(runtime_id)
卸载运行时

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**runtime_id** | **String** |  | [required] |

### Return type

 (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_runtime_catalog

> models::RuntimeCatalog get_runtime_catalog(r#type)
可安装版本清单(官方源)

拉取对应官方渠道的可用版本(java: Adoptium API;php: 权威预编译源;frpc: GitHub Releases)。

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**r#type** | [**RuntimeType**](RuntimeType.md) |  | [required] |

### Return type

[**models::RuntimeCatalog**](RuntimeCatalog.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## install_runtime

> models::JobAccepted install_runtime(runtime_install_request)
安装运行时(官方源下载,进度走 WS download/progress)

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**runtime_install_request** | [**RuntimeInstallRequest**](RuntimeInstallRequest.md) |  | [required] |

### Return type

[**models::JobAccepted**](JobAccepted.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_runtimes

> Vec<models::RuntimeInfo> list_runtimes()
已安装运行时列表

### Parameters

This endpoint does not need any parameter.

### Return type

[**Vec<models::RuntimeInfo>**](RuntimeInfo.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

