# \InstancesApi

All URIs are relative to *http://127.0.0.1:8760/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**analyze_instance_mods**](InstancesApi.md#analyze_instance_mods) | **POST** /instances/{instanceId}/mods/analyze | 提交插件/模组元数据解析任务
[**clear_finished_mod_downloads**](InstancesApi.md#clear_finished_mod_downloads) | **DELETE** /instances/{instanceId}/mods/downloads | 清除该实例已终结的下载任务
[**create_instance**](InstancesApi.md#create_instance) | **POST** /instances | 创建实例
[**delete_instance**](InstancesApi.md#delete_instance) | **DELETE** /instances/{instanceId} | 删除实例
[**download_instance_mod**](InstancesApi.md#download_instance_mod) | **POST** /instances/{instanceId}/mods/download | 提交单文件下载任务(模组/插件)
[**export_instance**](InstancesApi.md#export_instance) | **POST** /instances/{instanceId}/export | 导出实例(打包工作目录为归档)
[**get_instance**](InstancesApi.md#get_instance) | **GET** /instances/{instanceId} | 实例详情(配置 + 运行状态)
[**get_instance_log**](InstancesApi.md#get_instance_log) | **GET** /instances/{instanceId}/log | 增量日志拉取(重连回放)
[**get_instance_mods_metadata**](InstancesApi.md#get_instance_mods_metadata) | **GET** /instances/{instanceId}/mods/metadata | 获取插件/模组解析结果列表
[**get_instance_output_log**](InstancesApi.md#get_instance_output_log) | **GET** /instances/{instanceId}/outputlog | 持久化日志文件内容(完整回放/导出)
[**get_instance_process_config**](InstancesApi.md#get_instance_process_config) | **GET** /instances/{instanceId}/process-config | 读取实例配置文件(server.properties 等)
[**get_instances_overview**](InstancesApi.md#get_instances_overview) | **GET** /instances/overview | 全部实例状态聚合(首页看板)
[**kill_instance**](InstancesApi.md#kill_instance) | **POST** /instances/{instanceId}/kill | 强制结束进程(进程树)
[**list_instances**](InstancesApi.md#list_instances) | **GET** /instances | 实例列表(分页)
[**restart_instance**](InstancesApi.md#restart_instance) | **POST** /instances/{instanceId}/restart | 重启(停止完成后自动重新启动)
[**send_instance_command**](InstancesApi.md#send_instance_command) | **POST** /instances/{instanceId}/command | 程序化发送一行命令(命令框通道)
[**start_instance**](InstancesApi.md#start_instance) | **POST** /instances/{instanceId}/start | 启动实例
[**stop_instance**](InstancesApi.md#stop_instance) | **POST** /instances/{instanceId}/stop | 优雅停止(发送 stopCommand,默认 ^C)
[**update_instance**](InstancesApi.md#update_instance) | **PUT** /instances/{instanceId} | 更新实例配置
[**update_instance_process_config**](InstancesApi.md#update_instance_process_config) | **PUT** /instances/{instanceId}/process-config | 写回实例配置文件



## analyze_instance_mods

> models::JobAccepted analyze_instance_mods(instance_id, mods_analyze_request)
提交插件/模组元数据解析任务

扫描指定目录(相对实例 cwd,如 plugins / mods)内所有 .jar/.phar 文件, 在服务端解析元数据并缓存。返回 202 受理(JobAccepted),任务状态经 GET /tasks/{jobId} 轮询,完成后用 GET mods/metadata 拉取结果。 

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**instance_id** | **uuid::Uuid** | 实例 id(uuid) | [required] |
**mods_analyze_request** | [**ModsAnalyzeRequest**](ModsAnalyzeRequest.md) |  | [required] |

### Return type

[**models::JobAccepted**](JobAccepted.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## clear_finished_mod_downloads

> models::ClearFinishedModDownloads200Response clear_finished_mod_downloads(instance_id)
清除该实例已终结的下载任务

移除该实例所有已终结(succeeded/failed/cancelled)的 download_single_file 任务(下载队列「清除已完成」)。 进行中(queued/running)任务不受影响。返回清除数量。 

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**instance_id** | **uuid::Uuid** | 实例 id(uuid) | [required] |

### Return type

[**models::ClearFinishedModDownloads200Response**](clearFinishedModDownloads_200_response.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_instance

> models::InstanceConfig create_instance(instance_config)
创建实例

仅 name 必填;startCommand 可为空串(空实例),workingDirectory 缺省由 daemon 分配。 重名返回 409。 可选提供 downloadUrl(服务端下载链接) + checksum(校验值):daemon 创建配置后 自动向任务队列提交下载任务并回写 downloadTaskId,此时返回 202(响应体为完整 实例配置,含 downloadTaskId),客户端用 `GET /tasks/{downloadTaskId}` 查询下载 进度;下载完成该任务终结,实例方可启动。 downloadUrl 仅创建时生效;不带 downloadUrl 时同步返回 201 完整配置。 

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**instance_config** | [**InstanceConfig**](InstanceConfig.md) |  | [required] |

### Return type

[**models::InstanceConfig**](InstanceConfig.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_instance

> delete_instance(instance_id)
删除实例

运行中的实例必须先停止;仅删除配置与进程,不删除工作目录。

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**instance_id** | **uuid::Uuid** | 实例 id(uuid) | [required] |

### Return type

 (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## download_instance_mod

> models::JobAccepted download_instance_mod(instance_id, mod_download_request)
提交单文件下载任务(模组/插件)

通用单文件下载:下载 `url` 到实例 cwd 下 `destPath` 目录(文件名取 `fileName`,缺省取 URL 末段)。已存在的同名文件直接覆盖。可选 `replacePath` 指定更新替换的旧文件,下载成功后将其重命名为 `<replacePath>.disabled`(禁用旧版而非删除)。返回 202 受理 (JobAccepted),任务按 instanceId 分组 FIFO 串行(多个下载排队执行), 进度/状态经 GET /tasks/{jobId} 轮询,可 DELETE /tasks/{jobId} 取消。 

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**instance_id** | **uuid::Uuid** | 实例 id(uuid) | [required] |
**mod_download_request** | [**ModDownloadRequest**](ModDownloadRequest.md) |  | [required] |

### Return type

[**models::JobAccepted**](JobAccepted.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## export_instance

> models::JobAccepted export_instance(instance_id, export_request)
导出实例(打包工作目录为归档)

进度经 WS `task/progress` 推送,完成后返回下载地址。

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**instance_id** | **uuid::Uuid** | 实例 id(uuid) | [required] |
**export_request** | Option<[**ExportRequest**](ExportRequest.md)> |  |  |

### Return type

[**models::JobAccepted**](JobAccepted.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_instance

> models::InstanceDetail get_instance(instance_id)
实例详情(配置 + 运行状态)

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**instance_id** | **uuid::Uuid** | 实例 id(uuid) | [required] |

### Return type

[**models::InstanceDetail**](InstanceDetail.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_instance_log

> models::LogResponse get_instance_log(instance_id, since, limit)
增量日志拉取(重连回放)

`since` 为日志行序号(非时间戳),从 0 开始单调递增; 订阅 WS 后实时行由 `instance/stdout` 推送,本端点用于断线补拉。 

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**instance_id** | **uuid::Uuid** | 实例 id(uuid) | [required] |
**since** | Option<**i64**> | 起始行序号(含) |  |[default to 0]
**limit** | Option<**i32**> | 最大行数 |  |[default to 5000]

### Return type

[**models::LogResponse**](LogResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_instance_mods_metadata

> models::ModMetadataListResponse get_instance_mods_metadata(instance_id, path)
获取插件/模组解析结果列表

列出指定目录(相对实例 cwd)内插件/模组文件的解析结果; 未识别或尚未解析的文件 metadata 为 null。 

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**instance_id** | **uuid::Uuid** | 实例 id(uuid) | [required] |
**path** | **String** | 相对实例 cwd 的目录,如 plugins / mods | [required] |

### Return type

[**models::ModMetadataListResponse**](ModMetadataListResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_instance_output_log

> String get_instance_output_log(instance_id)
持久化日志文件内容(完整回放/导出)

返回该实例的日志文件全文(512KB 轮换,最大保留最近两卷)。

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**instance_id** | **uuid::Uuid** | 实例 id(uuid) | [required] |

### Return type

**String**

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: text/plain, application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_instance_process_config

> std::collections::HashMap<String, String> get_instance_process_config(instance_id, file)
读取实例配置文件(server.properties 等)

按文件名自动选择解析器:properties / yml / json / txt。 大整数以字符串返回避免精度丢失。 

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**instance_id** | **uuid::Uuid** | 实例 id(uuid) | [required] |
**file** | **String** | 配置文件名,如 server.properties(相对实例 cwd) | [required] |

### Return type

**std::collections::HashMap<String, String>**

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_instances_overview

> models::InstanceOverview get_instances_overview()
全部实例状态聚合(首页看板)

返回所有实例的概要 + 运行中实例数量,供 UI 首页一次性渲染; 实时变化经 WS `instance/state` 事件推送。 

### Parameters

This endpoint does not need any parameter.

### Return type

[**models::InstanceOverview**](InstanceOverview.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## kill_instance

> kill_instance(instance_id)
强制结束进程(进程树)

启动后 6 秒内禁止强杀(防误触);跨平台进程树杀死。

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**instance_id** | **uuid::Uuid** | 实例 id(uuid) | [required] |

### Return type

 (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_instances

> models::InstancePage list_instances(page, page_size, keyword)
实例列表(分页)

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**page** | Option<**i32**> | 页码,从 1 开始 |  |[default to 1]
**page_size** | Option<**i32**> |  |  |[default to 20]
**keyword** | Option<**String**> | 按名称模糊过滤 |  |

### Return type

[**models::InstancePage**](InstancePage.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## restart_instance

> restart_instance(instance_id)
重启(停止完成后自动重新启动)

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**instance_id** | **uuid::Uuid** | 实例 id(uuid) | [required] |

### Return type

 (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## send_instance_command

> send_instance_command(instance_id, command_request)
程序化发送一行命令(命令框通道)

结构化命令入口,对应终端协议中的 `input` 帧; 按实例配置可被替换为 RCON 等实现(附加层)。 

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**instance_id** | **uuid::Uuid** | 实例 id(uuid) | [required] |
**command_request** | [**CommandRequest**](CommandRequest.md) |  | [required] |

### Return type

 (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## start_instance

> start_instance(instance_id)
启动实例

完整多实例并发:任意数量实例可同时运行,互不干扰。 含首次启动的目录检查、锁与失败兜底 kill。 

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**instance_id** | **uuid::Uuid** | 实例 id(uuid) | [required] |

### Return type

 (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## stop_instance

> stop_instance(instance_id)
优雅停止(发送 stopCommand,默认 ^C)

stopCommand 超时(可配,默认 600s)后自动升级为强杀。

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**instance_id** | **uuid::Uuid** | 实例 id(uuid) | [required] |

### Return type

 (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## update_instance

> models::InstanceConfig update_instance(instance_id, instance_config)
更新实例配置

运行中实例的以下字段不可变更(需先停止):startCommand、workingDirectory、 type、runtimeId、terminal.pty、inputEncoding、outputEncoding。其余字段热更新。 

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**instance_id** | **uuid::Uuid** | 实例 id(uuid) | [required] |
**instance_config** | [**InstanceConfig**](InstanceConfig.md) |  | [required] |

### Return type

[**models::InstanceConfig**](InstanceConfig.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## update_instance_process_config

> update_instance_process_config(instance_id, file, request_body)
写回实例配置文件

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**instance_id** | **uuid::Uuid** | 实例 id(uuid) | [required] |
**file** | **String** |  | [required] |
**request_body** | [**std::collections::HashMap<String, String>**](String.md) |  | [required] |

### Return type

 (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

