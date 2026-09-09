//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

import 'dart:async';

import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';

import 'package:edgecube_api_client/src/api_util.dart';
import 'package:edgecube_api_client/src/model/error_response.dart';
import 'package:edgecube_api_client/src/model/job_accepted.dart';
import 'package:edgecube_api_client/src/model/server_core_update_check.dart';
import 'package:edgecube_api_client/src/model/server_core_update_request.dart';

class ServerCoreApi {

  final Dio _dio;

  final Serializers _serializers;

  const ServerCoreApi(this._dio, this._serializers);

  /// 检查服务端核心是否有新版本(Paper 系)
  /// daemon 代理 PaperMC 官方 API:对 java 实例按其启动命令中的核心 jar (server.jar/paper-*.jar 等)与版本目录推导当前服务端,若为 Paper 系 (Paper/Purpur/Spigot/CraftBukkit 由版本目录识别,识别不了按最新版判断) 则返回最新版本/构建/下载地址与当前版本对比结果。非 java 实例或不支持 更新来源时返回 &#x60;source: unknown / supported: false&#x60;。 
  ///
  /// Parameters:
  /// * [instanceId] - 实例 id(uuid)
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [ServerCoreUpdateCheck] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<ServerCoreUpdateCheck>> checkServerCoreUpdate({ 
    required String instanceId,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/instances/{instanceId}/core-update/check'.replaceAll('{' r'instanceId' '}', encodeQueryParameter(_serializers, instanceId, const FullType(String)).toString());
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

    ServerCoreUpdateCheck? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(ServerCoreUpdateCheck),
      ) as ServerCoreUpdateCheck;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<ServerCoreUpdateCheck>(
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

  /// 更新服务端核心(jar 替换,Paper 系)
  /// 按检查结果下载最新核心 jar 并替换现有 jar(旧 jar 重命名为 &#x60;.disabled&#x60;)。 实例必须处于 Stopped;任务进度经 GET /tasks/{jobId} 轮询,完成后 GET /instances/{instanceId}/core-update/check 的 currentVersion 即更新。 
  ///
  /// Parameters:
  /// * [instanceId] - 实例 id(uuid)
  /// * [serverCoreUpdateRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [JobAccepted] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<JobAccepted>> updateServerCore({ 
    required String instanceId,
    required ServerCoreUpdateRequest serverCoreUpdateRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/instances/{instanceId}/core-update'.replaceAll('{' r'instanceId' '}', encodeQueryParameter(_serializers, instanceId, const FullType(String)).toString());
    final _options = Options(
      method: r'POST',
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
      contentType: 'application/json',
      validateStatus: validateStatus,
    );

    dynamic _bodyData;

    try {
      const _type = FullType(ServerCoreUpdateRequest);
      _bodyData = _serializers.serialize(serverCoreUpdateRequest, specifiedType: _type);

    } catch(error, stackTrace) {
      throw DioException(
         requestOptions: _options.compose(
          _dio.options,
          _path,
        ),
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    final _response = await _dio.request<Object>(
      _path,
      data: _bodyData,
      options: _options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    JobAccepted? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(JobAccepted),
      ) as JobAccepted;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<JobAccepted>(
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
