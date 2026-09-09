# edgecube_api_client.model.ModDownloadRequest

## Load the model package
```dart
import 'package:edgecube_api_client/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**url** | **String** | 文件下载地址(HTTP/HTTPS) | 
**destPath** | **String** | 目标目录,相对实例 cwd(如 mods / plugins) | 
**fileName** | **String** | 落盘文件名;缺省取 URL 末段 | [optional] 
**displayName** | **String** | 用户可读展示标题(如「模组名 v1.2」),用于任务列表显示 | [optional] 
**replacePath** | **String** | 更新替换:下载成功后把该旧文件(相对实例 cwd)重命名为 `<replacePath>.disabled`(禁用旧版而非删除);文件不存在时静默跳过。  | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


