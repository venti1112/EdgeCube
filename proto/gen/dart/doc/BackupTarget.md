# edgecube_api_client.model.BackupTarget

## Load the model package
```dart
import 'package:edgecube_api_client/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | **String** |  | 
**name** | **String** |  | 
**type** | [**BackupTargetType**](BackupTargetType.md) |  | 
**host** | **String** |  | [optional] 
**port** | **int** |  | [optional] 
**username** | **String** |  | [optional] 
**path** | **String** | 目标目录(local 为绝对路径;ftp/sftp 为远端路径) | 
**encryptedPassword** | **String** | 可选;设置后服务端加密存储 | [optional] 
**createdAt** | [**DateTime**](DateTime.md) |  | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


