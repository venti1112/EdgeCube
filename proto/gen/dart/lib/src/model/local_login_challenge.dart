//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'local_login_challenge.g.dart';

/// LocalLoginChallenge
///
/// Properties:
/// * [challenge] - 一次性挑战值,5 分钟过期
/// * [expiresAt] 
@BuiltValue()
abstract class LocalLoginChallenge implements Built<LocalLoginChallenge, LocalLoginChallengeBuilder> {
  /// 一次性挑战值,5 分钟过期
  @BuiltValueField(wireName: r'challenge')
  String get challenge;

  @BuiltValueField(wireName: r'expiresAt')
  DateTime get expiresAt;

  LocalLoginChallenge._();

  factory LocalLoginChallenge([void updates(LocalLoginChallengeBuilder b)]) = _$LocalLoginChallenge;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LocalLoginChallengeBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<LocalLoginChallenge> get serializer => _$LocalLoginChallengeSerializer();
}

class _$LocalLoginChallengeSerializer implements PrimitiveSerializer<LocalLoginChallenge> {
  @override
  final Iterable<Type> types = const [LocalLoginChallenge, _$LocalLoginChallenge];

  @override
  final String wireName = r'LocalLoginChallenge';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    LocalLoginChallenge object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'challenge';
    yield serializers.serialize(
      object.challenge,
      specifiedType: const FullType(String),
    );
    yield r'expiresAt';
    yield serializers.serialize(
      object.expiresAt,
      specifiedType: const FullType(DateTime),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    LocalLoginChallenge object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required LocalLoginChallengeBuilder result,
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
        case r'expiresAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.expiresAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  LocalLoginChallenge deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LocalLoginChallengeBuilder();
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

