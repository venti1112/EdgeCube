# edgecube_api_client.model.PlayerSnapshot

## Load the model package
```dart
import 'package:edgecube_api_client/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**instanceStatus** | [**InstanceStatus**](InstanceStatus.md) |  | 
**online** | **BuiltList&lt;String&gt;** | 在线玩家名(daemon 解析控制台输出维护,按名排序) | 
**whitelist** | [**BuiltList&lt;PlayerNamedEntry&gt;**](PlayerNamedEntry.md) |  | 
**ops** | [**BuiltList&lt;PlayerNamedEntry&gt;**](PlayerNamedEntry.md) |  | 
**bans** | [**BuiltList&lt;PlayerBanEntry&gt;**](PlayerBanEntry.md) |  | 
**banIps** | [**BuiltList&lt;PlayerIpBanEntry&gt;**](PlayerIpBanEntry.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


