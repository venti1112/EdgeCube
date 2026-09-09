# \CatalogApi

All URIs are relative to *http://127.0.0.1:8760/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**get_catalog_download_info**](CatalogApi.md#get_catalog_download_info) | **GET** /catalog/download-info | 服务端下载信息(直链 + 校验值 + 落盘文件名)
[**list_catalog_loaders**](CatalogApi.md#list_catalog_loaders) | **GET** /catalog/loaders | 加载器版本列表(hasLoader 类型独有)
[**list_catalog_versions**](CatalogApi.md#list_catalog_versions) | **GET** /catalog/versions | 版本列表(按服务端类型)
[**list_server_types**](CatalogApi.md#list_server_types) | **GET** /catalog/server-types | 可用服务端类型列表(分类/是否带加载器/默认文件名)



## get_catalog_download_info

> models::ServerDownloadInfo get_catalog_download_info(r#type, version, mc_version, loader_version)
服务端下载信息(直链 + 校验值 + 落盘文件名)

按选择组装修订下载信息(URL、可选校验值、建议文件名)。 - 简单类型:type + version - hasLoader 类型(如 fabric):type + mcVersion + loaderVersion,   组装 meta.fabricmc.net 的 server/jar 直链 - bungeecord:只传 type,取最新构建直链 校验值格式 \"sha1:<hex>\" 或 \"sha256:<hex>\",与创建实例时 InstanceConfig.checksum 同构(daemon 下载完成后强校验)。 

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**r#type** | **String** |  | [required] |
**version** | Option<**String**> | 简单类型版本号(hasLoader 类型为 mcVersion 别名,可省略) |  |
**mc_version** | Option<**String**> | Minecraft 版本号(hasLoader 类型必填) |  |
**loader_version** | Option<**String**> | 加载器版本(hasLoader 类型必填) |  |

### Return type

[**models::ServerDownloadInfo**](ServerDownloadInfo.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_catalog_loaders

> Vec<String> list_catalog_loaders(r#type, mc_version)
加载器版本列表(hasLoader 类型独有)

返回指定 Minecraft 版本的可用加载器版本(降序)。 目前仅 fabric 为 hasLoader 类型,数据源 meta.fabricmc.net。 

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**r#type** | **String** | 服务端类型(hasLoader=true 者,如 fabric) | [required] |
**mc_version** | **String** | Minecraft 版本号(来自 /catalog/versions) | [required] |

### Return type

**Vec<String>**

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_catalog_versions

> Vec<models::ServerVersion> list_catalog_versions(r#type)
版本列表(按服务端类型)

返回该类型可选版本号(降序,最新在前)。 - hasLoader 类型(如 fabric):本体无独立版本 → 返回 Minecraft 版本列表,   加载器版本由 /catalog/loaders 另行查询 - bungeecord:无版本概念,返回空数组 - pocketmine / powernukkitx:版本号附带对应客户端/mcbe 版本,见   ServerVersion 的 meta 字段(可选) 

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**r#type** | **String** | 服务端类型(见 /catalog/server-types) | [required] |

### Return type

[**Vec<models::ServerVersion>**](ServerVersion.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_server_types

> Vec<models::ServerTypeInfo> list_server_types()
可用服务端类型列表(分类/是否带加载器/默认文件名)

静态定义(编译期),随 daemon 发布版本演进。结构: - 分类:vanilla / plugin / mod / proxy / bedrock(与 V1 分类树一致) - type:原版/插件/代理/基岩端直接用;'bungeecord' 无版本选择,直接下载最新构建 - hasLoader:true 时(todo: fabric)需走 /catalog/loaders 选择加载器版本 - fileName:该类型服务端默认落盘文件名(可被 /catalog/download-info 结果覆盖) 

### Parameters

This endpoint does not need any parameter.

### Return type

[**Vec<models::ServerTypeInfo>**](ServerTypeInfo.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

