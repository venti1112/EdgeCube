//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'pair_response.g.dart';

/// PairResponse
///
/// Properties:
/// * [token] - 长期 token(客户端存 secure storage)
/// * [deviceId] 
@BuiltValue()
abstract class PairResponse implements Built<PairResponse, PairResponseBuilder> {
  /// 长期 token(客户端存 secure storage)
  @BuiltValueField(wireName: r'token')
  String get token;

  @BuiltValueField(wireName: r'deviceId')
  String get deviceId;

  PairResponse._();

  factory PairResponse([void updates(PairResponseBuilder b)]) = _$PairResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PairResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PairResponse> get serializer => _$PairResponseSerializer();
}

class _$PairResponseSerializer implements PrimitiveSerializer<PairResponse> {
  @override
  final Iterable<Type> types = const [PairResponse, _$PairResponse];

  @override
  final String wireName = r'PairResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PairResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'token';
    yield serializers.serialize(
      object.token,
      specifiedType: const FullType(String),
    );
    yield r'deviceId';
    yield serializers.serialize(
      object.deviceId,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PairResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PairResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'token':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.token = valueDes;
          break;
        case r'deviceId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.deviceId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PairResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PairResponseBuilder();
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

