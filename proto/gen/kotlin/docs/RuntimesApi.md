# RuntimesApi

All URIs are relative to *http://127.0.0.1:8760/api/v1*

| Method | HTTP request | Description |
| ------------- | ------------- | ------------- |
| [**deleteRuntime**](RuntimesApi.md#deleteRuntime) | **DELETE** /runtimes/{runtimeId} | 卸载运行时 |
| [**getRuntimeCatalog**](RuntimesApi.md#getRuntimeCatalog) | **GET** /runtimes/catalog | 可安装版本清单(官方源) |
| [**installRuntime**](RuntimesApi.md#installRuntime) | **POST** /runtimes/install | 安装运行时(官方源下载,进度走 WS download/progress) |
| [**listRuntimes**](RuntimesApi.md#listRuntimes) | **GET** /runtimes | 已安装运行时列表 |


<a id="deleteRuntime"></a>
# **deleteRuntime**
> deleteRuntime(runtimeId)

卸载运行时

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = RuntimesApi()
val runtimeId : kotlin.String = runtimeId_example // kotlin.String | 
try {
    apiInstance.deleteRuntime(runtimeId)
} catch (e: ClientException) {
    println("4xx response calling RuntimesApi#deleteRuntime")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling RuntimesApi#deleteRuntime")
    e.printStackTrace()
}
```

### Parameters
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **runtimeId** | **kotlin.String**|  | |

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

<a id="getRuntimeCatalog"></a>
# **getRuntimeCatalog**
> RuntimeCatalog getRuntimeCatalog(type)

可安装版本清单(官方源)

拉取对应官方渠道的可用版本(java: Adoptium API;php: 权威预编译源;frpc: GitHub Releases)。

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = RuntimesApi()
val type : RuntimeType =  // RuntimeType | 
try {
    val result : RuntimeCatalog = apiInstance.getRuntimeCatalog(type)
    println(result)
} catch (e: ClientException) {
    println("4xx response calling RuntimesApi#getRuntimeCatalog")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling RuntimesApi#getRuntimeCatalog")
    e.printStackTrace()
}
```

### Parameters
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **type** | [**RuntimeType**](.md)|  | [enum: java, php, frpc] |

### Return type

[**RuntimeCatalog**](RuntimeCatalog.md)

### Authorization


Configure BearerAuth statically:
```kotlin
ApiClient.accessToken = ""
```

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

<a id="installRuntime"></a>
# **installRuntime**
> JobAccepted installRuntime(runtimeInstallRequest)

安装运行时(官方源下载,进度走 WS download/progress)

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = RuntimesApi()
val runtimeInstallRequest : RuntimeInstallRequest =  // RuntimeInstallRequest | 
try {
    val result : JobAccepted = apiInstance.installRuntime(runtimeInstallRequest)
    println(result)
} catch (e: ClientException) {
    println("4xx response calling RuntimesApi#installRuntime")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling RuntimesApi#installRuntime")
    e.printStackTrace()
}
```

### Parameters
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **runtimeInstallRequest** | [**RuntimeInstallRequest**](RuntimeInstallRequest.md)|  | |

### Return type

[**JobAccepted**](JobAccepted.md)

### Authorization


Configure BearerAuth statically:
```kotlin
ApiClient.accessToken = ""
```

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

<a id="listRuntimes"></a>
# **listRuntimes**
> kotlin.collections.List&lt;RuntimeInfo&gt; listRuntimes()

已安装运行时列表

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = RuntimesApi()
try {
    val result : kotlin.collections.List<RuntimeInfo> = apiInstance.listRuntimes()
    println(result)
} catch (e: ClientException) {
    println("4xx response calling RuntimesApi#listRuntimes")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling RuntimesApi#listRuntimes")
    e.printStackTrace()
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**kotlin.collections.List&lt;RuntimeInfo&gt;**](RuntimeInfo.md)

### Authorization


Configure BearerAuth statically:
```kotlin
ApiClient.accessToken = ""
```

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

