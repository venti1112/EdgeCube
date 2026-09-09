//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'server_download_info.g.dart';

/// ServerDownloadInfo
///
/// Properties:
/// * [url] - 服务端直链(http/https)
/// * [fileName] - 建议落盘文件名(写入实例工作目录;创建实例时可经 InstanceConfig.fileName 覆盖)
/// * [checksum] - 校验值,\"sha1:<hex>\" 或 \"sha256:<hex>\"(daemon 下载完成后强校验, 与 InstanceConfig.checksum 同构;无校验值的源返回 null) 
/// * [sizeBytes] - 可选,源不提供时为 null
@BuiltValue()
abstract class ServerDownloadInfo implements Built<ServerDownloadInfo, ServerDownloadInfoBuilder> {
  /// 服务端直链(http/https)
  @BuiltValueField(wireName: r'url')
  String get url;

  /// 建议落盘文件名(写入实例工作目录;创建实例时可经 InstanceConfig.fileName 覆盖)
  @BuiltValueField(wireName: r'fileName')
  String get fileName;

  /// 校验值,\"sha1:<hex>\" 或 \"sha256:<hex>\"(daemon 下载完成后强校验, 与 InstanceConfig.checksum 同构;无校验值的源返回 null) 
  @BuiltValueField(wireName: r'checksum')
  String? get checksum;

  /// 可选,源不提供时为 null
  @BuiltValueField(wireName: r'sizeBytes')
  int? get sizeBytes;

  ServerDownloadInfo._();

  factory ServerDownloadInfo([void updates(ServerDownloadInfoBuilder b)]) = _$ServerDownloadInfo;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ServerDownloadInfoBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ServerDownloadInfo> get serializer => _$ServerDownloadInfoSerializer();
}

class _$ServerDownloadInfoSerializer implements PrimitiveSerializer<ServerDownloadInfo> {
  @override
  final Iterable<Type> types = const [ServerDownloadInfo, _$ServerDownloadInfo];

  @override
  final String wireName = r'ServerDownloadInfo';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ServerDownloadInfo object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'url';
    yield serializers.serialize(
      object.url,
      specifiedType: const FullType(String),
    );
    yield r'fileName';
    yield serializers.serialize(
      object.fileName,
      specifiedType: const FullType(String),
    );
    if (object.checksum != null) {
      yield r'checksum';
      yield serializers.serialize(
        object.checksum,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.sizeBytes != null) {
      yield r'sizeBytes';
      yield serializers.serialize(
        object.sizeBytes,
        specifiedType: const FullType.nullable(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ServerDownloadInfo object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ServerDownloadInfoBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'url':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.url = valueDes;
          break;
        case r'fileName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.fileName = valueDes;
          break;
        case r'checksum':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.checksum = valueDes;
          break;
        case r'sizeBytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.sizeBytes = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ServerDownloadInfo deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ServerDownloadInfoBuilder();
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

