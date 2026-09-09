# edgecube_api_client.model.LocalLoginRequest

## Load the model package
```dart
import 'package:edgecube_api_client/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**challenge** | **String** |  | 
**signature** | **String** | lowercase(hex(HMAC-SHA256(localKey, challenge))),localKey 为 daemon 数据目录内 local.key 内容 | 
**deviceId** | **String** | 同 LoginRequest.deviceId,复用已有设备记录 | [optional] 
**deviceName** | **String** |  | [optional] 
**deviceType** | [**DeviceType**](DeviceType.md) |  | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


