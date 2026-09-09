//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'rename_device_request.g.dart';

/// RenameDeviceRequest
///
/// Properties:
/// * [name] 
@BuiltValue()
abstract class RenameDeviceRequest implements Built<RenameDeviceRequest, RenameDeviceRequestBuilder> {
  @BuiltValueField(wireName: r'name')
  String get name;

  RenameDeviceRequest._();

  factory RenameDeviceRequest([void updates(RenameDeviceRequestBuilder b)]) = _$RenameDeviceRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RenameDeviceRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RenameDeviceRequest> get serializer => _$RenameDeviceRequestSerializer();
}

class _$RenameDeviceRequestSerializer implements PrimitiveSerializer<RenameDeviceRequest> {
  @override
  final Iterable<Type> types = const [RenameDeviceRequest, _$RenameDeviceRequest];

  @override
  final String wireName = r'RenameDeviceRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RenameDeviceRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    RenameDeviceRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RenameDeviceRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RenameDeviceRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RenameDeviceRequestBuilder();
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

