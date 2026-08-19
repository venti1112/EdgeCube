
# BackupTarget

## Properties
| Name | Type | Description | Notes |
| ------------ | ------------- | ------------- | ------------- |
| **id** | **kotlin.String** |  |  |
| **name** | **kotlin.String** |  |  |
| **type** | [**BackupTargetType**](BackupTargetType.md) |  |  |
| **path** | **kotlin.String** | 目标目录(local 为绝对路径;ftp/sftp 为远端路径) |  |
| **host** | **kotlin.String** |  |  [optional] |
| **port** | **kotlin.Int** |  |  [optional] |
| **username** | **kotlin.String** |  |  [optional] |
| **encryptedPassword** | **kotlin.String** | 可选;设置后服务端加密存储 |  [optional] |
| **createdAt** | [**java.time.OffsetDateTime**](java.time.OffsetDateTime.md) |  |  [optional] [readonly] |



