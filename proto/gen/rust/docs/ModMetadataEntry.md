# ModMetadataEntry

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**path** | **String** | 相对实例 cwd 的路径 | 
**name** | **String** |  | 
**size_bytes** | **i64** |  | 
**sha1** | Option<**String**> | 文件 SHA1(小写 hex),供更新检查(Modrinth version_files)与图标查询 | [optional]
**icon_url** | Option<**String**> | 图标 URL(后端经 Modrinth 查询,尽力而为;失败/不可得为 null) | [optional]
**metadata** | Option<[**models::ModMetadata**](ModMetadata.md)> | 未识别/未解析时为 null | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


