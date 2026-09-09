# LocalLoginRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**challenge** | **String** |  | 
**signature** | **String** | lowercase(hex(HMAC-SHA256(localKey, challenge))),localKey 为 daemon 数据目录内 local.key 内容 | 
**device_id** | Option<**uuid::Uuid**> | 同 LoginRequest.deviceId,复用已有设备记录 | [optional]
**device_name** | Option<**String**> |  | [optional]
**device_type** | Option<[**models::DeviceType**](DeviceType.md)> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


