# edgecube_api_client.model.TunnelProxy

## Load the model package
```dart
import 'package:edgecube_api_client/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**name** | **String** | 代理名称(隧道内唯一) | 
**type** | [**ProxyType**](ProxyType.md) |  | 
**localIp** | **String** | 本地服务地址(如 127.0.0.1) | 
**localPort** | **int** |  | 
**remotePort** | **int** | tcp/udp 必填;http/https 无需 | [optional] 
**customDomains** | **BuiltList&lt;String&gt;** | http/https 必填(至少一个域名);tcp/udp 忽略 | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


