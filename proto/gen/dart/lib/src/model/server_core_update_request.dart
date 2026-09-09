//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'server_core_update_request.g.dart';

/// ServerCoreUpdateRequest
///
/// Properties:
/// * [downloadUrl] - 目标核心 jar 下载地址(通常来自 GET core-update/check 的 downloadUrl)
/// * [sha256] - 下载校验值(sha256 hex 或 \"sha1:<hex>\";为空不做校验)
/// * [fileName] - 落盘文件名替换(缺省为检测到的当前核心 jar 名,如 server.jar)
@BuiltValue()
abstract class ServerCoreUpdateRequest implements Built<ServerCoreUpdateRequest, ServerCoreUpdateRequestBuilder> {
  /// 目标核心 jar 下载地址(通常来自 GET core-update/check 的 downloadUrl)
  @BuiltValueField(wireName: r'downloadUrl')
  String get downloadUrl;

  /// 下载校验值(sha256 hex 或 \"sha1:<hex>\";为空不做校验)
  @BuiltValueField(wireName: r'sha256')
  String? get sha256;

  /// 落盘文件名替换(缺省为检测到的当前核心 jar 名,如 server.jar)
  @BuiltValueField(wireName: r'fileName')
  String? get fileName;

  ServerCoreUpdateRequest._();

  factory ServerCoreUpdateRequest([void updates(ServerCoreUpdateRequestBuilder b)]) = _$ServerCoreUpdateRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ServerCoreUpdateRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ServerCoreUpdateRequest> get serializer => _$ServerCoreUpdateRequestSerializer();
}

class _$ServerCoreUpdateRequestSerializer implements PrimitiveSerializer<ServerCoreUpdateRequest> {
  @override
  final Iterable<Type> types = const [ServerCoreUpdateRequest, _$ServerCoreUpdateRequest];

  @override
  final String wireName = r'ServerCoreUpdateRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ServerCoreUpdateRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'downloadUrl';
    yield serializers.serialize(
      object.downloadUrl,
      specifiedType: const FullType(String),
    );
    if (object.sha256 != null) {
      yield r'sha256';
      yield serializers.serialize(
        object.sha256,
        specifiedType: const FullType(String),
      );
    }
    if (object.fileName != null) {
      yield r'fileName';
      yield serializers.serialize(
        object.fileName,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ServerCoreUpdateRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ServerCoreUpdateRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'downloadUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.downloadUrl = valueDes;
          break;
        case r'sha256':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.sha256 = valueDes;
          break;
        case r'fileName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.fileName = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ServerCoreUpdateRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ServerCoreUpdateRequestBuilder();
    final serializedList = (serialized as Iterable<Object?>).toList();
    final unhandled = <Object?>[];
    _deserializeProperties(
      serializers,
      serialized,
      specifiedType: specifiedType,
      serializedList: serializedList,
      unhandled: unhandled,
      result: result,
    );
    return result.build();
  }
}

