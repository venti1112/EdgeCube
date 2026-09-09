# Task

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | 任务 id(= JobAccepted.jobId) | 
**kind** | [**models::TaskKind**](TaskKind.md) |  | 
**display_name** | Option<**String**> | 用户可读展示标题(如「模组名 v1.2」,download_single_file 等使用);无时为 null | [optional]
**instance_id** | Option<**uuid::Uuid**> | 关联实例;全局任务(下载运行时等)为 null | [optional]
**status** | [**models::TaskStatus**](TaskStatus.md) |  | 
**phase** | Option<**String**> | 执行阶段描述(如 start 的 launching / 下载的 fetching);无阶段概念时为 null | [optional]
**progress** | Option<[**models::TaskProgress**](TaskProgress.md)> |  | [optional]
**error** | Option<[**models::TaskError**](TaskError.md)> |  | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**started_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**finished_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


