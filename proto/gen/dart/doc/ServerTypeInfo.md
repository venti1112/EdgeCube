# edgecube_api_client.model.ServerTypeInfo

## Load the model package
```dart
import 'package:edgecube_api_client/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**type** | **String** | 类型 id,如 vanilla / paper / spigot / craftbukkit / purpur / leaf / leaves / velocity / bungeecord / fabric / pocketmine / powernukkitx / allay | 
**category** | **String** |  | 
**hasLoader** | **bool** | true 时版本页选择 MC 版本后需经 /catalog/loaders 选加载器版本(目前仅 fabric) | [optional] [default to false]
**fileName** | **String** | 该类型默认落盘文件名(如 server.jar / bungeecord.jar / PocketMine-MP.phar);下载信息可覆盖 | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


