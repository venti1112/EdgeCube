# SshApi

All URIs are relative to *http://127.0.0.1:8760/api/v1*

| Method | HTTP request | Description |
| ------------- | ------------- | ------------- |
| [**getSshStatus**](SshApi.md#getSshStatus) | **GET** /ssh | SSH 服务状态与配置 |
| [**updateSshConfig**](SshApi.md#updateSshConfig) | **PUT** /ssh | 更新 SSH 配置(启用/端口/账号/根目录) |


<a id="getSshStatus"></a>
# **getSshStatus**
> SshStatus getSshStatus()

SSH 服务状态与配置

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = SshApi()
try {
    val result : SshStatus = apiInstance.getSshStatus()
    println(result)
} catch (e: ClientException) {
    println("4xx response calling SshApi#getSshStatus")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling SshApi#getSshStatus")
    e.printStackTrace()
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**SshStatus**](SshStatus.md)

### Authorization


Configure BearerAuth statically:
```kotlin
ApiClient.accessToken = ""
```

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

<a id="updateSshConfig"></a>
# **updateSshConfig**
> SshStatus updateSshConfig(sshConfig)

更新 SSH 配置(启用/端口/账号/根目录)

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = SshApi()
val sshConfig : SshConfig =  // SshConfig | 
try {
    val result : SshStatus = apiInstance.updateSshConfig(sshConfig)
    println(result)
} catch (e: ClientException) {
    println("4xx response calling SshApi#updateSshConfig")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling SshApi#updateSshConfig")
    e.printStackTrace()
}
```

### Parameters
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **sshConfig** | [**SshConfig**](SshConfig.md)|  | |

### Return type

[**SshStatus**](SshStatus.md)

### Authorization


Configure BearerAuth statically:
```kotlin
ApiClient.accessToken = ""
```

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

