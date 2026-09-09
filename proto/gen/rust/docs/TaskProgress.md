# TaskProgress

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**received_bytes** | Option<**i64**> |  | [optional]
**total_bytes** | Option<**i64**> |  | [optional]
**speed_bytes_per_sec** | Option<**i64**> | 下载速度(字节/秒) | [optional]
**eta_seconds** | Option<**i64**> | 预计还需时间(秒,依据当前速度推算;无法推算时为 null) | [optional]
**percent** | Option<**f32**> | 0~1;未知大小(null) | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


