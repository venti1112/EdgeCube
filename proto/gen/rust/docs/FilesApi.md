# \FilesApi

All URIs are relative to *http://127.0.0.1:8760/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**complete_file_upload**](FilesApi.md#complete_file_upload) | **POST** /fs/upload-complete | 分片上传:完成(校验 sha256)
[**compress_file**](FilesApi.md#compress_file) | **POST** /fs/compress | 压缩为 zip
[**create_directory**](FilesApi.md#create_directory) | **POST** /fs/mkdir | 创建目录
[**delete_file**](FilesApi.md#delete_file) | **POST** /fs/delete | 删除文件/目录(目录递归)
[**download_file**](FilesApi.md#download_file) | **GET** /fs/download | 下载文件(二进制流)
[**extract_file**](FilesApi.md#extract_file) | **POST** /fs/extract | 解压归档(zip/tar/tar.gz)
[**init_file_upload**](FilesApi.md#init_file_upload) | **POST** /fs/upload-init | 分片上传:初始化
[**list_files**](FilesApi.md#list_files) | **GET** /fs/list | 列出目录(沙箱,以实例 cwd 为根)
[**move_file**](FilesApi.md#move_file) | **POST** /fs/move | 移动/重命名
[**upload_file_piece**](FilesApi.md#upload_file_piece) | **POST** /fs/upload-piece | 分片上传:写入一片



## complete_file_upload

> models::UploadCompleteResponse complete_file_upload(upload_complete_request)
分片上传:完成(校验 sha256)

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**upload_complete_request** | [**UploadCompleteRequest**](UploadCompleteRequest.md) |  | [required] |

### Return type

[**models::UploadCompleteResponse**](UploadCompleteResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## compress_file

> models::JobAccepted compress_file(fs_compress_request)
压缩为 zip

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**fs_compress_request** | [**FsCompressRequest**](FsCompressRequest.md) |  | [required] |

### Return type

[**models::JobAccepted**](JobAccepted.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_directory

> create_directory(fs_path_request)
创建目录

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**fs_path_request** | [**FsPathRequest**](FsPathRequest.md) |  | [required] |

### Return type

 (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_file

> delete_file(fs_path_request)
删除文件/目录(目录递归)

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**fs_path_request** | [**FsPathRequest**](FsPathRequest.md) |  | [required] |

### Return type

 (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## download_file

> std::path::PathBuf download_file(instance_id, path)
下载文件(二进制流)

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**instance_id** | **String** |  | [required] |
**path** | **String** |  | [required] |

### Return type

[**std::path::PathBuf**](std::path::PathBuf.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/octet-stream, application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## extract_file

> models::JobAccepted extract_file(fs_path_request)
解压归档(zip/tar/tar.gz)

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**fs_path_request** | [**FsPathRequest**](FsPathRequest.md) |  | [required] |

### Return type

[**models::JobAccepted**](JobAccepted.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## init_file_upload

> models::UploadSession init_file_upload(upload_init_request)
分片上传:初始化

分片断点续传三段式(upload-init / upload-piece / upload-complete), 对齐 MCSManager /upload-new + /upload-piece 设计。 分片大小由客户端自定(建议 1-8 MiB),服务端按 offset 写。 

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**upload_init_request** | [**UploadInitRequest**](UploadInitRequest.md) |  | [required] |

### Return type

[**models::UploadSession**](UploadSession.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_files

> models::FileListResponse list_files(instance_id, path)
列出目录(沙箱,以实例 cwd 为根)

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**instance_id** | **String** |  | [required] |
**path** | Option<**String**> | 相对实例 cwd 的路径,空为根 |  |[default to ]

### Return type

[**models::FileListResponse**](FileListResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## move_file

> move_file(fs_move_request)
移动/重命名

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**fs_move_request** | [**FsMoveRequest**](FsMoveRequest.md) |  | [required] |

### Return type

 (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## upload_file_piece

> models::UploadProgress upload_file_piece(upload_id, offset, body)
分片上传:写入一片

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**upload_id** | **String** |  | [required] |
**offset** | **i64** |  | [required] |
**body** | **std::path::PathBuf** |  | [required] |

### Return type

[**models::UploadProgress**](UploadProgress.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: application/octet-stream
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

