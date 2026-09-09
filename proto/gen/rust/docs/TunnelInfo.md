# TunnelInfo

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | **uuid::Uuid** |  | 
**name** | **String** |  | 
**server_addr** | **String** | frps 服务端地址(域名/IP) | 
**server_port** | **i32** |  | 
**user** | Option<**String**> | frps 用户名(可选) | [optional]
**auth_token** | Option<**String**> | frps 鉴权 token(可选) | [optional]
**proxies** | [**Vec<models::TunnelProxy>**](TunnelProxy.md) |  | 
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


