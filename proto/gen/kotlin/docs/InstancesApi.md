# InstancesApi

All URIs are relative to *http://127.0.0.1:8760/api/v1*

| Method | HTTP request | Description |
| ------------- | ------------- | ------------- |
| [**createInstance**](InstancesApi.md#createInstance) | **POST** /instances | 创建实例 |
| [**deleteInstance**](InstancesApi.md#deleteInstance) | **DELETE** /instances/{instanceId} | 删除实例 |
| [**exportInstance**](InstancesApi.md#exportInstance) | **POST** /instances/{instanceId}/export | 导出实例(打包工作目录为归档) |
| [**getInstance**](InstancesApi.md#getInstance) | **GET** /instances/{instanceId} | 实例详情(配置 + 运行状态) |
| [**getInstanceLog**](InstancesApi.md#getInstanceLog) | **GET** /instances/{instanceId}/log | 增量日志拉取(重连回放) |
| [**getInstanceOutputLog**](InstancesApi.md#getInstanceOutputLog) | **GET** /instances/{instanceId}/outputlog | 持久化日志文件内容(完整回放/导出) |
| [**getInstanceProcessConfig**](InstancesApi.md#getInstanceProcessConfig) | **GET** /instances/{instanceId}/process-config | 读取实例配置文件(server.properties 等) |
| [**getInstancesOverview**](InstancesApi.md#getInstancesOverview) | **GET** /instances/overview | 全部实例状态聚合(首页看板) |
| [**killInstance**](InstancesApi.md#killInstance) | **POST** /instances/{instanceId}/kill | 强制结束进程(进程树) |
| [**listInstances**](InstancesApi.md#listInstances) | **GET** /instances | 实例列表(分页) |
| [**restartInstance**](InstancesApi.md#restartInstance) | **POST** /instances/{instanceId}/restart | 重启(停止完成后自动重新启动) |
| [**sendInstanceCommand**](InstancesApi.md#sendInstanceCommand) | **POST** /instances/{instanceId}/command | 程序化发送一行命令(命令框通道) |
| [**startInstance**](InstancesApi.md#startInstance) | **POST** /instances/{instanceId}/start | 启动实例 |
| [**stopInstance**](InstancesApi.md#stopInstance) | **POST** /instances/{instanceId}/stop | 优雅停止(发送 stopCommand,默认 ^C) |
| [**updateInstance**](InstancesApi.md#updateInstance) | **PUT** /instances/{instanceId} | 更新实例配置 |
| [**updateInstanceProcessConfig**](InstancesApi.md#updateInstanceProcessConfig) | **PUT** /instances/{instanceId}/process-config | 写回实例配置文件 |


<a id="createInstance"></a>
# **createInstance**
> InstanceConfig createInstance(instanceConfig)

创建实例

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = InstancesApi()
val instanceConfig : InstanceConfig =  // InstanceConfig | 
try {
    val result : InstanceConfig = apiInstance.createInstance(instanceConfig)
    println(result)
} catch (e: ClientException) {
    println("4xx response calling InstancesApi#createInstance")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling InstancesApi#createInstance")
    e.printStackTrace()
}
```

### Parameters
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **instanceConfig** | [**InstanceConfig**](InstanceConfig.md)|  | |

### Return type

[**InstanceConfig**](InstanceConfig.md)

### Authorization


Configure BearerAuth statically:
```kotlin
ApiClient.accessToken = ""
```

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

<a id="deleteInstance"></a>
# **deleteInstance**
> deleteInstance(instanceId)

删除实例

运行中的实例必须先停止;仅删除配置与进程,不删除工作目录。

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = InstancesApi()
val instanceId : java.util.UUID = 38400000-8cf0-11bd-b23e-10b96e4ef00d // java.util.UUID | 实例 id(uuid)
try {
    apiInstance.deleteInstance(instanceId)
} catch (e: ClientException) {
    println("4xx response calling InstancesApi#deleteInstance")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling InstancesApi#deleteInstance")
    e.printStackTrace()
}
```

### Parameters
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **instanceId** | **java.util.UUID**| 实例 id(uuid) | |

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

<a id="exportInstance"></a>
# **exportInstance**
> JobAccepted exportInstance(instanceId, exportRequest)

导出实例(打包工作目录为归档)

进度经 WS &#x60;download/progress&#x60; 推送,完成后返回下载地址。

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = InstancesApi()
val instanceId : java.util.UUID = 38400000-8cf0-11bd-b23e-10b96e4ef00d // java.util.UUID | 实例 id(uuid)
val exportRequest : ExportRequest =  // ExportRequest | 
try {
    val result : JobAccepted = apiInstance.exportInstance(instanceId, exportRequest)
    println(result)
} catch (e: ClientException) {
    println("4xx response calling InstancesApi#exportInstance")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling InstancesApi#exportInstance")
    e.printStackTrace()
}
```

### Parameters
| **instanceId** | **java.util.UUID**| 实例 id(uuid) | |
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **exportRequest** | [**ExportRequest**](ExportRequest.md)|  | [optional] |

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

<a id="getInstance"></a>
# **getInstance**
> InstanceDetail getInstance(instanceId)

实例详情(配置 + 运行状态)

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = InstancesApi()
val instanceId : java.util.UUID = 38400000-8cf0-11bd-b23e-10b96e4ef00d // java.util.UUID | 实例 id(uuid)
try {
    val result : InstanceDetail = apiInstance.getInstance(instanceId)
    println(result)
} catch (e: ClientException) {
    println("4xx response calling InstancesApi#getInstance")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling InstancesApi#getInstance")
    e.printStackTrace()
}
```

### Parameters
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **instanceId** | **java.util.UUID**| 实例 id(uuid) | |

### Return type

[**InstanceDetail**](InstanceDetail.md)

### Authorization


Configure BearerAuth statically:
```kotlin
ApiClient.accessToken = ""
```

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

<a id="getInstanceLog"></a>
# **getInstanceLog**
> LogResponse getInstanceLog(instanceId, since, limit)

增量日志拉取(重连回放)

&#x60;since&#x60; 为日志行序号(非时间戳),从 0 开始单调递增; 订阅 WS 后实时行由 &#x60;instance/stdout&#x60; 推送,本端点用于断线补拉。 

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = InstancesApi()
val instanceId : java.util.UUID = 38400000-8cf0-11bd-b23e-10b96e4ef00d // java.util.UUID | 实例 id(uuid)
val since : kotlin.Long = 789 // kotlin.Long | 起始行序号(含)
val limit : kotlin.Int = 56 // kotlin.Int | 最大行数
try {
    val result : LogResponse = apiInstance.getInstanceLog(instanceId, since, limit)
    println(result)
} catch (e: ClientException) {
    println("4xx response calling InstancesApi#getInstanceLog")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling InstancesApi#getInstanceLog")
    e.printStackTrace()
}
```

### Parameters
| **instanceId** | **java.util.UUID**| 实例 id(uuid) | |
| **since** | **kotlin.Long**| 起始行序号(含) | [optional] [default to 0L] |
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **limit** | **kotlin.Int**| 最大行数 | [optional] [default to 5000] |

### Return type

[**LogResponse**](LogResponse.md)

### Authorization


Configure BearerAuth statically:
```kotlin
ApiClient.accessToken = ""
```

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

<a id="getInstanceOutputLog"></a>
# **getInstanceOutputLog**
> kotlin.String getInstanceOutputLog(instanceId)

持久化日志文件内容(完整回放/导出)

返回该实例的日志文件全文(512KB 轮换,最大保留最近两卷)。

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = InstancesApi()
val instanceId : java.util.UUID = 38400000-8cf0-11bd-b23e-10b96e4ef00d // java.util.UUID | 实例 id(uuid)
try {
    val result : kotlin.String = apiInstance.getInstanceOutputLog(instanceId)
    println(result)
} catch (e: ClientException) {
    println("4xx response calling InstancesApi#getInstanceOutputLog")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling InstancesApi#getInstanceOutputLog")
    e.printStackTrace()
}
```

### Parameters
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **instanceId** | **java.util.UUID**| 实例 id(uuid) | |

### Return type

**kotlin.String**

### Authorization


Configure BearerAuth statically:
```kotlin
ApiClient.accessToken = ""
```

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: text/plain, application/json

<a id="getInstanceProcessConfig"></a>
# **getInstanceProcessConfig**
> kotlin.collections.Map&lt;kotlin.String, kotlin.String&gt; getInstanceProcessConfig(instanceId, file)

读取实例配置文件(server.properties 等)

按文件名自动选择解析器:properties / yml / json / txt。 大整数以字符串返回避免精度丢失。 

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = InstancesApi()
val instanceId : java.util.UUID = 38400000-8cf0-11bd-b23e-10b96e4ef00d // java.util.UUID | 实例 id(uuid)
val file : kotlin.String = file_example // kotlin.String | 配置文件名,如 server.properties(相对实例 cwd)
try {
    val result : kotlin.collections.Map<kotlin.String, kotlin.String> = apiInstance.getInstanceProcessConfig(instanceId, file)
    println(result)
} catch (e: ClientException) {
    println("4xx response calling InstancesApi#getInstanceProcessConfig")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling InstancesApi#getInstanceProcessConfig")
    e.printStackTrace()
}
```

### Parameters
| **instanceId** | **java.util.UUID**| 实例 id(uuid) | |
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **file** | **kotlin.String**| 配置文件名,如 server.properties(相对实例 cwd) | |

### Return type

**kotlin.collections.Map&lt;kotlin.String, kotlin.String&gt;**

### Authorization


Configure BearerAuth statically:
```kotlin
ApiClient.accessToken = ""
```

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

<a id="getInstancesOverview"></a>
# **getInstancesOverview**
> InstanceOverview getInstancesOverview()

全部实例状态聚合(首页看板)

返回所有实例的概要 + 运行中实例数量,供 UI 首页一次性渲染; 实时变化经 WS &#x60;instance/state&#x60; 事件推送。 

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = InstancesApi()
try {
    val result : InstanceOverview = apiInstance.getInstancesOverview()
    println(result)
} catch (e: ClientException) {
    println("4xx response calling InstancesApi#getInstancesOverview")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling InstancesApi#getInstancesOverview")
    e.printStackTrace()
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**InstanceOverview**](InstanceOverview.md)

### Authorization


Configure BearerAuth statically:
```kotlin
ApiClient.accessToken = ""
```

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

<a id="killInstance"></a>
# **killInstance**
> killInstance(instanceId)

强制结束进程(进程树)

启动后 6 秒内禁止强杀(防误触);跨平台进程树杀死。

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = InstancesApi()
val instanceId : java.util.UUID = 38400000-8cf0-11bd-b23e-10b96e4ef00d // java.util.UUID | 实例 id(uuid)
try {
    apiInstance.killInstance(instanceId)
} catch (e: ClientException) {
    println("4xx response calling InstancesApi#killInstance")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling InstancesApi#killInstance")
    e.printStackTrace()
}
```

### Parameters
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **instanceId** | **java.util.UUID**| 实例 id(uuid) | |

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

<a id="listInstances"></a>
# **listInstances**
> InstancePage listInstances(page, pageSize, keyword)

实例列表(分页)

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = InstancesApi()
val page : kotlin.Int = 56 // kotlin.Int | 页码,从 1 开始
val pageSize : kotlin.Int = 56 // kotlin.Int | 
val keyword : kotlin.String = keyword_example // kotlin.String | 按名称模糊过滤
try {
    val result : InstancePage = apiInstance.listInstances(page, pageSize, keyword)
    println(result)
} catch (e: ClientException) {
    println("4xx response calling InstancesApi#listInstances")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling InstancesApi#listInstances")
    e.printStackTrace()
}
```

### Parameters
| **page** | **kotlin.Int**| 页码,从 1 开始 | [optional] [default to 1] |
| **pageSize** | **kotlin.Int**|  | [optional] [default to 20] |
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **keyword** | **kotlin.String**| 按名称模糊过滤 | [optional] |

### Return type

[**InstancePage**](InstancePage.md)

### Authorization


Configure BearerAuth statically:
```kotlin
ApiClient.accessToken = ""
```

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

<a id="restartInstance"></a>
# **restartInstance**
> restartInstance(instanceId)

重启(停止完成后自动重新启动)

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = InstancesApi()
val instanceId : java.util.UUID = 38400000-8cf0-11bd-b23e-10b96e4ef00d // java.util.UUID | 实例 id(uuid)
try {
    apiInstance.restartInstance(instanceId)
} catch (e: ClientException) {
    println("4xx response calling InstancesApi#restartInstance")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling InstancesApi#restartInstance")
    e.printStackTrace()
}
```

### Parameters
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **instanceId** | **java.util.UUID**| 实例 id(uuid) | |

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

<a id="sendInstanceCommand"></a>
# **sendInstanceCommand**
> sendInstanceCommand(instanceId, commandRequest)

程序化发送一行命令(命令框通道)

结构化命令入口,对应终端协议中的 &#x60;input&#x60; 帧; 按实例配置可被替换为 RCON 等实现(附加层)。 

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = InstancesApi()
val instanceId : java.util.UUID = 38400000-8cf0-11bd-b23e-10b96e4ef00d // java.util.UUID | 实例 id(uuid)
val commandRequest : CommandRequest =  // CommandRequest | 
try {
    apiInstance.sendInstanceCommand(instanceId, commandRequest)
} catch (e: ClientException) {
    println("4xx response calling InstancesApi#sendInstanceCommand")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling InstancesApi#sendInstanceCommand")
    e.printStackTrace()
}
```

### Parameters
| **instanceId** | **java.util.UUID**| 实例 id(uuid) | |
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **commandRequest** | [**CommandRequest**](CommandRequest.md)|  | |

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

<a id="startInstance"></a>
# **startInstance**
> startInstance(instanceId)

启动实例

完整多实例并发:任意数量实例可同时运行,互不干扰。 含首次启动的目录检查、锁与失败兜底 kill。 

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = InstancesApi()
val instanceId : java.util.UUID = 38400000-8cf0-11bd-b23e-10b96e4ef00d // java.util.UUID | 实例 id(uuid)
try {
    apiInstance.startInstance(instanceId)
} catch (e: ClientException) {
    println("4xx response calling InstancesApi#startInstance")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling InstancesApi#startInstance")
    e.printStackTrace()
}
```

### Parameters
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **instanceId** | **java.util.UUID**| 实例 id(uuid) | |

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

<a id="stopInstance"></a>
# **stopInstance**
> stopInstance(instanceId)

优雅停止(发送 stopCommand,默认 ^C)

stopCommand 超时(可配,默认 600s)后自动升级为强杀。

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = InstancesApi()
val instanceId : java.util.UUID = 38400000-8cf0-11bd-b23e-10b96e4ef00d // java.util.UUID | 实例 id(uuid)
try {
    apiInstance.stopInstance(instanceId)
} catch (e: ClientException) {
    println("4xx response calling InstancesApi#stopInstance")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling InstancesApi#stopInstance")
    e.printStackTrace()
}
```

### Parameters
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **instanceId** | **java.util.UUID**| 实例 id(uuid) | |

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

<a id="updateInstance"></a>
# **updateInstance**
> InstanceConfig updateInstance(instanceId, instanceConfig)

更新实例配置

运行中实例的以下字段不可变更(需先停止):startCommand、workingDirectory、 type、terminal.pty、inputEncoding、outputEncoding。其余字段热更新。 

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = InstancesApi()
val instanceId : java.util.UUID = 38400000-8cf0-11bd-b23e-10b96e4ef00d // java.util.UUID | 实例 id(uuid)
val instanceConfig : InstanceConfig =  // InstanceConfig | 
try {
    val result : InstanceConfig = apiInstance.updateInstance(instanceId, instanceConfig)
    println(result)
} catch (e: ClientException) {
    println("4xx response calling InstancesApi#updateInstance")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling InstancesApi#updateInstance")
    e.printStackTrace()
}
```

### Parameters
| **instanceId** | **java.util.UUID**| 实例 id(uuid) | |
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **instanceConfig** | [**InstanceConfig**](InstanceConfig.md)|  | |

### Return type

[**InstanceConfig**](InstanceConfig.md)

### Authorization


Configure BearerAuth statically:
```kotlin
ApiClient.accessToken = ""
```

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

<a id="updateInstanceProcessConfig"></a>
# **updateInstanceProcessConfig**
> updateInstanceProcessConfig(instanceId, file, requestBody)

写回实例配置文件

### Example
```kotlin
// Import classes:
//import com.venti1112.edgecube.api.infrastructure.*
//import com.venti1112.edgecube.api.models.*

val apiInstance = InstancesApi()
val instanceId : java.util.UUID = 38400000-8cf0-11bd-b23e-10b96e4ef00d // java.util.UUID | 实例 id(uuid)
val file : kotlin.String = file_example // kotlin.String | 
val requestBody : kotlin.collections.Map<kotlin.String, kotlin.String> =  // kotlin.collections.Map<kotlin.String, kotlin.String> | 
try {
    apiInstance.updateInstanceProcessConfig(instanceId, file, requestBody)
} catch (e: ClientException) {
    println("4xx response calling InstancesApi#updateInstanceProcessConfig")
    e.printStackTrace()
} catch (e: ServerException) {
    println("5xx response calling InstancesApi#updateInstanceProcessConfig")
    e.printStackTrace()
}
```

### Parameters
| **instanceId** | **java.util.UUID**| 实例 id(uuid) | |
| **file** | **kotlin.String**|  | |
| Name | Type | Description  | Notes |
| ------------- | ------------- | ------------- | ------------- |
| **requestBody** | [**kotlin.collections.Map&lt;kotlin.String, kotlin.String&gt;**](kotlin.String.md)|  | |

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

