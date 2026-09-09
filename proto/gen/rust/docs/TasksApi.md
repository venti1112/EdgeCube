# \TasksApi

All URIs are relative to *http://127.0.0.1:8760/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**cancel_task**](TasksApi.md#cancel_task) | **DELETE** /tasks/{jobId} | 取消任务
[**get_task**](TasksApi.md#get_task) | **GET** /tasks/{jobId} | 查询单个任务
[**list_tasks**](TasksApi.md#list_tasks) | **GET** /tasks | 任务列表(进行中优先 + 最近完成)



## cancel_task

> models::Task cancel_task(job_id)
取消任务

queued 任务直接移除;running 任务置取消标志,由执行体尽快中断。 已结束(succeeded/failed/cancelled)任务不可取消,返回 409。 取消结果回显最终 Task(status=cancelled)。 

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**job_id** | **uuid::Uuid** | 任务 id(即 Task.id,异步操作 202 响应中的 jobId) | [required] |

### Return type

[**models::Task**](Task.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_task

> models::Task get_task(job_id)
查询单个任务

返回任务详情;下载类任务运行时 progress 携带实时进度 (已下载/总大小/速度/预计剩余时间)。 

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**job_id** | **uuid::Uuid** | 任务 id(即 Task.id,异步操作 202 响应中的 jobId) | [required] |

### Return type

[**models::Task**](Task.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_tasks

> models::TaskList list_tasks(instance_id, status, page, page_size)
任务列表(进行中优先 + 最近完成)

进行中(queued/running)任务在前,其余按创建时间倒序。 可选按 instanceId / status 过滤。 

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**instance_id** | Option<**uuid::Uuid**> | 按实例过滤;缺省返回全部 |  |
**status** | Option<[**TaskStatus**](TaskStatus.md)> | 按状态过滤 |  |
**page** | Option<**i32**> | 页码,从 1 开始 |  |[default to 1]
**page_size** | Option<**i32**> |  |  |[default to 20]

### Return type

[**models::TaskList**](TaskList.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

