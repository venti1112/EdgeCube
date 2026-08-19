//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ftp_config.g.dart';

/// FtpConfig
///
/// Properties:
/// * [enabled] 
/// * [port] 
/// * [username] 
/// * [password] 
/// * [rootDir] - 根目录;null 跟随当前选中实例 cwd
@BuiltValue(instantiable: false)
abstract class FtpConfig  {
  @BuiltValueField(wireName: r'enabled')
  bool get enabled;

  @BuiltValueField(wireName: r'port')
  int get port;

  @BuiltValueField(wireName: r'username')
  String get username;

  @BuiltValueField(wireName: r'password')
  String? get password;

  /// 根目录;null 跟随当前选中实例 cwd
  @BuiltValueField(wireName: r'rootDir')
  String? get rootDir;

  @BuiltValueSerializer(custom: true)
  static Serializer<FtpConfig> get serializer => _$FtpConfigSerializer();
}

class _$FtpConfigSerializer implements PrimitiveSerializer<FtpConfig> {
  @override
  final Iterable<Type> types = const [FtpConfig];

  @override
  final String wireName = r'FtpConfig';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    FtpConfig object, {
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
    FtpConfig object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  @override
  FtpConfig deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return serializers.deserialize(serialized, specifiedType: FullType($FtpConfig)) as $FtpConfig;
  }
}

/// a concrete implementation of [FtpConfig], since [FtpConfig] is not instantiable
@BuiltValue(instantiable: true)
abstract class $FtpConfig implements FtpConfig, Built<$FtpConfig, $FtpConfigBuilder> {
  $FtpConfig._();

  factory $FtpConfig([void Function($FtpConfigBuilder)? updates]) = _$$FtpConfig;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults($FtpConfigBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<$FtpConfig> get serializer => _$$FtpConfigSerializer();
}

class _$$FtpConfigSerializer implements PrimitiveSerializer<$FtpConfig> {
  @override
  final Iterable<Type> types = const [$FtpConfig, _$$FtpConfig];

  @override
  final String wireName = r'$FtpConfig';

  @override
  Object serialize(
    Serializers serializers,
    $FtpConfig object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return serializers.serialize(object, specifiedType: FullType(FtpConfig))!;
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required FtpConfigBuilder result,
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
  $FtpConfig deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = $FtpConfigBuilder();
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

