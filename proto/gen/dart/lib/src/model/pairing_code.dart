//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'pairing_code.g.dart';

/// PairingCode
///
/// Properties:
/// * [code] - 6 位对码
/// * [expiresAt] 
@BuiltValue()
abstract class PairingCode implements Built<PairingCode, PairingCodeBuilder> {
  /// 6 位对码
  @BuiltValueField(wireName: r'code')
  String get code;

  @BuiltValueField(wireName: r'expiresAt')
  DateTime get expiresAt;

  PairingCode._();

  factory PairingCode([void updates(PairingCodeBuilder b)]) = _$PairingCode;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PairingCodeBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PairingCode> get serializer => _$PairingCodeSerializer();
}

class _$PairingCodeSerializer implements PrimitiveSerializer<PairingCode> {
  @override
  final Iterable<Type> types = const [PairingCode, _$PairingCode];

  @override
  final String wireName = r'PairingCode';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PairingCode object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'code';
    yield serializers.serialize(
      object.code,
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
    PairingCode object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PairingCodeBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.code = valueDes;
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
  PairingCode deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PairingCodeBuilder();
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

