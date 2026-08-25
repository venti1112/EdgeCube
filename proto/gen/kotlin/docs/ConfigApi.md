# ConfigApi

All URIs are relative to *http://127.0.0.1:8760/api/v1*

| Method | HTTP request | Description |
| ------------- | ------------- | ------------- |
| [**getConfigEntry**](ConfigApi.md#getConfigEntry) | **GET** /config/{key} | 读取设置项 |
| [**updateConfigEntry**](ConfigApi.md#updateConfigEntry) | **PUT** /config/{key} | 写入设置项 |


<a id="getConfigEntry"></a>
# **getConfigEntry**
> ConfigEntry getConfigEntry(key)

读取设置项

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = ConfigApi()
val key : kotlin.String = network // kotlin.String | 
try {
    val result : ConfigEntry = apiInstance.getConfigEntry(key)
    println(result)
} catch (e: ClientException) {
    println("4xx response calling ConfigApi#getConfigEntry")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling ConfigApi#getConfigEntry")
    e.printStackTrace()
}
```

### Parameters
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **key** | **kotlin.String**|  | |

### Return type

[**ConfigEntry**](ConfigEntry.md)

### Authorization


Configure BearerAuth statically:
```kotlin
ApiClient.accessToken = ""
```

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

<a id="updateConfigEntry"></a>
# **updateConfigEntry**
> ConfigEntry updateConfigEntry(key, configEntry)

写入设置项

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = ConfigApi()
val key : kotlin.String = network // kotlin.String | 
val configEntry : ConfigEntry =  // ConfigEntry | 
try {
    val result : ConfigEntry = apiInstance.updateConfigEntry(key, configEntry)
    println(result)
} catch (e: ClientException) {
    println("4xx response calling ConfigApi#updateConfigEntry")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling ConfigApi#updateConfigEntry")
    e.printStackTrace()
}
```

### Parameters
| **key** | **kotlin.String**|  | |
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **configEntry** | [**ConfigEntry**](ConfigEntry.md)|  | |

### Return type

[**ConfigEntry**](ConfigEntry.md)

### Authorization


Configure BearerAuth statically:
```kotlin
ApiClient.accessToken = ""
```

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

