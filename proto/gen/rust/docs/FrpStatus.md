# FrpStatus

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**running** | **bool** |  | 
**tunnel_id** | Option<**uuid::Uuid**> | 运行中的隧道(未运行时缺省) | [optional]
**started_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> | 本次启动时间(未运行时缺省) | [optional]
**exit_code** | Option<**i32**> | 未运行时的上次退出码(无记录时缺省) | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


