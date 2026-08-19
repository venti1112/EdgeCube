//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'pair_request.g.dart';

/// PairRequest
///
/// Properties:
/// * [code] 
/// * [deviceName] - 设备显示名(如 \"我的手机\" / \"办公室电脑\")
@BuiltValue()
abstract class PairRequest implements Built<PairRequest, PairRequestBuilder> {
  @BuiltValueField(wireName: r'code')
  String get code;

  /// 设备显示名(如 \"我的手机\" / \"办公室电脑\")
  @BuiltValueField(wireName: r'deviceName')
  String get deviceName;

  PairRequest._();

  factory PairRequest([void updates(PairRequestBuilder b)]) = _$PairRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PairRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PairRequest> get serializer => _$PairRequestSerializer();
}

class _$PairRequestSerializer implements PrimitiveSerializer<PairRequest> {
  @override
  final Iterable<Type> types = const [PairRequest, _$PairRequest];

  @override
  final String wireName = r'PairRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PairRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'code';
    yield serializers.serialize(
      object.code,
      specifiedType: const FullType(String),
    );
    yield r'deviceName';
    yield serializers.serialize(
      object.deviceName,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PairRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PairRequestBuilder result,
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
        case r'deviceName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
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
  PairRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PairRequestBuilder();
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

