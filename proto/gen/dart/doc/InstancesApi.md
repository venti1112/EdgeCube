# edgecube_api_client.api.InstancesApi

## Load the API package
```dart
import 'package:edgecube_api_client/api.dart';
```

All URIs are relative to *http://127.0.0.1:8760/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**analyzeInstanceMods**](InstancesApi.md#analyzeinstancemods) | **POST** /instances/{instanceId}/mods/analyze | 提交插件/模组元数据解析任务
[**clearFinishedModDownloads**](InstancesApi.md#clearfinishedmoddownloads) | **DELETE** /instances/{instanceId}/mods/downloads | 清除该实例已终结的下载任务
[**createInstance**](InstancesApi.md#createinstance) | **POST** /instances | 创建实例
[**deleteInstance**](InstancesApi.md#deleteinstance) | **DELETE** /instances/{instanceId} | 删除实例
[**downloadInstanceMod**](InstancesApi.md#downloadinstancemod) | **POST** /instances/{instanceId}/mods/download | 提交单文件下载任务(模组/插件)
[**exportInstance**](InstancesApi.md#exportinstance) | **POST** /instances/{instanceId}/export | 导出实例(打包工作目录为归档)
[**getInstance**](InstancesApi.md#getinstance) | **GET** /instances/{instanceId} | 实例详情(配置 + 运行状态)
[**getInstanceLog**](InstancesApi.md#getinstancelog) | **GET** /instances/{instanceId}/log | 增量日志拉取(重连回放)
[**getInstanceModsMetadata**](InstancesApi.md#getinstancemodsmetadata) | **GET** /instances/{instanceId}/mods/metadata | 获取插件/模组解析结果列表
[**getInstanceOutputLog**](InstancesApi.md#getinstanceoutputlog) | **GET** /instances/{instanceId}/outputlog | 持久化日志文件内容(完整回放/导出)
[**getInstanceProcessConfig**](InstancesApi.md#getinstanceprocessconfig) | **GET** /instances/{instanceId}/process-config | 读取实例配置文件(server.properties 等)
[**getInstancesOverview**](InstancesApi.md#getinstancesoverview) | **GET** /instances/overview | 全部实例状态聚合(首页看板)
[**killInstance**](InstancesApi.md#killinstance) | **POST** /instances/{instanceId}/kill | 强制结束进程(进程树)
[**listInstances**](InstancesApi.md#listinstances) | **GET** /instances | 实例列表(分页)
[**restartInstance**](InstancesApi.md#restartinstance) | **POST** /instances/{instanceId}/restart | 重启(停止完成后自动重新启动)
[**sendInstanceCommand**](InstancesApi.md#sendinstancecommand) | **POST** /instances/{instanceId}/command | 程序化发送一行命令(命令框通道)
[**startInstance**](InstancesApi.md#startinstance) | **POST** /instances/{instanceId}/start | 启动实例
[**stopInstance**](InstancesApi.md#stopinstance) | **POST** /instances/{instanceId}/stop | 优雅停止(发送 stopCommand,默认 ^C)
[**updateInstance**](InstancesApi.md#updateinstance) | **PUT** /instances/{instanceId} | 更新实例配置
[**updateInstanceProcessConfig**](InstancesApi.md#updateinstanceprocessconfig) | **PUT** /instances/{instanceId}/process-config | 写回实例配置文件


# **analyzeInstanceMods**
> JobAccepted analyzeInstanceMods(instanceId, modsAnalyzeRequest)

提交插件/模组元数据解析任务

扫描指定目录(相对实例 cwd,如 plugins / mods)内所有 .jar/.phar 文件, 在服务端解析元数据并缓存。返回 202 受理(JobAccepted),任务状态经 GET /tasks/{jobId} 轮询,完成后用 GET mods/metadata 拉取结果。 

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getInstancesApi();
final String instanceId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 实例 id(uuid)
final ModsAnalyzeRequest modsAnalyzeRequest = ; // ModsAnalyzeRequest | 

try {
    final response = api.analyzeInstanceMods(instanceId, modsAnalyzeRequest);
    print(response);
} on DioException catch (e) {
    print('Exception when calling InstancesApi->analyzeInstanceMods: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **instanceId** | **String**| 实例 id(uuid) | 
 **modsAnalyzeRequest** | [**ModsAnalyzeRequest**](ModsAnalyzeRequest.md)|  | 

### Return type

[**JobAccepted**](JobAccepted.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **clearFinishedModDownloads**
> ClearFinishedModDownloads200Response clearFinishedModDownloads(instanceId)

清除该实例已终结的下载任务

移除该实例所有已终结(succeeded/failed/cancelled)的 download_single_file 任务(下载队列「清除已完成」)。 进行中(queued/running)任务不受影响。返回清除数量。 

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getInstancesApi();
final String instanceId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 实例 id(uuid)

try {
    final response = api.clearFinishedModDownloads(instanceId);
    print(response);
} on DioException catch (e) {
    print('Exception when calling InstancesApi->clearFinishedModDownloads: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **instanceId** | **String**| 实例 id(uuid) | 

### Return type

[**ClearFinishedModDownloads200Response**](ClearFinishedModDownloads200Response.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **createInstance**
> InstanceConfig createInstance(instanceConfig)

创建实例

仅 name 必填;startCommand 可为空串(空实例),workingDirectory 缺省由 daemon 分配。 重名返回 409。 可选提供 downloadUrl(服务端下载链接) + checksum(校验值):daemon 创建配置后 自动向任务队列提交下载任务并回写 downloadTaskId,此时返回 202(响应体为完整 实例配置,含 downloadTaskId),客户端用 `GET /tasks/{downloadTaskId}` 查询下载 进度;下载完成该任务终结,实例方可启动。 downloadUrl 仅创建时生效;不带 downloadUrl 时同步返回 201 完整配置。 

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getInstancesApi();
final InstanceConfig instanceConfig = ; // InstanceConfig | 

try {
    final response = api.createInstance(instanceConfig);
    print(response);
} on DioException catch (e) {
    print('Exception when calling InstancesApi->createInstance: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **instanceConfig** | [**InstanceConfig**](InstanceConfig.md)|  | 

### Return type

[**InstanceConfig**](InstanceConfig.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **deleteInstance**
> deleteInstance(instanceId)

删除实例

运行中的实例必须先停止;仅删除配置与进程,不删除工作目录。

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getInstancesApi();
final String instanceId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 实例 id(uuid)

try {
    api.deleteInstance(instanceId);
} on DioException catch (e) {
    print('Exception when calling InstancesApi->deleteInstance: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **instanceId** | **String**| 实例 id(uuid) | 

### Return type

void (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **downloadInstanceMod**
> JobAccepted downloadInstanceMod(instanceId, modDownloadRequest)

提交单文件下载任务(模组/插件)

通用单文件下载:下载 `url` 到实例 cwd 下 `destPath` 目录(文件名取 `fileName`,缺省取 URL 末段)。已存在的同名文件直接覆盖。可选 `replacePath` 指定更新替换的旧文件,下载成功后将其重命名为 `<replacePath>.disabled`(禁用旧版而非删除)。返回 202 受理 (JobAccepted),任务按 instanceId 分组 FIFO 串行(多个下载排队执行), 进度/状态经 GET /tasks/{jobId} 轮询,可 DELETE /tasks/{jobId} 取消。 

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getInstancesApi();
final String instanceId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 实例 id(uuid)
final ModDownloadRequest modDownloadRequest = ; // ModDownloadRequest | 

try {
    final response = api.downloadInstanceMod(instanceId, modDownloadRequest);
    print(response);
} on DioException catch (e) {
    print('Exception when calling InstancesApi->downloadInstanceMod: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **instanceId** | **String**| 实例 id(uuid) | 
 **modDownloadRequest** | [**ModDownloadRequest**](ModDownloadRequest.md)|  | 

### Return type

[**JobAccepted**](JobAccepted.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **exportInstance**
> JobAccepted exportInstance(instanceId, exportRequest)

导出实例(打包工作目录为归档)

将实例配置与工作目录打包为归档(zip/tar.gz,可排除 logs 目录),存入 daemon 的 `exports` 目录。返回 202 受理(JobAccepted),任务完成 (GET /tasks/{jobId} = succeeded)后经 GET /instances/{instanceId}/export/download 下载归档。导出期间实例必须处于 Stopped(运行中返回 409 instance_busy)。 同一实例的导出任务串行,进行中的导出重复提交返回 409 task_conflict。 

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getInstancesApi();
final String instanceId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 实例 id(uuid)
final ExportRequest exportRequest = ; // ExportRequest | 

try {
    final response = api.exportInstance(instanceId, exportRequest);
    print(response);
} on DioException catch (e) {
    print('Exception when calling InstancesApi->exportInstance: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **instanceId** | **String**| 实例 id(uuid) | 
 **exportRequest** | [**ExportRequest**](ExportRequest.md)|  | [optional] 

### Return type

[**JobAccepted**](JobAccepted.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getInstance**
> InstanceDetail getInstance(instanceId)

实例详情(配置 + 运行状态)

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getInstancesApi();
final String instanceId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 实例 id(uuid)

try {
    final response = api.getInstance(instanceId);
    print(response);
} on DioException catch (e) {
    print('Exception when calling InstancesApi->getInstance: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **instanceId** | **String**| 实例 id(uuid) | 

### Return type

[**InstanceDetail**](InstanceDetail.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getInstanceLog**
> LogResponse getInstanceLog(instanceId, since, limit)

增量日志拉取(重连回放)

`since` 为日志行序号(非时间戳),从 0 开始单调递增; 订阅 WS 后实时行由 `instance/stdout` 推送,本端点用于断线补拉。 

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getInstancesApi();
final String instanceId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 实例 id(uuid)
final int since = 789; // int | 起始行序号(含)
final int limit = 56; // int | 最大行数

try {
    final response = api.getInstanceLog(instanceId, since, limit);
    print(response);
} on DioException catch (e) {
    print('Exception when calling InstancesApi->getInstanceLog: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **instanceId** | **String**| 实例 id(uuid) | 
 **since** | **int**| 起始行序号(含) | [optional] [default to 0]
 **limit** | **int**| 最大行数 | [optional] [default to 5000]

### Return type

[**LogResponse**](LogResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getInstanceModsMetadata**
> ModMetadataListResponse getInstanceModsMetadata(instanceId, path)

获取插件/模组解析结果列表

列出指定目录(相对实例 cwd)内插件/模组文件的解析结果; 未识别或尚未解析的文件 metadata 为 null。 

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getInstancesApi();
final String instanceId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 实例 id(uuid)
final String path = path_example; // String | 相对实例 cwd 的目录,如 plugins / mods

try {
    final response = api.getInstanceModsMetadata(instanceId, path);
    print(response);
} on DioException catch (e) {
    print('Exception when calling InstancesApi->getInstanceModsMetadata: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **instanceId** | **String**| 实例 id(uuid) | 
 **path** | **String**| 相对实例 cwd 的目录,如 plugins / mods | 

### Return type

[**ModMetadataListResponse**](ModMetadataListResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getInstanceOutputLog**
> String getInstanceOutputLog(instanceId)

持久化日志文件内容(完整回放/导出)

返回该实例的日志文件全文(512KB 轮换,最大保留最近两卷)。

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getInstancesApi();
final String instanceId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 实例 id(uuid)

try {
    final response = api.getInstanceOutputLog(instanceId);
    print(response);
} on DioException catch (e) {
    print('Exception when calling InstancesApi->getInstanceOutputLog: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **instanceId** | **String**| 实例 id(uuid) | 

### Return type

**String**

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: text/plain, application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getInstanceProcessConfig**
> BuiltMap<String, String> getInstanceProcessConfig(instanceId, file)

读取实例配置文件(server.properties 等)

按文件名自动选择解析器:properties / yml / json / txt。 大整数以字符串返回避免精度丢失。 

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getInstancesApi();
final String instanceId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 实例 id(uuid)
final String file = file_example; // String | 配置文件名,如 server.properties(相对实例 cwd)

try {
    final response = api.getInstanceProcessConfig(instanceId, file);
    print(response);
} on DioException catch (e) {
    print('Exception when calling InstancesApi->getInstanceProcessConfig: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **instanceId** | **String**| 实例 id(uuid) | 
 **file** | **String**| 配置文件名,如 server.properties(相对实例 cwd) | 

### Return type

**BuiltMap&lt;String, String&gt;**

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getInstancesOverview**
> InstanceOverview getInstancesOverview()

全部实例状态聚合(首页看板)

返回所有实例的概要 + 运行中实例数量,供 UI 首页一次性渲染; 实时变化经 WS `instance/state` 事件推送。 

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getInstancesApi();

try {
    final response = api.getInstancesOverview();
    print(response);
} on DioException catch (e) {
    print('Exception when calling InstancesApi->getInstancesOverview: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**InstanceOverview**](InstanceOverview.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **killInstance**
> killInstance(instanceId)

强制结束进程(进程树)

启动后 6 秒内禁止强杀(防误触);跨平台进程树杀死。

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getInstancesApi();
final String instanceId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 实例 id(uuid)

try {
    api.killInstance(instanceId);
} on DioException catch (e) {
    print('Exception when calling InstancesApi->killInstance: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **instanceId** | **String**| 实例 id(uuid) | 

### Return type

void (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **listInstances**
> InstancePage listInstances(page, pageSize, keyword)

实例列表(分页)

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getInstancesApi();
final int page = 56; // int | 页码,从 1 开始
final int pageSize = 56; // int | 
final String keyword = keyword_example; // String | 按名称模糊过滤

try {
    final response = api.listInstances(page, pageSize, keyword);
    print(response);
} on DioException catch (e) {
    print('Exception when calling InstancesApi->listInstances: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **page** | **int**| 页码,从 1 开始 | [optional] [default to 1]
 **pageSize** | **int**|  | [optional] [default to 20]
 **keyword** | **String**| 按名称模糊过滤 | [optional] 

### Return type

[**InstancePage**](InstancePage.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **restartInstance**
> restartInstance(instanceId)

重启(停止完成后自动重新启动)

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getInstancesApi();
final String instanceId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 实例 id(uuid)

try {
    api.restartInstance(instanceId);
} on DioException catch (e) {
    print('Exception when calling InstancesApi->restartInstance: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **instanceId** | **String**| 实例 id(uuid) | 

### Return type

void (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **sendInstanceCommand**
> sendInstanceCommand(instanceId, commandRequest)

程序化发送一行命令(命令框通道)

结构化命令入口,对应终端协议中的 `input` 帧; 按实例配置可被替换为 RCON 等实现(附加层)。 

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getInstancesApi();
final String instanceId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 实例 id(uuid)
final CommandRequest commandRequest = ; // CommandRequest | 

try {
    api.sendInstanceCommand(instanceId, commandRequest);
} on DioException catch (e) {
    print('Exception when calling InstancesApi->sendInstanceCommand: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **instanceId** | **String**| 实例 id(uuid) | 
 **commandRequest** | [**CommandRequest**](CommandRequest.md)|  | 

### Return type

void (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **startInstance**
> startInstance(instanceId)

启动实例

完整多实例并发:任意数量实例可同时运行,互不干扰。 含首次启动的目录检查、锁与失败兜底 kill。 

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getInstancesApi();
final String instanceId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 实例 id(uuid)

try {
    api.startInstance(instanceId);
} on DioException catch (e) {
    print('Exception when calling InstancesApi->startInstance: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **instanceId** | **String**| 实例 id(uuid) | 

### Return type

void (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **stopInstance**
> stopInstance(instanceId)

优雅停止(发送 stopCommand,默认 ^C)

stopCommand 超时(可配,默认 600s)后自动升级为强杀。

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getInstancesApi();
final String instanceId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 实例 id(uuid)

try {
    api.stopInstance(instanceId);
} on DioException catch (e) {
    print('Exception when calling InstancesApi->stopInstance: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **instanceId** | **String**| 实例 id(uuid) | 

### Return type

void (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **updateInstance**
> InstanceConfig updateInstance(instanceId, instanceConfig)

更新实例配置

运行中实例的以下字段不可变更(需先停止):startCommand、workingDirectory、 type、runtimeId、terminal.pty、inputEncoding、outputEncoding。其余字段热更新。 

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getInstancesApi();
final String instanceId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 实例 id(uuid)
final InstanceConfig instanceConfig = ; // InstanceConfig | 

try {
    final response = api.updateInstance(instanceId, instanceConfig);
    print(response);
} on DioException catch (e) {
    print('Exception when calling InstancesApi->updateInstance: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **instanceId** | **String**| 实例 id(uuid) | 
 **instanceConfig** | [**InstanceConfig**](InstanceConfig.md)|  | 

### Return type

[**InstanceConfig**](InstanceConfig.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **updateInstanceProcessConfig**
> updateInstanceProcessConfig(instanceId, file, requestBody)

写回实例配置文件

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getInstancesApi();
final String instanceId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 实例 id(uuid)
final String file = file_example; // String | 
final BuiltMap<String, String> requestBody = ; // BuiltMap<String, String> | 

try {
    api.updateInstanceProcessConfig(instanceId, file, requestBody);
} on DioException catch (e) {
    print('Exception when calling InstancesApi->updateInstanceProcessConfig: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **instanceId** | **String**| 实例 id(uuid) | 
 **file** | **String**|  | 
 **requestBody** | [**BuiltMap&lt;String, String&gt;**](String.md)|  | 

### Return type

void (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

