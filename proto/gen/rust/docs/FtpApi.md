# \FtpApi

All URIs are relative to *http://127.0.0.1:8760/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**get_ftp_status**](FtpApi.md#get_ftp_status) | **GET** /ftp | FTP 服务状态与配置
[**update_ftp_config**](FtpApi.md#update_ftp_config) | **PUT** /ftp | 更新 FTP 配置(启用/端口/账号/根目录)



## get_ftp_status

> models::FtpStatus get_ftp_status()
FTP 服务状态与配置

### Parameters

This endpoint does not need any parameter.

### Return type

[**models::FtpStatus**](FtpStatus.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## update_ftp_config

> models::FtpStatus update_ftp_config(ftp_config)
更新 FTP 配置(启用/端口/账号/根目录)

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**ftp_config** | [**FtpConfig**](FtpConfig.md) |  | [required] |

### Return type

[**models::FtpStatus**](FtpStatus.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

