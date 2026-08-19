# UploadInitRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**instance_id** | **String** |  | 
**path** | **String** | 目标目录(相对实例 cwd) | 
**file_name** | **String** |  | 
**size_bytes** | **i64** |  | 
**sha256** | Option<**String**> | 可选,complete 时校验 | [optional]
**auto_extract** | Option<**bool**> | 完成自动解压(服务端整合包场景) | [optional][default to false]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


