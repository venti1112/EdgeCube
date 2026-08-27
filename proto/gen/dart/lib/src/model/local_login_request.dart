//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'local_login_request.g.dart';

/// LocalLoginRequest
///
/// Properties:
/// * [challenge] 
/// * [signature] - lowercase(hex(HMAC-SHA256(localKey, challenge))),localKey 为 daemon 数据目录内 local.key 内容
/// * [deviceName] 
@BuiltValue()
abstract class LocalLoginRequest implements Built<LocalLoginRequest, LocalLoginRequestBuilder> {
  @BuiltValueField(wireName: r'challenge')
  String get challenge;

  /// lowercase(hex(HMAC-SHA256(localKey, challenge))),localKey 为 daemon 数据目录内 local.key 内容
  @BuiltValueField(wireName: r'signature')
  String get signature;

  @BuiltValueField(wireName: r'deviceName')
  String? get deviceName;

  LocalLoginRequest._();

  factory LocalLoginRequest([void updates(LocalLoginRequestBuilder b)]) = _$LocalLoginRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LocalLoginRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<LocalLoginRequest> get serializer => _$LocalLoginRequestSerializer();
}

class _$LocalLoginRequestSerializer implements PrimitiveSerializer<LocalLoginRequest> {
  @override
  final Iterable<Type> types = const [LocalLoginRequest, _$LocalLoginRequest];

  @override
  final String wireName = r'LocalLoginRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    LocalLoginRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'challenge';
    yield serializers.serialize(
      object.challenge,
      specifiedType: const FullType(String),
    );
    yield r'signature';
    yield serializers.serialize(
      object.signature,
      specifiedType: const FullType(String),
    );
    if (object.deviceName != null) {
      yield r'deviceName';
      yield serializers.serialize(
        object.deviceName,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    LocalLoginRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required LocalLoginRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'challenge':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.challenge = valueDes;
          break;
        case r'signature':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.signature = valueDes;
          break;
        case r'deviceName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.deviceName = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  LocalLoginRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LocalLoginRequestBuilder();
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

