//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'health_response_instances.g.dart';

/// HealthResponseInstances
///
/// Properties:
/// * [running] 
/// * [total] 
@BuiltValue()
abstract class HealthResponseInstances implements Built<HealthResponseInstances, HealthResponseInstancesBuilder> {
  @BuiltValueField(wireName: r'running')
  int? get running;

  @BuiltValueField(wireName: r'total')
  int? get total;

  HealthResponseInstances._();

  factory HealthResponseInstances([void updates(HealthResponseInstancesBuilder b)]) = _$HealthResponseInstances;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(HealthResponseInstancesBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<HealthResponseInstances> get serializer => _$HealthResponseInstancesSerializer();
}

class _$HealthResponseInstancesSerializer implements PrimitiveSerializer<HealthResponseInstances> {
  @override
  final Iterable<Type> types = const [HealthResponseInstances, _$HealthResponseInstances];

  @override
  final String wireName = r'HealthResponseInstances';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    HealthResponseInstances object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.running != null) {
      yield r'running';
      yield serializers.serialize(
        object.running,
        specifiedType: const FullType(int),
      );
    }
    if (object.total != null) {
      yield r'total';
      yield serializers.serialize(
        object.total,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    HealthResponseInstances object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required HealthResponseInstancesBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'running':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.running = valueDes;
          break;
        case r'total':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.total = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  HealthResponseInstances deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = HealthResponseInstancesBuilder();
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

