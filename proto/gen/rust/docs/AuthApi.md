# \AuthApi

All URIs are relative to *http://127.0.0.1:8760/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**get_pairing_code**](AuthApi.md#get_pairing_code) | **GET** /auth/pairing-code | 获取当前配对码
[**list_devices**](AuthApi.md#list_devices) | **GET** /auth/tokens | 已配对设备列表
[**pair_device**](AuthApi.md#pair_device) | **POST** /auth/pair | 对码配对,换取长期 token
[**revoke_device**](AuthApi.md#revoke_device) | **DELETE** /auth/tokens/{deviceId} | 吊销指定设备的 token
[**rotate_pairing_code**](AuthApi.md#rotate_pairing_code) | **POST** /auth/pairing-code | 轮换配对码



## get_pairing_code

> models::PairingCode get_pairing_code()
获取当前配对码

返回当前生效的 6 位配对码。配对码用于本地/局域网设备换取 token; 未配对设备无需鉴权即可访问本端点(仅局域网可绑定)。 

### Parameters

This endpoint does not need any parameter.

### Return type

[**models::PairingCode**](PairingCode.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_devices

> Vec<models::DeviceInfo> list_devices()
已配对设备列表

### Parameters

This endpoint does not need any parameter.

### Return type

[**Vec<models::DeviceInfo>**](DeviceInfo.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## pair_device

> models::PairResponse pair_device(pair_request)
对码配对,换取长期 token

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**pair_request** | [**PairRequest**](PairRequest.md) |  | [required] |

### Return type

[**models::PairResponse**](PairResponse.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## revoke_device

> revoke_device(device_id)
吊销指定设备的 token

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**device_id** | **String** | 配对设备 id | [required] |

### Return type

 (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## rotate_pairing_code

> models::PairingCode rotate_pairing_code()
轮换配对码

使当前配对码失效并生成新码。

### Parameters

This endpoint does not need any parameter.

### Return type

[**models::PairingCode**](PairingCode.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

