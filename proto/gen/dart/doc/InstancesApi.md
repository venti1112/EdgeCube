# edgecube_api_client.api.InstancesApi

## Load the API package
```dart
import 'package:edgecube_api_client/api.dart';
```

All URIs are relative to *http://127.0.0.1:8760/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**createInstance**](InstancesApi.md#createinstance) | **POST** /instances | 创建实例
[**deleteInstance**](InstancesApi.md#deleteinstance) | **DELETE** /instances/{instanceId} | 删除实例
[**exportInstance**](InstancesApi.md#exportinstance) | **POST** /instances/{instanceId}/export | 导出实例(打包工作目录为归档)
[**getInstance**](InstancesApi.md#getinstance) | **GET** /instances/{instanceId} | 实例详情(配置 + 运行状态)
[**getInstanceLog**](InstancesApi.md#getinstancelog) | **GET** /instances/{instanceId}/log | 增量日志拉取(重连回放)
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


# **createInstance**
> InstanceConfig createInstance(instanceConfig)

创建实例

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

# **exportInstance**
> JobAccepted exportInstance(instanceId, exportRequest)

导出实例(打包工作目录为归档)

进度经 WS `download/progress` 推送,完成后返回下载地址。

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

运行中实例的以下字段不可变更(需先停止):startCommand、workingDirectory、 type、terminal.pty、inputEncoding、outputEncoding。其余字段热更新。 

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

