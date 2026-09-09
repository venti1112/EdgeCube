# edgecube_api_client.api.CatalogApi

## Load the API package
```dart
import 'package:edgecube_api_client/api.dart';
```

All URIs are relative to *http://127.0.0.1:8760/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**getCatalogDownloadInfo**](CatalogApi.md#getcatalogdownloadinfo) | **GET** /catalog/download-info | 服务端下载信息(直链 + 校验值 + 落盘文件名)
[**listCatalogLoaders**](CatalogApi.md#listcatalogloaders) | **GET** /catalog/loaders | 加载器版本列表(hasLoader 类型独有)
[**listCatalogVersions**](CatalogApi.md#listcatalogversions) | **GET** /catalog/versions | 版本列表(按服务端类型)
[**listServerTypes**](CatalogApi.md#listservertypes) | **GET** /catalog/server-types | 可用服务端类型列表(分类/是否带加载器/默认文件名)


# **getCatalogDownloadInfo**
> ServerDownloadInfo getCatalogDownloadInfo(type, version, mcVersion, loaderVersion)

服务端下载信息(直链 + 校验值 + 落盘文件名)

按选择组装修订下载信息(URL、可选校验值、建议文件名)。 - 简单类型:type + version - hasLoader 类型(如 fabric):type + mcVersion + loaderVersion,   组装 meta.fabricmc.net 的 server/jar 直链 - bungeecord:只传 type,取最新构建直链 校验值格式 \"sha1:<hex>\" 或 \"sha256:<hex>\",与创建实例时 InstanceConfig.checksum 同构(daemon 下载完成后强校验)。 

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getCatalogApi();
final String type = type_example; // String | 
final String version = version_example; // String | 简单类型版本号(hasLoader 类型为 mcVersion 别名,可省略)
final String mcVersion = mcVersion_example; // String | Minecraft 版本号(hasLoader 类型必填)
final String loaderVersion = loaderVersion_example; // String | 加载器版本(hasLoader 类型必填)

try {
    final response = api.getCatalogDownloadInfo(type, version, mcVersion, loaderVersion);
    print(response);
} on DioException catch (e) {
    print('Exception when calling CatalogApi->getCatalogDownloadInfo: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **type** | **String**|  | 
 **version** | **String**| 简单类型版本号(hasLoader 类型为 mcVersion 别名,可省略) | [optional] 
 **mcVersion** | **String**| Minecraft 版本号(hasLoader 类型必填) | [optional] 
 **loaderVersion** | **String**| 加载器版本(hasLoader 类型必填) | [optional] 

### Return type

[**ServerDownloadInfo**](ServerDownloadInfo.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **listCatalogLoaders**
> BuiltList<String> listCatalogLoaders(type, mcVersion)

加载器版本列表(hasLoader 类型独有)

返回指定 Minecraft 版本的可用加载器版本(降序)。 目前仅 fabric 为 hasLoader 类型,数据源 meta.fabricmc.net。 

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getCatalogApi();
final String type = type_example; // String | 服务端类型(hasLoader=true 者,如 fabric)
final String mcVersion = mcVersion_example; // String | Minecraft 版本号(来自 /catalog/versions)

try {
    final response = api.listCatalogLoaders(type, mcVersion);
    print(response);
} on DioException catch (e) {
    print('Exception when calling CatalogApi->listCatalogLoaders: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **type** | **String**| 服务端类型(hasLoader=true 者,如 fabric) | 
 **mcVersion** | **String**| Minecraft 版本号(来自 /catalog/versions) | 

### Return type

**BuiltList&lt;String&gt;**

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **listCatalogVersions**
> BuiltList<ServerVersion> listCatalogVersions(type)

版本列表(按服务端类型)

返回该类型可选版本号(降序,最新在前)。 - hasLoader 类型(如 fabric):本体无独立版本 → 返回 Minecraft 版本列表,   加载器版本由 /catalog/loaders 另行查询 - bungeecord:无版本概念,返回空数组 - pocketmine / powernukkitx:版本号附带对应客户端/mcbe 版本,见   ServerVersion 的 meta 字段(可选) 

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getCatalogApi();
final String type = type_example; // String | 服务端类型(见 /catalog/server-types)

try {
    final response = api.listCatalogVersions(type);
    print(response);
} on DioException catch (e) {
    print('Exception when calling CatalogApi->listCatalogVersions: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **type** | **String**| 服务端类型(见 /catalog/server-types) | 

### Return type

[**BuiltList&lt;ServerVersion&gt;**](ServerVersion.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **listServerTypes**
> BuiltList<ServerTypeInfo> listServerTypes()

可用服务端类型列表(分类/是否带加载器/默认文件名)

静态定义(编译期),随 daemon 发布版本演进。结构: - 分类:vanilla / plugin / mod / proxy / bedrock(与 V1 分类树一致) - type:原版/插件/代理/基岩端直接用;'bungeecord' 无版本选择,直接下载最新构建 - hasLoader:true 时(todo: fabric)需走 /catalog/loaders 选择加载器版本 - fileName:该类型服务端默认落盘文件名(可被 /catalog/download-info 结果覆盖) 

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getCatalogApi();

try {
    final response = api.listServerTypes();
    print(response);
} on DioException catch (e) {
    print('Exception when calling CatalogApi->listServerTypes: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**BuiltList&lt;ServerTypeInfo&gt;**](ServerTypeInfo.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

