//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:edgecube_api_client/src/model/runtime_type.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'runtime_install_request.g.dart';

/// RuntimeInstallRequest
///
/// Properties:
/// * [type] 
/// * [version] - 缺省取 catalog 推荐版本
/// * [arch] - 缺省取当前平台架构
/// * [url] - 覆盖官方源地址(开发者选项)
@BuiltValue()
abstract class RuntimeInstallRequest implements Built<RuntimeInstallRequest, RuntimeInstallRequestBuilder> {
  @BuiltValueField(wireName: r'type')
  RuntimeType get type;
  // enum typeEnum {  java,  php,  frpc,  };

  /// 缺省取 catalog 推荐版本
  @BuiltValueField(wireName: r'version')
  String? get version;

  /// 缺省取当前平台架构
  @BuiltValueField(wireName: r'arch')
  String? get arch;

  /// 覆盖官方源地址(开发者选项)
  @BuiltValueField(wireName: r'url')
  String? get url;

  RuntimeInstallRequest._();

  factory RuntimeInstallRequest([void updates(RuntimeInstallRequestBuilder b)]) = _$RuntimeInstallRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RuntimeInstallRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RuntimeInstallRequest> get serializer => _$RuntimeInstallRequestSerializer();
}

class _$RuntimeInstallRequestSerializer implements PrimitiveSerializer<RuntimeInstallRequest> {
  @override
  final Iterable<Type> types = const [RuntimeInstallRequest, _$RuntimeInstallRequest];

  @override
  final String wireName = r'RuntimeInstallRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RuntimeInstallRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'type';
    yield serializers.serialize(
      object.type,
      specifiedType: const FullType(RuntimeType),
    );
    if (object.version != null) {
      yield r'version';
      yield serializers.serialize(
        object.version,
        specifiedType: const FullType(String),
      );
    }
    if (object.arch != null) {
      yield r'arch';
      yield serializers.serialize(
        object.arch,
        specifiedType: const FullType(String),
      );
    }
    if (object.url != null) {
      yield r'url';
      yield serializers.serialize(
        object.url,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    RuntimeInstallRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RuntimeInstallRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(RuntimeType),
          ) as RuntimeType;
          result.type = valueDes;
          break;
        case r'version':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.version = valueDes;
          break;
        case r'arch':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.arch = valueDes;
          break;
        case r'url':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.url = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RuntimeInstallRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RuntimeInstallRequestBuilder();
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

