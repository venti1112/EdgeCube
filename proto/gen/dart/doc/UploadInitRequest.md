# edgecube_api_client.model.UploadInitRequest

## Load the model package
```dart
import 'package:edgecube_api_client/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**instanceId** | **String** |  | 
**path** | **String** | 目标目录(相对实例 cwd) | 
**fileName** | **String** |  | 
**sizeBytes** | **int** |  | 
**sha256** | **String** | 可选,complete 时校验 | [optional] 
**autoExtract** | **bool** | 完成自动解压(服务端整合包场景) | [optional] [default to false]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


