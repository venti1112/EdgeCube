# BackupTarget

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | **String** |  | 
**name** | **String** |  | 
**r#type** | [**models::BackupTargetType**](BackupTargetType.md) |  | 
**host** | Option<**String**> |  | [optional]
**port** | Option<**i32**> |  | [optional]
**username** | Option<**String**> |  | [optional]
**path** | **String** | 目标目录(local 为绝对路径;ftp/sftp 为远端路径) | 
**encrypted_password** | Option<**String**> | 可选;设置后服务端加密存储 | [optional]
**created_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional][readonly]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


