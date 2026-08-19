# FtpApi

All URIs are relative to *http://127.0.0.1:8760/api/v1*

| Method | HTTP request | Description |
| ------------- | ------------- | ------------- |
| [**getFtpStatus**](FtpApi.md#getFtpStatus) | **GET** /ftp | FTP 服务状态与配置 |
| [**updateFtpConfig**](FtpApi.md#updateFtpConfig) | **PUT** /ftp | 更新 FTP 配置(启用/端口/账号/根目录) |


<a id="getFtpStatus"></a>
# **getFtpStatus**
> FtpStatus getFtpStatus()

FTP 服务状态与配置

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = FtpApi()
try {
    val result : FtpStatus = apiInstance.getFtpStatus()
    println(result)
} catch (e: ClientException) {
    println("4xx response calling FtpApi#getFtpStatus")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling FtpApi#getFtpStatus")
    e.printStackTrace()
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**FtpStatus**](FtpStatus.md)

### Authorization


Configure BearerAuth statically:
```kotlin
ApiClient.accessToken = ""
```

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

<a id="updateFtpConfig"></a>
# **updateFtpConfig**
> FtpStatus updateFtpConfig(ftpConfig)

更新 FTP 配置(启用/端口/账号/根目录)

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = FtpApi()
val ftpConfig : FtpConfig =  // FtpConfig | 
try {
    val result : FtpStatus = apiInstance.updateFtpConfig(ftpConfig)
    println(result)
} catch (e: ClientException) {
    println("4xx response calling FtpApi#updateFtpConfig")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling FtpApi#updateFtpConfig")
    e.printStackTrace()
}
```

### Parameters
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **ftpConfig** | [**FtpConfig**](FtpConfig.md)|  | |

### Return type

[**FtpStatus**](FtpStatus.md)

### Authorization


Configure BearerAuth statically:
```kotlin
ApiClient.accessToken = ""
```

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

