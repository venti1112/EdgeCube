# LocalLoginRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**challenge** | **String** |  | 
**signature** | **String** | lowercase(hex(HMAC-SHA256(localKey, challenge))),localKey 为 daemon 数据目录内 local.key 内容 | 
**device_name** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


