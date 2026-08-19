# HealthApi

All URIs are relative to *http://127.0.0.1:8760/api/v1*

| Method | HTTP request | Description |
| ------------- | ------------- | ------------- |
| [**getHealth**](HealthApi.md#getHealth) | **GET** /health | 健康检查(未配对可访问) |


<a id="getHealth"></a>
# **getHealth**
> HealthResponse getHealth()

健康检查(未配对可访问)

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = HealthApi()
try {
    val result : HealthResponse = apiInstance.getHealth()
    println(result)
} catch (e: ClientException) {
    println("4xx response calling HealthApi#getHealth")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling HealthApi#getHealth")
    e.printStackTrace()
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**HealthResponse**](HealthResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

