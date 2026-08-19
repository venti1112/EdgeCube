# AuthApi

All URIs are relative to *http://127.0.0.1:8760/api/v1*

| Method | HTTP request | Description |
| ------------- | ------------- | ------------- |
| [**getPairingCode**](AuthApi.md#getPairingCode) | **GET** /auth/pairing-code | 获取当前配对码 |
| [**listDevices**](AuthApi.md#listDevices) | **GET** /auth/tokens | 已配对设备列表 |
| [**pairDevice**](AuthApi.md#pairDevice) | **POST** /auth/pair | 对码配对,换取长期 token |
| [**revokeDevice**](AuthApi.md#revokeDevice) | **DELETE** /auth/tokens/{deviceId} | 吊销指定设备的 token |
| [**rotatePairingCode**](AuthApi.md#rotatePairingCode) | **POST** /auth/pairing-code | 轮换配对码 |


<a id="getPairingCode"></a>
# **getPairingCode**
> PairingCode getPairingCode()

获取当前配对码

返回当前生效的 6 位配对码。配对码用于本地/局域网设备换取 token; 未配对设备无需鉴权即可访问本端点(仅局域网可绑定)。 

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = AuthApi()
try {
    val result : PairingCode = apiInstance.getPairingCode()
    println(result)
} catch (e: ClientException) {
    println("4xx response calling AuthApi#getPairingCode")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling AuthApi#getPairingCode")
    e.printStackTrace()
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**PairingCode**](PairingCode.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

<a id="listDevices"></a>
# **listDevices**
> kotlin.collections.List&lt;DeviceInfo&gt; listDevices()

已配对设备列表

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

<a id="pairDevice"></a>
# **pairDevice**
> PairResponse pairDevice(pairRequest)

对码配对,换取长期 token

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = AuthApi()
val pairRequest : PairRequest =  // PairRequest | 
try {
    val result : PairResponse = apiInstance.pairDevice(pairRequest)
    println(result)
} catch (e: ClientException) {
    println("4xx response calling AuthApi#pairDevice")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling AuthApi#pairDevice")
    e.printStackTrace()
}
```

### Parameters
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **pairRequest** | [**PairRequest**](PairRequest.md)|  | |

### Return type

[**PairResponse**](PairResponse.md)

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

<a id="rotatePairingCode"></a>
# **rotatePairingCode**
> PairingCode rotatePairingCode()

轮换配对码

使当前配对码失效并生成新码。

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = AuthApi()
try {
    val result : PairingCode = apiInstance.rotatePairingCode()
    println(result)
} catch (e: ClientException) {
    println("4xx response calling AuthApi#rotatePairingCode")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling AuthApi#rotatePairingCode")
    e.printStackTrace()
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**PairingCode**](PairingCode.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

