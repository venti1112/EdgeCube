# edgecube_api_client.model.InstanceSummary

## Load the model package
```dart
import 'package:edgecube_api_client/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | **String** |  | 
**name** | **String** |  | 
**status** | [**InstanceStatus**](InstanceStatus.md) |  | 
**type** | [**InstanceType**](InstanceType.md) |  | 
**pid** | **int** |  | [optional] 
**runningSince** | [**DateTime**](DateTime.md) |  | [optional] 
**autoRestart** | **bool** |  | [optional] 
**autoStartOnBoot** | **bool** |  | [optional] 
**port** | **int** | 附加层解析出的服务端监听端口 | [optional] 
**onlinePlayers** | **int** | 附加层解析出的在线人数 | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


