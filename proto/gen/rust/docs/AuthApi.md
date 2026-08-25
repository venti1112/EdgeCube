# \AuthApi

All URIs are relative to *http://127.0.0.1:8760/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**change_password**](AuthApi.md#change_password) | **POST** /auth/change-password | 修改密码
[**change_username**](AuthApi.md#change_username) | **POST** /auth/change-username | 修改用户名
[**list_devices**](AuthApi.md#list_devices) | **GET** /auth/tokens | 已登录设备列表
[**login**](AuthApi.md#login) | **POST** /auth/login | 用户名密码登录,换取长期 token
[**revoke_device**](AuthApi.md#revoke_device) | **DELETE** /auth/tokens/{deviceId} | 吊销指定设备的 token



## change_password

> change_password(change_password_request)
修改密码

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**change_password_request** | [**ChangePasswordRequest**](ChangePasswordRequest.md) |  | [required] |

### Return type

 (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## change_username

> change_username(change_username_request)
修改用户名

需提供当前密码进行二次验证。

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**change_username_request** | [**ChangeUsernameRequest**](ChangeUsernameRequest.md) |  | [required] |

### Return type

 (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_devices

> Vec<models::DeviceInfo> list_devices()
已登录设备列表

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


## login

> models::LoginResponse login(login_request)
用户名密码登录,换取长期 token

使用用户名和密码登录。daemon 首次启动时生成随机凭证并打印到控制台; 未登录设备无需鉴权即可访问本端点(仅局域网可绑定)。 

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**login_request** | [**LoginRequest**](LoginRequest.md) |  | [required] |

### Return type

[**models::LoginResponse**](LoginResponse.md)

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

