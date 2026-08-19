# InstanceSummary

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | **uuid::Uuid** |  | 
**name** | **String** |  | 
**status** | [**models::InstanceStatus**](InstanceStatus.md) |  | 
**r#type** | [**models::InstanceType**](InstanceType.md) |  | 
**pid** | Option<**i32**> |  | [optional]
**running_since** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**auto_restart** | Option<**bool**> |  | [optional]
**auto_start_on_boot** | Option<**bool**> |  | [optional]
**port** | Option<**i32**> | 附加层解析出的服务端监听端口 | [optional]
**online_players** | Option<**i32**> | 附加层解析出的在线人数 | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


