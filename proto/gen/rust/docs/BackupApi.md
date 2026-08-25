# \BackupApi

All URIs are relative to *http://127.0.0.1:8760/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**create_backup_job**](BackupApi.md#create_backup_job) | **POST** /backup/jobs | 创建备份任务
[**create_backup_target**](BackupApi.md#create_backup_target) | **POST** /backup/targets | 创建备份目标
[**delete_backup_job**](BackupApi.md#delete_backup_job) | **DELETE** /backup/jobs/{jobId} | 删除备份任务
[**delete_backup_target**](BackupApi.md#delete_backup_target) | **DELETE** /backup/targets/{targetId} | 删除备份目标
[**list_backup_jobs**](BackupApi.md#list_backup_jobs) | **GET** /backup/jobs | 备份任务列表
[**list_backup_targets**](BackupApi.md#list_backup_targets) | **GET** /backup/targets | 备份目标列表(local/FTP/SFTP)
[**trigger_backup_job**](BackupApi.md#trigger_backup_job) | **POST** /backup/jobs/{jobId}/trigger | 立即执行备份(进度走 WS backup/progress)
[**update_backup_job**](BackupApi.md#update_backup_job) | **PUT** /backup/jobs/{jobId} | 更新备份任务
[**update_backup_target**](BackupApi.md#update_backup_target) | **PUT** /backup/targets/{targetId} | 更新备份目标



## create_backup_job

> models::BackupJob create_backup_job(backup_job)
创建备份任务

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**backup_job** | [**BackupJob**](BackupJob.md) |  | [required] |

### Return type

[**models::BackupJob**](BackupJob.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_backup_target

> models::BackupTarget create_backup_target(backup_target)
创建备份目标

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**backup_target** | [**BackupTarget**](BackupTarget.md) |  | [required] |

### Return type

[**models::BackupTarget**](BackupTarget.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_backup_job

> delete_backup_job(job_id)
删除备份任务

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**job_id** | **String** |  | [required] |

### Return type

 (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_backup_target

> delete_backup_target(target_id)
删除备份目标

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**target_id** | **String** |  | [required] |

### Return type

 (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_backup_jobs

> Vec<models::BackupJob> list_backup_jobs()
备份任务列表

### Parameters

This endpoint does not need any parameter.

### Return type

[**Vec<models::BackupJob>**](BackupJob.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_backup_targets

> Vec<models::BackupTarget> list_backup_targets()
备份目标列表(local/FTP/SFTP)

### Parameters

This endpoint does not need any parameter.

### Return type

[**Vec<models::BackupTarget>**](BackupTarget.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## trigger_backup_job

> models::JobAccepted trigger_backup_job(job_id)
立即执行备份(进度走 WS backup/progress)

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**job_id** | **String** |  | [required] |

### Return type

[**models::JobAccepted**](JobAccepted.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## update_backup_job

> models::ErrorResponse update_backup_job(job_id, backup_job)
更新备份任务

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**job_id** | **String** |  | [required] |
**backup_job** | [**BackupJob**](BackupJob.md) |  | [required] |

### Return type

[**models::ErrorResponse**](ErrorResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## update_backup_target

> models::BackupTarget update_backup_target(target_id, backup_target)
更新备份目标

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**target_id** | **String** |  | [required] |
**backup_target** | [**BackupTarget**](BackupTarget.md) |  | [required] |

### Return type

[**models::BackupTarget**](BackupTarget.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

