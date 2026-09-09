# TunnelProxy

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**name** | **String** | 代理名称(隧道内唯一) | 
**r#type** | [**models::ProxyType**](ProxyType.md) |  | 
**local_ip** | **String** | 本地服务地址(如 127.0.0.1) | 
**local_port** | **i32** |  | 
**remote_port** | Option<**i32**> | tcp/udp 必填;http/https 无需 | [optional]
**custom_domains** | Option<**Vec<String>**> | http/https 必填(至少一个域名);tcp/udp 忽略 | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


