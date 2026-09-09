# edgecube_api_client.model.InstanceConfig

## Load the model package
```dart
import 'package:edgecube_api_client/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | **String** | 服务端生成 | [optional] 
**name** | **String** |  | 
**startCommand** | **String** | 命令行字符串(支持引号/转义,解析为参数数组 spawn,不经 shell);空串表示尚未配置启动命令 | [optional] [default to '']
**stopCommand** | **String** | 优雅停止命令;^C 表示发送 Ctrl+C | [optional] [default to '^C']
**stopTimeoutSeconds** | **int** | 优雅停止超时,超时升级强杀 | [optional] [default to 600]
**workingDirectory** | **String** | 工作目录(实例 cwd,文件沙箱根);创建/更新时缺省由 daemon 维护为实例专属目录,不随实例删除 | [optional] 
**environment** | **BuiltMap&lt;String, String&gt;** | 额外环境变量 | [optional] 
**inputEncoding** | [**Encoding**](Encoding.md) |  | [optional] 
**outputEncoding** | [**Encoding**](Encoding.md) |  | [optional] 
**autoRestart** | **bool** | 异常/正常退出后自动重启 | [optional] [default to false]
**autoRestartMaxTimes** | **int** | 重启次数上限;-1 无限 | [optional] [default to -1]
**autoStartOnBoot** | **bool** | daemon 启动时自动拉起 | [optional] [default to false]
**terminal** | [**InstanceConfigTerminal**](InstanceConfigTerminal.md) |  | [optional] 
**type** | [**InstanceType**](InstanceType.md) |  | [optional] 
**runtimeId** | **String** | 引用已安装运行时(runtimes 的 RuntimeInfo.id,如 java 指定 JRE 版本)。 为空表示未指定,启动命令中的可执行文件需自行可用。  | [optional] 
**downloadUrl** | **String** | 创建实例时的服务端下载链接(http/https)。仅在创建时生效: daemon 收到后自动发起下载任务(下载到实例工作目录),下载完成前实例暂不可启动。 更新实例时忽略本字段。  | [optional] 
**fileName** | **String** | 下载目标文件名(仅与 downloadUrl 配合,创建时生效)。缺省由 daemon 从 URL 末段推导(如 https://.../paper-1.21.1-198.jar → paper-1.21.1-198.jar); 建议取 /catalog/download-info 返回的 fileName。  | [optional] 
**checksum** | **String** | 下载校验值,格式 \"sha1:<hex>\" 或 \"sha256:<hex>\"(aria2 风格,不填则不做校验)。 仅与 downloadUrl 配合使用,下载完成后按算法强校验,不一致视为失败。  | [optional] 
**downloadTaskId** | **String** | 创建实例触发的下载任务 id(只读)。创建后经 `GET /tasks/{jobId}` 查询下载进度;下载完成后保留,便于追溯。  | [optional] 
**createdAt** | [**DateTime**](DateTime.md) |  | [optional] 
**updatedAt** | [**DateTime**](DateTime.md) |  | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


