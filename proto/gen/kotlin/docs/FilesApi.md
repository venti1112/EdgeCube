# FilesApi

All URIs are relative to *http://127.0.0.1:8760/api/v1*

| Method | HTTP request | Description |
| ------------- | ------------- | ------------- |
| [**completeFileUpload**](FilesApi.md#completeFileUpload) | **POST** /fs/upload-complete | 分片上传:完成(校验 sha256) |
| [**compressFile**](FilesApi.md#compressFile) | **POST** /fs/compress | 压缩为 zip |
| [**createDirectory**](FilesApi.md#createDirectory) | **POST** /fs/mkdir | 创建目录 |
| [**deleteFile**](FilesApi.md#deleteFile) | **POST** /fs/delete | 删除文件/目录(目录递归) |
| [**downloadFile**](FilesApi.md#downloadFile) | **GET** /fs/download | 下载文件(二进制流) |
| [**extractFile**](FilesApi.md#extractFile) | **POST** /fs/extract | 解压归档(zip/tar/tar.gz) |
| [**initFileUpload**](FilesApi.md#initFileUpload) | **POST** /fs/upload-init | 分片上传:初始化 |
| [**listFiles**](FilesApi.md#listFiles) | **GET** /fs/list | 列出目录(沙箱,以实例 cwd 为根) |
| [**moveFile**](FilesApi.md#moveFile) | **POST** /fs/move | 移动/重命名 |
| [**uploadFilePiece**](FilesApi.md#uploadFilePiece) | **POST** /fs/upload-piece | 分片上传:写入一片 |


<a id="completeFileUpload"></a>
# **completeFileUpload**
> UploadCompleteResponse completeFileUpload(uploadCompleteRequest)

分片上传:完成(校验 sha256)

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = FilesApi()
val uploadCompleteRequest : UploadCompleteRequest =  // UploadCompleteRequest | 
try {
    val result : UploadCompleteResponse = apiInstance.completeFileUpload(uploadCompleteRequest)
    println(result)
} catch (e: ClientException) {
    println("4xx response calling FilesApi#completeFileUpload")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling FilesApi#completeFileUpload")
    e.printStackTrace()
}
```

### Parameters
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **uploadCompleteRequest** | [**UploadCompleteRequest**](UploadCompleteRequest.md)|  | |

### Return type

[**UploadCompleteResponse**](UploadCompleteResponse.md)

### Authorization


Configure BearerAuth statically:
```kotlin
ApiClient.accessToken = ""
```

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

<a id="compressFile"></a>
# **compressFile**
> JobAccepted compressFile(fsCompressRequest)

压缩为 zip

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = FilesApi()
val fsCompressRequest : FsCompressRequest =  // FsCompressRequest | 
try {
    val result : JobAccepted = apiInstance.compressFile(fsCompressRequest)
    println(result)
} catch (e: ClientException) {
    println("4xx response calling FilesApi#compressFile")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling FilesApi#compressFile")
    e.printStackTrace()
}
```

### Parameters
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **fsCompressRequest** | [**FsCompressRequest**](FsCompressRequest.md)|  | |

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

<a id="createDirectory"></a>
# **createDirectory**
> createDirectory(fsPathRequest)

创建目录

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = FilesApi()
val fsPathRequest : FsPathRequest =  // FsPathRequest | 
try {
    apiInstance.createDirectory(fsPathRequest)
} catch (e: ClientException) {
    println("4xx response calling FilesApi#createDirectory")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling FilesApi#createDirectory")
    e.printStackTrace()
}
```

### Parameters
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **fsPathRequest** | [**FsPathRequest**](FsPathRequest.md)|  | |

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

<a id="deleteFile"></a>
# **deleteFile**
> deleteFile(fsPathRequest)

删除文件/目录(目录递归)

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = FilesApi()
val fsPathRequest : FsPathRequest =  // FsPathRequest | 
try {
    apiInstance.deleteFile(fsPathRequest)
} catch (e: ClientException) {
    println("4xx response calling FilesApi#deleteFile")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling FilesApi#deleteFile")
    e.printStackTrace()
}
```

### Parameters
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **fsPathRequest** | [**FsPathRequest**](FsPathRequest.md)|  | |

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

<a id="downloadFile"></a>
# **downloadFile**
> java.io.File downloadFile(instanceId, path)

下载文件(二进制流)

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = FilesApi()
val instanceId : kotlin.String = instanceId_example // kotlin.String | 
val path : kotlin.String = path_example // kotlin.String | 
try {
    val result : java.io.File = apiInstance.downloadFile(instanceId, path)
    println(result)
} catch (e: ClientException) {
    println("4xx response calling FilesApi#downloadFile")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling FilesApi#downloadFile")
    e.printStackTrace()
}
```

### Parameters
| **instanceId** | **kotlin.String**|  | |
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **path** | **kotlin.String**|  | |

### Return type

[**java.io.File**](java.io.File.md)

### Authorization


Configure BearerAuth statically:
```kotlin
ApiClient.accessToken = ""
```

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/octet-stream, application/json

<a id="extractFile"></a>
# **extractFile**
> JobAccepted extractFile(fsPathRequest)

解压归档(zip/tar/tar.gz)

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = FilesApi()
val fsPathRequest : FsPathRequest =  // FsPathRequest | 
try {
    val result : JobAccepted = apiInstance.extractFile(fsPathRequest)
    println(result)
} catch (e: ClientException) {
    println("4xx response calling FilesApi#extractFile")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling FilesApi#extractFile")
    e.printStackTrace()
}
```

### Parameters
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **fsPathRequest** | [**FsPathRequest**](FsPathRequest.md)|  | |

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

<a id="initFileUpload"></a>
# **initFileUpload**
> UploadSession initFileUpload(uploadInitRequest)

分片上传:初始化

分片断点续传三段式(upload-init / upload-piece / upload-complete), 对齐 MCSManager /upload-new + /upload-piece 设计。 分片大小由客户端自定(建议 1-8 MiB),服务端按 offset 写。 

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = FilesApi()
val uploadInitRequest : UploadInitRequest =  // UploadInitRequest | 
try {
    val result : UploadSession = apiInstance.initFileUpload(uploadInitRequest)
    println(result)
} catch (e: ClientException) {
    println("4xx response calling FilesApi#initFileUpload")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling FilesApi#initFileUpload")
    e.printStackTrace()
}
```

### Parameters
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **uploadInitRequest** | [**UploadInitRequest**](UploadInitRequest.md)|  | |

### Return type

[**UploadSession**](UploadSession.md)

### Authorization


Configure BearerAuth statically:
```kotlin
ApiClient.accessToken = ""
```

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

<a id="listFiles"></a>
# **listFiles**
> FileListResponse listFiles(instanceId, path)

列出目录(沙箱,以实例 cwd 为根)

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = FilesApi()
val instanceId : kotlin.String = instanceId_example // kotlin.String | 
val path : kotlin.String = path_example // kotlin.String | 相对实例 cwd 的路径,空为根
try {
    val result : FileListResponse = apiInstance.listFiles(instanceId, path)
    println(result)
} catch (e: ClientException) {
    println("4xx response calling FilesApi#listFiles")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling FilesApi#listFiles")
    e.printStackTrace()
}
```

### Parameters
| **instanceId** | **kotlin.String**|  | |
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **path** | **kotlin.String**| 相对实例 cwd 的路径,空为根 | [optional] [default to &quot;&quot;] |

### Return type

[**FileListResponse**](FileListResponse.md)

### Authorization


Configure BearerAuth statically:
```kotlin
ApiClient.accessToken = ""
```

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

<a id="moveFile"></a>
# **moveFile**
> moveFile(fsMoveRequest)

移动/重命名

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = FilesApi()
val fsMoveRequest : FsMoveRequest =  // FsMoveRequest | 
try {
    apiInstance.moveFile(fsMoveRequest)
} catch (e: ClientException) {
    println("4xx response calling FilesApi#moveFile")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling FilesApi#moveFile")
    e.printStackTrace()
}
```

### Parameters
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **fsMoveRequest** | [**FsMoveRequest**](FsMoveRequest.md)|  | |

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

<a id="uploadFilePiece"></a>
# **uploadFilePiece**
> UploadProgress uploadFilePiece(uploadId, offset, body)

分片上传:写入一片

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = FilesApi()
val uploadId : kotlin.String = uploadId_example // kotlin.String | 
val offset : kotlin.Long = 789 // kotlin.Long | 
val body : java.io.File = BINARY_DATA_HERE // java.io.File | 
try {
    val result : UploadProgress = apiInstance.uploadFilePiece(uploadId, offset, body)
    println(result)
} catch (e: ClientException) {
    println("4xx response calling FilesApi#uploadFilePiece")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling FilesApi#uploadFilePiece")
    e.printStackTrace()
}
```

### Parameters
| **uploadId** | **kotlin.String**|  | |
| **offset** | **kotlin.Long**|  | |
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **body** | **java.io.File**|  | |

### Return type

[**UploadProgress**](UploadProgress.md)

### Authorization


Configure BearerAuth statically:
```kotlin
ApiClient.accessToken = ""
```

### HTTP request headers

 - **Content-Type**: application/octet-stream
 - **Accept**: application/json

