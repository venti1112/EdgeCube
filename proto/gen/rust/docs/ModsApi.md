# \ModsApi

All URIs are relative to *http://127.0.0.1:8760/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**modrinth_game_versions**](ModsApi.md#modrinth_game_versions) | **GET** /mods/modrinth/game-versions | 游戏版本列表(筛选数据源,代理)
[**modrinth_project_versions**](ModsApi.md#modrinth_project_versions) | **GET** /mods/modrinth/project/{projectId}/versions | 项目版本列表(代理)
[**modrinth_projects**](ModsApi.md#modrinth_projects) | **GET** /mods/modrinth/projects | 批量项目信息(图标/标题,代理)
[**modrinth_search**](ModsApi.md#modrinth_search) | **GET** /mods/modrinth/search | Modrinth 搜索(代理)
[**modrinth_version_files**](ModsApi.md#modrinth_version_files) | **POST** /mods/modrinth/version-files | 按 SHA1 查版本(更新检查,代理)
[**poggit_plugins**](ModsApi.md#poggit_plugins) | **GET** /mods/poggit/plugins | Poggit 全量发布列表(带缓存,代理)



## modrinth_game_versions

> Vec<String> modrinth_game_versions()
游戏版本列表(筛选数据源,代理)

### Parameters

This endpoint does not need any parameter.

### Return type

**Vec<String>**

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## modrinth_project_versions

> Vec<models::ModrinthVersion> modrinth_project_versions(project_id, game_version, loader)
项目版本列表(代理)

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**project_id** | **String** |  | [required] |
**game_version** | Option<**String**> |  |  |
**loader** | Option<**String**> |  |  |

### Return type

[**Vec<models::ModrinthVersion>**](ModrinthVersion.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## modrinth_projects

> Vec<models::ModrinthProject> modrinth_projects(ids)
批量项目信息(图标/标题,代理)

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**ids** | [**Vec<String>**](String.md) |  | [required] |

### Return type

[**Vec<models::ModrinthProject>**](ModrinthProject.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## modrinth_search

> models::ModrinthSearchResponse modrinth_search(query, offset, limit, game_version, loader, sort, project_type)
Modrinth 搜索(代理)

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**query** | **String** |  | [required] |
**offset** | Option<**i64**> |  |  |[default to 0]
**limit** | Option<**i64**> |  |  |[default to 20]
**game_version** | Option<**String**> |  |  |
**loader** | Option<**String**> |  |  |
**sort** | Option<**String**> |  |  |[default to relevance]
**project_type** | Option<**String**> |  |  |[default to mod]

### Return type

[**models::ModrinthSearchResponse**](ModrinthSearchResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## modrinth_version_files

> std::collections::HashMap<String, models::ModrinthVersion> modrinth_version_files(modrinth_version_files_request)
按 SHA1 查版本(更新检查,代理)

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**modrinth_version_files_request** | [**ModrinthVersionFilesRequest**](ModrinthVersionFilesRequest.md) |  | [required] |

### Return type

[**std::collections::HashMap<String, models::ModrinthVersion>**](ModrinthVersion.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## poggit_plugins

> Vec<models::PoggitPlugin> poggit_plugins()
Poggit 全量发布列表(带缓存,代理)

### Parameters

This endpoint does not need any parameter.

### Return type

[**Vec<models::PoggitPlugin>**](PoggitPlugin.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

