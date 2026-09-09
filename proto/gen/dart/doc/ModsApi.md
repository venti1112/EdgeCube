# edgecube_api_client.api.ModsApi

## Load the API package
```dart
import 'package:edgecube_api_client/api.dart';
```

All URIs are relative to *http://127.0.0.1:8760/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**modrinthGameVersions**](ModsApi.md#modrinthgameversions) | **GET** /mods/modrinth/game-versions | 游戏版本列表(筛选数据源,代理)
[**modrinthProjectVersions**](ModsApi.md#modrinthprojectversions) | **GET** /mods/modrinth/project/{projectId}/versions | 项目版本列表(代理)
[**modrinthProjects**](ModsApi.md#modrinthprojects) | **GET** /mods/modrinth/projects | 批量项目信息(图标/标题,代理)
[**modrinthSearch**](ModsApi.md#modrinthsearch) | **GET** /mods/modrinth/search | Modrinth 搜索(代理)
[**modrinthVersionFiles**](ModsApi.md#modrinthversionfiles) | **POST** /mods/modrinth/version-files | 按 SHA1 查版本(更新检查,代理)
[**poggitPlugins**](ModsApi.md#poggitplugins) | **GET** /mods/poggit/plugins | Poggit 全量发布列表(带缓存,代理)


# **modrinthGameVersions**
> BuiltList<String> modrinthGameVersions()

游戏版本列表(筛选数据源,代理)

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getModsApi();

try {
    final response = api.modrinthGameVersions();
    print(response);
} on DioException catch (e) {
    print('Exception when calling ModsApi->modrinthGameVersions: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

**BuiltList&lt;String&gt;**

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **modrinthProjectVersions**
> BuiltList<ModrinthVersion> modrinthProjectVersions(projectId, gameVersion, loader)

项目版本列表(代理)

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getModsApi();
final String projectId = projectId_example; // String | 
final String gameVersion = gameVersion_example; // String | 
final String loader = loader_example; // String | 

try {
    final response = api.modrinthProjectVersions(projectId, gameVersion, loader);
    print(response);
} on DioException catch (e) {
    print('Exception when calling ModsApi->modrinthProjectVersions: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **projectId** | **String**|  | 
 **gameVersion** | **String**|  | [optional] 
 **loader** | **String**|  | [optional] 

### Return type

[**BuiltList&lt;ModrinthVersion&gt;**](ModrinthVersion.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **modrinthProjects**
> BuiltList<ModrinthProject> modrinthProjects(ids)

批量项目信息(图标/标题,代理)

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getModsApi();
final BuiltList<String> ids = ; // BuiltList<String> | 

try {
    final response = api.modrinthProjects(ids);
    print(response);
} on DioException catch (e) {
    print('Exception when calling ModsApi->modrinthProjects: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **ids** | [**BuiltList&lt;String&gt;**](String.md)|  | 

### Return type

[**BuiltList&lt;ModrinthProject&gt;**](ModrinthProject.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **modrinthSearch**
> ModrinthSearchResponse modrinthSearch(query, offset, limit, gameVersion, loader, sort, projectType)

Modrinth 搜索(代理)

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getModsApi();
final String query = query_example; // String | 
final int offset = 789; // int | 
final int limit = 789; // int | 
final String gameVersion = gameVersion_example; // String | 
final String loader = loader_example; // String | 
final String sort = sort_example; // String | 
final String projectType = projectType_example; // String | 

try {
    final response = api.modrinthSearch(query, offset, limit, gameVersion, loader, sort, projectType);
    print(response);
} on DioException catch (e) {
    print('Exception when calling ModsApi->modrinthSearch: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **query** | **String**|  | 
 **offset** | **int**|  | [optional] [default to 0]
 **limit** | **int**|  | [optional] [default to 20]
 **gameVersion** | **String**|  | [optional] 
 **loader** | **String**|  | [optional] 
 **sort** | **String**|  | [optional] [default to 'relevance']
 **projectType** | **String**|  | [optional] [default to 'mod']

### Return type

[**ModrinthSearchResponse**](ModrinthSearchResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **modrinthVersionFiles**
> BuiltMap<String, ModrinthVersion> modrinthVersionFiles(modrinthVersionFilesRequest)

按 SHA1 查版本(更新检查,代理)

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getModsApi();
final ModrinthVersionFilesRequest modrinthVersionFilesRequest = ; // ModrinthVersionFilesRequest | 

try {
    final response = api.modrinthVersionFiles(modrinthVersionFilesRequest);
    print(response);
} on DioException catch (e) {
    print('Exception when calling ModsApi->modrinthVersionFiles: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **modrinthVersionFilesRequest** | [**ModrinthVersionFilesRequest**](ModrinthVersionFilesRequest.md)|  | 

### Return type

[**BuiltMap&lt;String, ModrinthVersion&gt;**](ModrinthVersion.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **poggitPlugins**
> BuiltList<PoggitPlugin> poggitPlugins()

Poggit 全量发布列表(带缓存,代理)

### Example
```dart
import 'package:edgecube_api_client/api.dart';

final api = EdgecubeApiClient().getModsApi();

try {
    final response = api.poggitPlugins();
    print(response);
} on DioException catch (e) {
    print('Exception when calling ModsApi->poggitPlugins: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**BuiltList&lt;PoggitPlugin&gt;**](PoggitPlugin.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

