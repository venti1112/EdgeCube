# MonitorApi

All URIs are relative to *http://127.0.0.1:8760/api/v1*

| Method | HTTP request | Description |
| ------------- | ------------- | ------------- |
| [**getMonitorSnapshot**](MonitorApi.md#getMonitorSnapshot) | **GET** /monitor/snapshot | 系统监控快照(实时曲线走 WS monitor/stats) |


<a id="getMonitorSnapshot"></a>
# **getMonitorSnapshot**
> MonitorSnapshot getMonitorSnapshot()

系统监控快照(实时曲线走 WS monitor/stats)

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = MonitorApi()
try {
    val result : MonitorSnapshot = apiInstance.getMonitorSnapshot()
    println(result)
} catch (e: ClientException) {
    println("4xx response calling MonitorApi#getMonitorSnapshot")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling MonitorApi#getMonitorSnapshot")
    e.printStackTrace()
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**MonitorSnapshot**](MonitorSnapshot.md)

### Authorization


Configure BearerAuth statically:
```kotlin
ApiClient.accessToken = ""
```

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

