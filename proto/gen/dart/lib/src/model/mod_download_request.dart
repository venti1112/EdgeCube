//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'mod_download_request.g.dart';

/// ModDownloadRequest
///
/// Properties:
/// * [url] - 文件下载地址(HTTP/HTTPS)
/// * [destPath] - 目标目录,相对实例 cwd(如 mods / plugins)
/// * [fileName] - 落盘文件名;缺省取 URL 末段
/// * [displayName] - 用户可读展示标题(如「模组名 v1.2」),用于任务列表显示
/// * [replacePath] - 更新替换:下载成功后把该旧文件(相对实例 cwd)重命名为 `<replacePath>.disabled`(禁用旧版而非删除);文件不存在时静默跳过。 
@BuiltValue()
abstract class ModDownloadRequest implements Built<ModDownloadRequest, ModDownloadRequestBuilder> {
  /// 文件下载地址(HTTP/HTTPS)
  @BuiltValueField(wireName: r'url')
  String get url;

  /// 目标目录,相对实例 cwd(如 mods / plugins)
  @BuiltValueField(wireName: r'destPath')
  String get destPath;

  /// 落盘文件名;缺省取 URL 末段
  @BuiltValueField(wireName: r'fileName')
  String? get fileName;

  /// 用户可读展示标题(如「模组名 v1.2」),用于任务列表显示
  @BuiltValueField(wireName: r'displayName')
  String? get displayName;

  /// 更新替换:下载成功后把该旧文件(相对实例 cwd)重命名为 `<replacePath>.disabled`(禁用旧版而非删除);文件不存在时静默跳过。 
  @BuiltValueField(wireName: r'replacePath')
  String? get replacePath;

  ModDownloadRequest._();

  factory ModDownloadRequest([void updates(ModDownloadRequestBuilder b)]) = _$ModDownloadRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ModDownloadRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ModDownloadRequest> get serializer => _$ModDownloadRequestSerializer();
}

class _$ModDownloadRequestSerializer implements PrimitiveSerializer<ModDownloadRequest> {
  @override
  final Iterable<Type> types = const [ModDownloadRequest, _$ModDownloadRequest];

  @override
  final String wireName = r'ModDownloadRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ModDownloadRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'url';
    yield serializers.serialize(
      object.url,
      specifiedType: const FullType(String),
    );
    yield r'destPath';
    yield serializers.serialize(
      object.destPath,
      specifiedType: const FullType(String),
    );
    if (object.fileName != null) {
      yield r'fileName';
      yield serializers.serialize(
        object.fileName,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.displayName != null) {
      yield r'displayName';
      yield serializers.serialize(
        object.displayName,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.replacePath != null) {
      yield r'replacePath';
      yield serializers.serialize(
        object.replacePath,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ModDownloadRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ModDownloadRequestBuilder result,
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
        case r'destPath':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.destPath = valueDes;
          break;
        case r'fileName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.fileName = valueDes;
          break;
        case r'displayName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.displayName = valueDes;
          break;
        case r'replacePath':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.replacePath = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ModDownloadRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ModDownloadRequestBuilder();
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

