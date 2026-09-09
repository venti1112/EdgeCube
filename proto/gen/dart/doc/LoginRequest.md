# edgecube_api_client.model.LoginRequest

## Load the model package
```dart
import 'package:edgecube_api_client/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**username** | **String** |  | 
**password** | **String** |  | 
**deviceId** | **String** | 客户端持久化的设备标识(uuid)。存在该设备记录时复用并轮换 token, 不会产生新设备;缺省时新建设备记录。  | [optional] 
**deviceName** | **String** | 设备显示名(如 \"我的手机\" / \"办公室电脑\") | [optional] 
**deviceType** | [**DeviceType**](DeviceType.md) |  | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


