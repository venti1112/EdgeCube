//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

import 'dart:async';

import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';

import 'package:built_collection/built_collection.dart';
import 'package:edgecube_api_client/src/api_util.dart';
import 'package:edgecube_api_client/src/model/error_response.dart';
import 'package:edgecube_api_client/src/model/server_download_info.dart';
import 'package:edgecube_api_client/src/model/server_type_info.dart';
import 'package:edgecube_api_client/src/model/server_version.dart';

class CatalogApi {

  final Dio _dio;

  final Serializers _serializers;

  const CatalogApi(this._dio, this._serializers);

  /// 服务端下载信息(直链 + 校验值 + 落盘文件名)
  /// 按选择组装修订下载信息(URL、可选校验值、建议文件名)。 - 简单类型:type + version - hasLoader 类型(如 fabric):type + mcVersion + loaderVersion,   组装 meta.fabricmc.net 的 server/jar 直链 - bungeecord:只传 type,取最新构建直链 校验值格式 \&quot;sha1:&lt;hex&gt;\&quot; 或 \&quot;sha256:&lt;hex&gt;\&quot;,与创建实例时 InstanceConfig.checksum 同构(daemon 下载完成后强校验)。 
  ///
  /// Parameters:
  /// * [type] 
  /// * [version] - 简单类型版本号(hasLoader 类型为 mcVersion 别名,可省略)
  /// * [mcVersion] - Minecraft 版本号(hasLoader 类型必填)
  /// * [loaderVersion] - 加载器版本(hasLoader 类型必填)
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [ServerDownloadInfo] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<ServerDownloadInfo>> getCatalogDownloadInfo({ 
    required String type,
    String? version,
    String? mcVersion,
    String? loaderVersion,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/catalog/download-info';
    final _options = Options(
      method: r'GET',
      headers: <String, dynamic>{
        ...?headers,
      },
      extra: <String, dynamic>{
        'secure': <Map<String, String>>[
          {
            'type': 'http',
            'scheme': 'bearer',
            'name': 'BearerAuth',
          },
        ],
        ...?extra,
      },
      validateStatus: validateStatus,
    );

    final _queryParameters = <String, dynamic>{
      r'type': encodeQueryParameter(_serializers, type, const FullType(String)),
      if (version != null) r'version': encodeQueryParameter(_serializers, version, const FullType(String)),
      if (mcVersion != null) r'mcVersion': encodeQueryParameter(_serializers, mcVersion, const FullType(String)),
      if (loaderVersion != null) r'loaderVersion': encodeQueryParameter(_serializers, loaderVersion, const FullType(String)),
    };

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      queryParameters: _queryParameters,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    ServerDownloadInfo? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(ServerDownloadInfo),
      ) as ServerDownloadInfo;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<ServerDownloadInfo>(
      data: _responseData,
      headers: _response.headers,
      isRedirect: _response.isRedirect,
      requestOptions: _response.requestOptions,
      redirects: _response.redirects,
      statusCode: _response.statusCode,
      statusMessage: _response.statusMessage,
      extra: _response.extra,
    );
  }

  /// 加载器版本列表(hasLoader 类型独有)
  /// 返回指定 Minecraft 版本的可用加载器版本(降序)。 目前仅 fabric 为 hasLoader 类型,数据源 meta.fabricmc.net。 
  ///
  /// Parameters:
  /// * [type] - 服务端类型(hasLoader=true 者,如 fabric)
  /// * [mcVersion] - Minecraft 版本号(来自 /catalog/versions)
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [BuiltList<String>] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<BuiltList<String>>> listCatalogLoaders({ 
    required String type,
    required String mcVersion,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/catalog/loaders';
    final _options = Options(
      method: r'GET',
      headers: <String, dynamic>{
        ...?headers,
      },
      extra: <String, dynamic>{
        'secure': <Map<String, String>>[
          {
            'type': 'http',
            'scheme': 'bearer',
            'name': 'BearerAuth',
          },
        ],
        ...?extra,
      },
      validateStatus: validateStatus,
    );

    final _queryParameters = <String, dynamic>{
      r'type': encodeQueryParameter(_serializers, type, const FullType(String)),
      r'mcVersion': encodeQueryParameter(_serializers, mcVersion, const FullType(String)),
    };

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      queryParameters: _queryParameters,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    BuiltList<String>? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      ) as BuiltList<String>;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<BuiltList<String>>(
      data: _responseData,
      headers: _response.headers,
      isRedirect: _response.isRedirect,
      requestOptions: _response.requestOptions,
      redirects: _response.redirects,
      statusCode: _response.statusCode,
      statusMessage: _response.statusMessage,
      extra: _response.extra,
    );
  }

  /// 版本列表(按服务端类型)
  /// 返回该类型可选版本号(降序,最新在前)。 - hasLoader 类型(如 fabric):本体无独立版本 → 返回 Minecraft 版本列表,   加载器版本由 /catalog/loaders 另行查询 - bungeecord:无版本概念,返回空数组 - pocketmine / powernukkitx:版本号附带对应客户端/mcbe 版本,见   ServerVersion 的 meta 字段(可选) 
  ///
  /// Parameters:
  /// * [type] - 服务端类型(见 /catalog/server-types)
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [BuiltList<ServerVersion>] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<BuiltList<ServerVersion>>> listCatalogVersions({ 
    required String type,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/catalog/versions';
    final _options = Options(
      method: r'GET',
      headers: <String, dynamic>{
        ...?headers,
      },
      extra: <String, dynamic>{
        'secure': <Map<String, String>>[
          {
            'type': 'http',
            'scheme': 'bearer',
            'name': 'BearerAuth',
          },
        ],
        ...?extra,
      },
      validateStatus: validateStatus,
    );

    final _queryParameters = <String, dynamic>{
      r'type': encodeQueryParameter(_serializers, type, const FullType(String)),
    };

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      queryParameters: _queryParameters,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    BuiltList<ServerVersion>? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(BuiltList, [FullType(ServerVersion)]),
      ) as BuiltList<ServerVersion>;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<BuiltList<ServerVersion>>(
      data: _responseData,
      headers: _response.headers,
      isRedirect: _response.isRedirect,
      requestOptions: _response.requestOptions,
      redirects: _response.redirects,
      statusCode: _response.statusCode,
      statusMessage: _response.statusMessage,
      extra: _response.extra,
    );
  }

  /// 可用服务端类型列表(分类/是否带加载器/默认文件名)
  /// 静态定义(编译期),随 daemon 发布版本演进。结构: - 分类:vanilla / plugin / mod / proxy / bedrock(与 V1 分类树一致) - type:原版/插件/代理/基岩端直接用;&#39;bungeecord&#39; 无版本选择,直接下载最新构建 - hasLoader:true 时(todo: fabric)需走 /catalog/loaders 选择加载器版本 - fileName:该类型服务端默认落盘文件名(可被 /catalog/download-info 结果覆盖) 
  ///
  /// Parameters:
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [BuiltList<ServerTypeInfo>] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<BuiltList<ServerTypeInfo>>> listServerTypes({ 
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/catalog/server-types';
    final _options = Options(
      method: r'GET',
      headers: <String, dynamic>{
        ...?headers,
      },
      extra: <String, dynamic>{
        'secure': <Map<String, String>>[
          {
            'type': 'http',
            'scheme': 'bearer',
            'name': 'BearerAuth',
          },
        ],
        ...?extra,
      },
      validateStatus: validateStatus,
    );

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    BuiltList<ServerTypeInfo>? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(BuiltList, [FullType(ServerTypeInfo)]),
      ) as BuiltList<ServerTypeInfo>;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<BuiltList<ServerTypeInfo>>(
      data: _responseData,
      headers: _response.headers,
      isRedirect: _response.isRedirect,
      requestOptions: _response.requestOptions,
      redirects: _response.redirects,
      statusCode: _response.statusCode,
      statusMessage: _response.statusMessage,
      extra: _response.extra,
    );
  }

}
