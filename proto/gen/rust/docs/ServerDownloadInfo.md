# ServerDownloadInfo

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**url** | **String** | 服务端直链(http/https) | 
**file_name** | **String** | 建议落盘文件名(写入实例工作目录;创建实例时可经 InstanceConfig.fileName 覆盖) | 
**checksum** | Option<**String**> | 校验值,\"sha1:<hex>\" 或 \"sha256:<hex>\"(daemon 下载完成后强校验, 与 InstanceConfig.checksum 同构;无校验值的源返回 null)  | [optional]
**size_bytes** | Option<**i64**> | 可选,源不提供时为 null | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


