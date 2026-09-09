# edgecube_api_client.model.TaskProgress

## Load the model package
```dart
import 'package:edgecube_api_client/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**receivedBytes** | **int** |  | [optional] 
**totalBytes** | **int** |  | [optional] 
**speedBytesPerSec** | **int** | 下载速度(字节/秒) | [optional] 
**etaSeconds** | **int** | 预计还需时间(秒,依据当前速度推算;无法推算时为 null) | [optional] 
**percent** | **double** | 0~1;未知大小(null) | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


