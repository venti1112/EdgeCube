# edgecube_api_client.api.FilesApi

## Load the API package
```dart
import 'package:edgecube_api_client/api.dart';
```

All URIs are relative to *http://127.0.0.1:8760/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**completeFileUpload**](FilesApi.md#completefileupload) | **POST** /fs/upload-complete | 分片上传:完成(校验 sha256)
[**compressFile**](FilesApi.md#compressfile) | **POST** /fs/compress | 压缩为 zip
[**createDirectory**](FilesApi.md#createdirectory) | **POST** /fs/mkdir | 创建目录
[**deleteFile**](FilesApi.md#deletefile) | **POST** /fs/delete | 删除文件/目录(目录递归)
[**downloadFile**](FilesApi.md#downloadfile) | **GET** /fs/download | 下载文件(二进制流)
[**extractFile**](FilesApi.md#extractfile) | **POST** /fs/extract | 解压归档(zip/tar/tar.gz)
[**initFileUpload**](FilesApi.md#initfileupload) | **POST** /fs/upload-init | 分片上传:初始化
[**listFiles**](FilesApi.md#listfiles) | **GET** /fs/list | 列出目录(沙箱,以实例 cwd 为根)
[**moveFile**](FilesApi.md#movefile) | **POST** /fs/move | 移动/重命名
[**uploadFilePiece**](FilesApi.md#uploadfilepiece) | **POST** /fs/upload-piece | 分片上传:写入一片


# **completeFileUpload**
> UploadCompleteResponse completeFileUpload(uploadCompleteRequest)

分片上传:完成(校验 sha256)

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getFilesApi();
final UploadCompleteRequest uploadCompleteRequest = ; // UploadCompleteRequest | 

try {
    final response = api.completeFileUpload(uploadCompleteRequest);
    print(response);
} on DioException catch (e) {
    print('Exception when calling FilesApi->completeFileUpload: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **uploadCompleteRequest** | [**UploadCompleteRequest**](UploadCompleteRequest.md)|  | 

### Return type

[**UploadCompleteResponse**](UploadCompleteResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **compressFile**
> JobAccepted compressFile(fsCompressRequest)

压缩为 zip

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getFilesApi();
final FsCompressRequest fsCompressRequest = ; // FsCompressRequest | 

try {
    final response = api.compressFile(fsCompressRequest);
    print(response);
} on DioException catch (e) {
    print('Exception when calling FilesApi->compressFile: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **fsCompressRequest** | [**FsCompressRequest**](FsCompressRequest.md)|  | 

### Return type

[**JobAccepted**](JobAccepted.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **createDirectory**
> createDirectory(fsPathRequest)

创建目录

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getFilesApi();
final FsPathRequest fsPathRequest = ; // FsPathRequest | 

try {
    api.createDirectory(fsPathRequest);
} on DioException catch (e) {
    print('Exception when calling FilesApi->createDirectory: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **fsPathRequest** | [**FsPathRequest**](FsPathRequest.md)|  | 

### Return type

void (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **deleteFile**
> deleteFile(fsPathRequest)

删除文件/目录(目录递归)

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getFilesApi();
final FsPathRequest fsPathRequest = ; // FsPathRequest | 

try {
    api.deleteFile(fsPathRequest);
} on DioException catch (e) {
    print('Exception when calling FilesApi->deleteFile: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **fsPathRequest** | [**FsPathRequest**](FsPathRequest.md)|  | 

### Return type

void (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **downloadFile**
> Uint8List downloadFile(instanceId, path)

下载文件(二进制流)

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getFilesApi();
final String instanceId = instanceId_example; // String | 
final String path = path_example; // String | 

try {
    final response = api.downloadFile(instanceId, path);
    print(response);
} on DioException catch (e) {
    print('Exception when calling FilesApi->downloadFile: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **instanceId** | **String**|  | 
 **path** | **String**|  | 

### Return type

[**Uint8List**](Uint8List.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/octet-stream, application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **extractFile**
> JobAccepted extractFile(fsPathRequest)

解压归档(zip/tar/tar.gz)

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getFilesApi();
final FsPathRequest fsPathRequest = ; // FsPathRequest | 

try {
    final response = api.extractFile(fsPathRequest);
    print(response);
} on DioException catch (e) {
    print('Exception when calling FilesApi->extractFile: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **fsPathRequest** | [**FsPathRequest**](FsPathRequest.md)|  | 

### Return type

[**JobAccepted**](JobAccepted.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **initFileUpload**
> UploadSession initFileUpload(uploadInitRequest)

分片上传:初始化

分片断点续传三段式(upload-init / upload-piece / upload-complete), 对齐 MCSManager /upload-new + /upload-piece 设计。 分片大小由客户端自定(建议 1-8 MiB),服务端按 offset 写。 

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getFilesApi();
final UploadInitRequest uploadInitRequest = ; // UploadInitRequest | 

try {
    final response = api.initFileUpload(uploadInitRequest);
    print(response);
} on DioException catch (e) {
    print('Exception when calling FilesApi->initFileUpload: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **uploadInitRequest** | [**UploadInitRequest**](UploadInitRequest.md)|  | 

### Return type

[**UploadSession**](UploadSession.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **listFiles**
> FileListResponse listFiles(instanceId, path)

列出目录(沙箱,以实例 cwd 为根)

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getFilesApi();
final String instanceId = instanceId_example; // String | 
final String path = path_example; // String | 相对实例 cwd 的路径,空为根

try {
    final response = api.listFiles(instanceId, path);
    print(response);
} on DioException catch (e) {
    print('Exception when calling FilesApi->listFiles: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **instanceId** | **String**|  | 
 **path** | **String**| 相对实例 cwd 的路径,空为根 | [optional] [default to '']

### Return type

[**FileListResponse**](FileListResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **moveFile**
> moveFile(fsMoveRequest)

移动/重命名

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getFilesApi();
final FsMoveRequest fsMoveRequest = ; // FsMoveRequest | 

try {
    api.moveFile(fsMoveRequest);
} on DioException catch (e) {
    print('Exception when calling FilesApi->moveFile: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **fsMoveRequest** | [**FsMoveRequest**](FsMoveRequest.md)|  | 

### Return type

void (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **uploadFilePiece**
> UploadProgress uploadFilePiece(uploadId, offset, body)

分片上传:写入一片

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getFilesApi();
final String uploadId = uploadId_example; // String | 
final int offset = 789; // int | 
final MultipartFile body = BINARY_DATA_HERE; // MultipartFile | 

try {
    final response = api.uploadFilePiece(uploadId, offset, body);
    print(response);
} on DioException catch (e) {
    print('Exception when calling FilesApi->uploadFilePiece: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **uploadId** | **String**|  | 
 **offset** | **int**|  | 
 **body** | **MultipartFile**|  | 

### Return type

[**UploadProgress**](UploadProgress.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/octet-stream
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

