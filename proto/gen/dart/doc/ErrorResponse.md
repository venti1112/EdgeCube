# edgecube_api_client.model.ErrorResponse

## Load the model package
```dart
import 'package:edgecube_api_client/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**code** | **String** | 机器可读错误码,如 not_authenticated / invalid_pair_code / instance_busy / not_found | 
**message** | **String** | 人类可读错误信息(daemon 侧为英文,UI 按 code 本地化) | 
**details** | [**BuiltMap&lt;String, JsonObject&gt;**](JsonObject.md) |  | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


