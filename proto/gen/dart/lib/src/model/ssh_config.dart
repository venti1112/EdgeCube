//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ssh_config.g.dart';

/// SshConfig
///
/// Properties:
/// * [enabled] 
/// * [port] 
/// * [username] 
/// * [password] - 密码登录;留空则仅密钥
/// * [rootDir] 
@BuiltValue(instantiable: false)
abstract class SshConfig  {
  @BuiltValueField(wireName: r'enabled')
  bool get enabled;

  @BuiltValueField(wireName: r'port')
  int get port;

  @BuiltValueField(wireName: r'username')
  String get username;

  /// 密码登录;留空则仅密钥
  @BuiltValueField(wireName: r'password')
  String? get password;

  @BuiltValueField(wireName: r'rootDir')
  String? get rootDir;

  @BuiltValueSerializer(custom: true)
  static Serializer<SshConfig> get serializer => _$SshConfigSerializer();
}

class _$SshConfigSerializer implements PrimitiveSerializer<SshConfig> {
  @override
  final Iterable<Type> types = const [SshConfig];

  @override
  final String wireName = r'SshConfig';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SshConfig object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'enabled';
    yield serializers.serialize(
      object.enabled,
      specifiedType: const FullType(bool),
    );
    yield r'port';
    yield serializers.serialize(
      object.port,
      specifiedType: const FullType(int),
    );
    yield r'username';
    yield serializers.serialize(
      object.username,
      specifiedType: const FullType(String),
    );
    if (object.password != null) {
      yield r'password';
      yield serializers.serialize(
        object.password,
        specifiedType: const FullType(String),
      );
    }
    if (object.rootDir != null) {
      yield r'rootDir';
      yield serializers.serialize(
        object.rootDir,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SshConfig object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  @override
  SshConfig deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return serializers.deserialize(serialized, specifiedType: FullType($SshConfig)) as $SshConfig;
  }
}

/// a concrete implementation of [SshConfig], since [SshConfig] is not instantiable
@BuiltValue(instantiable: true)
abstract class $SshConfig implements SshConfig, Built<$SshConfig, $SshConfigBuilder> {
  $SshConfig._();

  factory $SshConfig([void Function($SshConfigBuilder)? updates]) = _$$SshConfig;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults($SshConfigBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<$SshConfig> get serializer => _$$SshConfigSerializer();
}

class _$$SshConfigSerializer implements PrimitiveSerializer<$SshConfig> {
  @override
  final Iterable<Type> types = const [$SshConfig, _$$SshConfig];

  @override
  final String wireName = r'$SshConfig';

  @override
  Object serialize(
    Serializers serializers,
    $SshConfig object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return serializers.serialize(object, specifiedType: FullType(SshConfig))!;
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SshConfigBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'enabled':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.enabled = valueDes;
          break;
        case r'port':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.port = valueDes;
          break;
        case r'username':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.username = valueDes;
          break;
        case r'password':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.password = valueDes;
          break;
        case r'rootDir':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.rootDir = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  $SshConfig deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = $SshConfigBuilder();
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

