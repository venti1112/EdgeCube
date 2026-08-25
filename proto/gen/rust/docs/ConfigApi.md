# \ConfigApi

All URIs are relative to *http://127.0.0.1:8760/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**get_config_entry**](ConfigApi.md#get_config_entry) | **GET** /config/{key} | 读取设置项
[**update_config_entry**](ConfigApi.md#update_config_entry) | **PUT** /config/{key} | 写入设置项



## get_config_entry

> models::ConfigEntry get_config_entry(key)
读取设置项

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**key** | **String** |  | [required] |

### Return type

[**models::ConfigEntry**](ConfigEntry.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## update_config_entry

> models::ConfigEntry update_config_entry(key, config_entry)
写入设置项

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**key** | **String** |  | [required] |
**config_entry** | [**ConfigEntry**](ConfigEntry.md) |  | [required] |

### Return type

[**models::ConfigEntry**](ConfigEntry.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

