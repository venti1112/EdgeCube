# BackupApi

All URIs are relative to *http://127.0.0.1:8760/api/v1*

| Method | HTTP request | Description |
| ------------- | ------------- | ------------- |
| [**createBackupJob**](BackupApi.md#createBackupJob) | **POST** /backup/jobs | 创建备份任务 |
| [**createBackupTarget**](BackupApi.md#createBackupTarget) | **POST** /backup/targets | 创建备份目标 |
| [**deleteBackupJob**](BackupApi.md#deleteBackupJob) | **DELETE** /backup/jobs/{jobId} | 删除备份任务 |
| [**deleteBackupTarget**](BackupApi.md#deleteBackupTarget) | **DELETE** /backup/targets/{targetId} | 删除备份目标 |
| [**listBackupJobs**](BackupApi.md#listBackupJobs) | **GET** /backup/jobs | 备份任务列表 |
| [**listBackupTargets**](BackupApi.md#listBackupTargets) | **GET** /backup/targets | 备份目标列表(local/FTP/SFTP) |
| [**triggerBackupJob**](BackupApi.md#triggerBackupJob) | **POST** /backup/jobs/{jobId}/trigger | 立即执行备份(进度走 WS backup/progress) |
| [**updateBackupJob**](BackupApi.md#updateBackupJob) | **PUT** /backup/jobs/{jobId} | 更新备份任务 |
| [**updateBackupTarget**](BackupApi.md#updateBackupTarget) | **PUT** /backup/targets/{targetId} | 更新备份目标 |


<a id="createBackupJob"></a>
# **createBackupJob**
> BackupJob createBackupJob(backupJob)

创建备份任务

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = BackupApi()
val backupJob : BackupJob =  // BackupJob | 
try {
    val result : BackupJob = apiInstance.createBackupJob(backupJob)
    println(result)
} catch (e: ClientException) {
    println("4xx response calling BackupApi#createBackupJob")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling BackupApi#createBackupJob")
    e.printStackTrace()
}
```

### Parameters
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **backupJob** | [**BackupJob**](BackupJob.md)|  | |

### Return type

[**BackupJob**](BackupJob.md)

### Authorization


Configure BearerAuth statically:
```kotlin
ApiClient.accessToken = ""
```

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

<a id="createBackupTarget"></a>
# **createBackupTarget**
> BackupTarget createBackupTarget(backupTarget)

创建备份目标

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = BackupApi()
val backupTarget : BackupTarget =  // BackupTarget | 
try {
    val result : BackupTarget = apiInstance.createBackupTarget(backupTarget)
    println(result)
} catch (e: ClientException) {
    println("4xx response calling BackupApi#createBackupTarget")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling BackupApi#createBackupTarget")
    e.printStackTrace()
}
```

### Parameters
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **backupTarget** | [**BackupTarget**](BackupTarget.md)|  | |

### Return type

[**BackupTarget**](BackupTarget.md)

### Authorization


Configure BearerAuth statically:
```kotlin
ApiClient.accessToken = ""
```

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

<a id="deleteBackupJob"></a>
# **deleteBackupJob**
> deleteBackupJob(jobId)

删除备份任务

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = BackupApi()
val jobId : kotlin.String = jobId_example // kotlin.String | 
try {
    apiInstance.deleteBackupJob(jobId)
} catch (e: ClientException) {
    println("4xx response calling BackupApi#deleteBackupJob")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling BackupApi#deleteBackupJob")
    e.printStackTrace()
}
```

### Parameters
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **jobId** | **kotlin.String**|  | |

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

<a id="deleteBackupTarget"></a>
# **deleteBackupTarget**
> deleteBackupTarget(targetId)

删除备份目标

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = BackupApi()
val targetId : kotlin.String = targetId_example // kotlin.String | 
try {
    apiInstance.deleteBackupTarget(targetId)
} catch (e: ClientException) {
    println("4xx response calling BackupApi#deleteBackupTarget")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling BackupApi#deleteBackupTarget")
    e.printStackTrace()
}
```

### Parameters
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **targetId** | **kotlin.String**|  | |

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

<a id="listBackupJobs"></a>
# **listBackupJobs**
> kotlin.collections.List&lt;BackupJob&gt; listBackupJobs()

备份任务列表

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = BackupApi()
try {
    val result : kotlin.collections.List<BackupJob> = apiInstance.listBackupJobs()
    println(result)
} catch (e: ClientException) {
    println("4xx response calling BackupApi#listBackupJobs")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling BackupApi#listBackupJobs")
    e.printStackTrace()
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**kotlin.collections.List&lt;BackupJob&gt;**](BackupJob.md)

### Authorization


Configure BearerAuth statically:
```kotlin
ApiClient.accessToken = ""
```

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

<a id="listBackupTargets"></a>
# **listBackupTargets**
> kotlin.collections.List&lt;BackupTarget&gt; listBackupTargets()

备份目标列表(local/FTP/SFTP)

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = BackupApi()
try {
    val result : kotlin.collections.List<BackupTarget> = apiInstance.listBackupTargets()
    println(result)
} catch (e: ClientException) {
    println("4xx response calling BackupApi#listBackupTargets")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling BackupApi#listBackupTargets")
    e.printStackTrace()
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**kotlin.collections.List&lt;BackupTarget&gt;**](BackupTarget.md)

### Authorization


Configure BearerAuth statically:
```kotlin
ApiClient.accessToken = ""
```

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

<a id="triggerBackupJob"></a>
# **triggerBackupJob**
> JobAccepted triggerBackupJob(jobId)

立即执行备份(进度走 WS backup/progress)

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = BackupApi()
val jobId : kotlin.String = jobId_example // kotlin.String | 
try {
    val result : JobAccepted = apiInstance.triggerBackupJob(jobId)
    println(result)
} catch (e: ClientException) {
    println("4xx response calling BackupApi#triggerBackupJob")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling BackupApi#triggerBackupJob")
    e.printStackTrace()
}
```

### Parameters
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **jobId** | **kotlin.String**|  | |

### Return type

[**JobAccepted**](JobAccepted.md)

### Authorization


Configure BearerAuth statically:
```kotlin
ApiClient.accessToken = ""
```

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

<a id="updateBackupJob"></a>
# **updateBackupJob**
> ErrorResponse updateBackupJob(jobId, backupJob)

更新备份任务

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = BackupApi()
val jobId : kotlin.String = jobId_example // kotlin.String | 
val backupJob : BackupJob =  // BackupJob | 
try {
    val result : ErrorResponse = apiInstance.updateBackupJob(jobId, backupJob)
    println(result)
} catch (e: ClientException) {
    println("4xx response calling BackupApi#updateBackupJob")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling BackupApi#updateBackupJob")
    e.printStackTrace()
}
```

### Parameters
| **jobId** | **kotlin.String**|  | |
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **backupJob** | [**BackupJob**](BackupJob.md)|  | |

### Return type

[**ErrorResponse**](ErrorResponse.md)

### Authorization


Configure BearerAuth statically:
```kotlin
ApiClient.accessToken = ""
```

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

<a id="updateBackupTarget"></a>
# **updateBackupTarget**
> BackupTarget updateBackupTarget(targetId, backupTarget)

更新备份目标

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = BackupApi()
val targetId : kotlin.String = targetId_example // kotlin.String | 
val backupTarget : BackupTarget =  // BackupTarget | 
try {
    val result : BackupTarget = apiInstance.updateBackupTarget(targetId, backupTarget)
    println(result)
} catch (e: ClientException) {
    println("4xx response calling BackupApi#updateBackupTarget")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling BackupApi#updateBackupTarget")
    e.printStackTrace()
}
```

### Parameters
| **targetId** | **kotlin.String**|  | |
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **backupTarget** | [**BackupTarget**](BackupTarget.md)|  | |

### Return type

[**BackupTarget**](BackupTarget.md)

### Authorization


Configure BearerAuth statically:
```kotlin
ApiClient.accessToken = ""
```

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

