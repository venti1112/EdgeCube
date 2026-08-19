# BackupJob

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | **String** |  | 
**name** | **String** |  | 
**instance_id** | **String** | 备份哪个实例 | 
**schedule_cron** | Option<**String**> | 定时表达式(如 \"0 4 * * *\");null 为仅手动 | [optional]
**target_ids** | Option<**Vec<String>**> | 备份目标;空为仅本地 | [optional]
**enabled** | Option<**bool**> |  | [optional][default to true]
**max_keep** | Option<**i32**> | 保留最近 N 份 | [optional][default to 10]
**include_dirs** | Option<**Vec<String>**> | 相对 cwd 的附加目录;空为整个工作目录 | [optional]
**last_run_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional][readonly]
**last_result** | Option<**LastResult**> |  (enum: success, failed, running) | [optional][readonly]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


