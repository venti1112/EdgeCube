//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'start_frpc_request.g.dart';

/// StartFrpcRequest
///
/// Properties:
/// * [tunnelId] 
@BuiltValue()
abstract class StartFrpcRequest implements Built<StartFrpcRequest, StartFrpcRequestBuilder> {
  @BuiltValueField(wireName: r'tunnelId')
  String get tunnelId;

  StartFrpcRequest._();

  factory StartFrpcRequest([void updates(StartFrpcRequestBuilder b)]) = _$StartFrpcRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(StartFrpcRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<StartFrpcRequest> get serializer => _$StartFrpcRequestSerializer();
}

class _$StartFrpcRequestSerializer implements PrimitiveSerializer<StartFrpcRequest> {
  @override
  final Iterable<Type> types = const [StartFrpcRequest, _$StartFrpcRequest];

  @override
  final String wireName = r'StartFrpcRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    StartFrpcRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'tunnelId';
    yield serializers.serialize(
      object.tunnelId,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    StartFrpcRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required StartFrpcRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'tunnelId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.tunnelId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  StartFrpcRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = StartFrpcRequestBuilder();
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

