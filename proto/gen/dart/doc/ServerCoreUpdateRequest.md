# edgecube_api_client.model.ServerCoreUpdateRequest

## Load the model package
```dart
import 'package:edgecube_api_client/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**downloadUrl** | **String** | 目标核心 jar 下载地址(通常来自 GET core-update/check 的 downloadUrl) | 
**sha256** | **String** | 下载校验值(sha256 hex 或 \"sha1:<hex>\";为空不做校验) | [optional] 
**fileName** | **String** | 落盘文件名替换(缺省为检测到的当前核心 jar 名,如 server.jar) | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


