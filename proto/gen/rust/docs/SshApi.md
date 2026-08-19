# \SshApi

All URIs are relative to *http://127.0.0.1:8760/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**get_ssh_status**](SshApi.md#get_ssh_status) | **GET** /ssh | SSH 服务状态与配置
[**update_ssh_config**](SshApi.md#update_ssh_config) | **PUT** /ssh | 更新 SSH 配置(启用/端口/账号/根目录)



## get_ssh_status

> models::SshStatus get_ssh_status()
SSH 服务状态与配置

### Parameters

This endpoint does not need any parameter.

### Return type

[**models::SshStatus**](SshStatus.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## update_ssh_config

> models::SshStatus update_ssh_config(ssh_config)
更新 SSH 配置(启用/端口/账号/根目录)

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**ssh_config** | [**SshConfig**](SshConfig.md) |  | [required] |

### Return type

[**models::SshStatus**](SshStatus.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

