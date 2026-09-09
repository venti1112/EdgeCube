# edgecube_api_client.model.ServerCoreUpdateCheck

## Load the model package
```dart
import 'package:edgecube_api_client/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**supported** | **bool** | 该实例是否支持服务端核心更新(当前仅 Paper 系 java 实例) | 
**source_** | **String** | 检测到的更新源(paper = PaperMC 官方 API) | [optional] 
**currentVersion** | **String** | 当前服务端核心版本(如 1.21.4);未知时为空串 | [optional] 
**currentBuild** | **String** | 当前核心构建号(如 214);未知时为空串 | [optional] 
**latestVersion** | **String** | 最新可用版本(如 1.21.4) | [optional] 
**latestBuild** | **String** | 最新构建号(如 214) | [optional] 
**downloadUrl** | **String** | 最新版核心 jar 下载地址 | [optional] 
**sha256** | **String** | 下载文件 sha256(64 位 hex) | [optional] 
**updateAvailable** | **bool** | 当前是否有可用更新(版本/构建与已装核心不一致) | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


