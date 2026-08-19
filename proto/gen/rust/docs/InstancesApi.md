# \InstancesApi

All URIs are relative to *http://127.0.0.1:8760/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**create_instance**](InstancesApi.md#create_instance) | **POST** /instances | 创建实例
[**delete_instance**](InstancesApi.md#delete_instance) | **DELETE** /instances/{instanceId} | 删除实例
[**export_instance**](InstancesApi.md#export_instance) | **POST** /instances/{instanceId}/export | 导出实例(打包工作目录为归档)
[**get_instance**](InstancesApi.md#get_instance) | **GET** /instances/{instanceId} | 实例详情(配置 + 运行状态)
[**get_instance_log**](InstancesApi.md#get_instance_log) | **GET** /instances/{instanceId}/log | 增量日志拉取(重连回放)
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



## create_instance

> models::InstanceConfig create_instance(instance_config)
创建实例

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


## export_instance

> models::JobAccepted export_instance(instance_id, export_request)
导出实例(打包工作目录为归档)

进度经 WS `download/progress` 推送,完成后返回下载地址。

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

运行中实例的以下字段不可变更(需先停止):startCommand、workingDirectory、 type、terminal.pty、inputEncoding、outputEncoding。其余字段热更新。 

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

