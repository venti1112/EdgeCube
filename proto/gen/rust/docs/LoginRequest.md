# LoginRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**username** | **String** |  | 
**password** | **String** |  | 
**device_id** | Option<**uuid::Uuid**> | 客户端持久化的设备标识(uuid)。存在该设备记录时复用并轮换 token, 不会产生新设备;缺省时新建设备记录。  | [optional]
**device_name** | Option<**String**> | 设备显示名(如 \"我的手机\" / \"办公室电脑\") | [optional]
**device_type** | Option<[**models::DeviceType**](DeviceType.md)> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


