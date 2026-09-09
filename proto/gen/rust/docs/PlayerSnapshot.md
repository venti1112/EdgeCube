# PlayerSnapshot

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**instance_status** | [**models::InstanceStatus**](InstanceStatus.md) |  | 
**online** | **Vec<String>** | 在线玩家名(daemon 解析控制台输出维护,按名排序) | 
**whitelist** | [**Vec<models::PlayerNamedEntry>**](PlayerNamedEntry.md) |  | 
**ops** | [**Vec<models::PlayerNamedEntry>**](PlayerNamedEntry.md) |  | 
**bans** | [**Vec<models::PlayerBanEntry>**](PlayerBanEntry.md) |  | 
**ban_ips** | [**Vec<models::PlayerIpBanEntry>**](PlayerIpBanEntry.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


