# AuthApi

All URIs are relative to *http://127.0.0.1:8760/api/v1*

| Method | HTTP request | Description |
| ------------- | ------------- | ------------- |
| [**changePassword**](AuthApi.md#changePassword) | **POST** /auth/change-password | 修改密码 |
| [**changeUsername**](AuthApi.md#changeUsername) | **POST** /auth/change-username | 修改用户名 |
| [**listDevices**](AuthApi.md#listDevices) | **GET** /auth/tokens | 已登录设备列表 |
| [**login**](AuthApi.md#login) | **POST** /auth/login | 用户名密码登录,换取长期 token |
| [**revokeDevice**](AuthApi.md#revokeDevice) | **DELETE** /auth/tokens/{deviceId} | 吊销指定设备的 token |


<a id="changePassword"></a>
# **changePassword**
> changePassword(changePasswordRequest)

修改密码

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = AuthApi()
val changePasswordRequest : ChangePasswordRequest =  // ChangePasswordRequest | 
try {
    apiInstance.changePassword(changePasswordRequest)
} catch (e: ClientException) {
    println("4xx response calling AuthApi#changePassword")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling AuthApi#changePassword")
    e.printStackTrace()
}
```

### Parameters
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **changePasswordRequest** | [**ChangePasswordRequest**](ChangePasswordRequest.md)|  | |

### Return type

null (empty response body)

### Authorization


Configure BearerAuth statically:
```kotlin
ApiClient.accessToken = ""
```

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

<a id="changeUsername"></a>
# **changeUsername**
> changeUsername(changeUsernameRequest)

修改用户名

需提供当前密码进行二次验证。

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = AuthApi()
val changeUsernameRequest : ChangeUsernameRequest =  // ChangeUsernameRequest | 
try {
    apiInstance.changeUsername(changeUsernameRequest)
} catch (e: ClientException) {
    println("4xx response calling AuthApi#changeUsername")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling AuthApi#changeUsername")
    e.printStackTrace()
}
```

### Parameters
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **changeUsernameRequest** | [**ChangeUsernameRequest**](ChangeUsernameRequest.md)|  | |

### Return type

null (empty response body)

### Authorization


Configure BearerAuth statically:
```kotlin
ApiClient.accessToken = ""
```

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

<a id="listDevices"></a>
# **listDevices**
> kotlin.collections.List&lt;DeviceInfo&gt; listDevices()

已登录设备列表

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = AuthApi()
try {
    val result : kotlin.collections.List<DeviceInfo> = apiInstance.listDevices()
    println(result)
} catch (e: ClientException) {
    println("4xx response calling AuthApi#listDevices")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling AuthApi#listDevices")
    e.printStackTrace()
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**kotlin.collections.List&lt;DeviceInfo&gt;**](DeviceInfo.md)

### Authorization


Configure BearerAuth statically:
```kotlin
ApiClient.accessToken = ""
```

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

<a id="login"></a>
# **login**
> LoginResponse login(loginRequest)

用户名密码登录,换取长期 token

使用用户名和密码登录。daemon 首次启动时生成随机凭证并打印到控制台; 未登录设备无需鉴权即可访问本端点(仅局域网可绑定)。 

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = AuthApi()
val loginRequest : LoginRequest =  // LoginRequest | 
try {
    val result : LoginResponse = apiInstance.login(loginRequest)
    println(result)
} catch (e: ClientException) {
    println("4xx response calling AuthApi#login")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling AuthApi#login")
    e.printStackTrace()
}
```

### Parameters
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **loginRequest** | [**LoginRequest**](LoginRequest.md)|  | |

### Return type

[**LoginResponse**](LoginResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

<a id="revokeDevice"></a>
# **revokeDevice**
> revokeDevice(deviceId)

吊销指定设备的 token

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = AuthApi()
val deviceId : kotlin.String = deviceId_example // kotlin.String | 配对设备 id
try {
    apiInstance.revokeDevice(deviceId)
} catch (e: ClientException) {
    println("4xx response calling AuthApi#revokeDevice")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling AuthApi#revokeDevice")
    e.printStackTrace()
}
```

### Parameters
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **deviceId** | **kotlin.String**| 配对设备 id | |

### Return type

null (empty response body)

### Authorization


Configure BearerAuth statically:
```kotlin
ApiClient.accessToken = ""
```

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

