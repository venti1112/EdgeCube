//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:edgecube_api_client/src/model/ssh_config.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ssh_status.g.dart';

/// SshStatus
///
/// Properties:
/// * [enabled] 
/// * [port] 
/// * [username] 
/// * [password] - 密码登录;留空则仅密钥
/// * [rootDir] 
/// * [running] 
/// * [connections] 
@BuiltValue()
abstract class SshStatus implements SshConfig, Built<SshStatus, SshStatusBuilder> {
  @BuiltValueField(wireName: r'running')
  bool? get running;

  @BuiltValueField(wireName: r'connections')
  int? get connections;

  SshStatus._();

  factory SshStatus([void updates(SshStatusBuilder b)]) = _$SshStatus;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SshStatusBuilder b) => b
      ..port = 2222
      ..connections = 0;

  @BuiltValueSerializer(custom: true)
  static Serializer<SshStatus> get serializer => _$SshStatusSerializer();
}

class _$SshStatusSerializer implements PrimitiveSerializer<SshStatus> {
  @override
  final Iterable<Type> types = const [SshStatus, _$SshStatus];

  @override
  final String wireName = r'SshStatus';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SshStatus object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.running != null) {
      yield r'running';
      yield serializers.serialize(
        object.running,
        specifiedType: const FullType(bool),
      );
    }
    if (object.password != null) {
      yield r'password';
      yield serializers.serialize(
        object.password,
        specifiedType: const FullType(String),
      );
    }
    yield r'port';
    yield serializers.serialize(
      object.port,
      specifiedType: const FullType(int),
    );
    if (object.rootDir != null) {
      yield r'rootDir';
      yield serializers.serialize(
        object.rootDir,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.connections != null) {
      yield r'connections';
      yield serializers.serialize(
        object.connections,
        specifiedType: const FullType(int),
      );
    }
    yield r'enabled';
    yield serializers.serialize(
      object.enabled,
      specifiedType: const FullType(bool),
    );
    yield r'username';
    yield serializers.serialize(
      object.username,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    SshStatus object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SshStatusBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'running':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.running = valueDes;
          break;
        case r'password':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.password = valueDes;
          break;
        case r'port':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.port = valueDes;
          break;
        case r'rootDir':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.rootDir = valueDes;
          break;
        case r'connections':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.connections = valueDes;
          break;
        case r'enabled':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.enabled = valueDes;
          break;
        case r'username':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.username = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SshStatus deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SshStatusBuilder();
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

