//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:edgecube_api_client/src/model/instance_config.dart';
import 'package:edgecube_api_client/src/model/run_status.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'instance_detail.g.dart';

/// InstanceDetail
///
/// Properties:
/// * [config] 
/// * [status] 
@BuiltValue()
abstract class InstanceDetail implements Built<InstanceDetail, InstanceDetailBuilder> {
  @BuiltValueField(wireName: r'config')
  InstanceConfig get config;

  @BuiltValueField(wireName: r'status')
  RunStatus get status;

  InstanceDetail._();

  factory InstanceDetail([void updates(InstanceDetailBuilder b)]) = _$InstanceDetail;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(InstanceDetailBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<InstanceDetail> get serializer => _$InstanceDetailSerializer();
}

class _$InstanceDetailSerializer implements PrimitiveSerializer<InstanceDetail> {
  @override
  final Iterable<Type> types = const [InstanceDetail, _$InstanceDetail];

  @override
  final String wireName = r'InstanceDetail';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    InstanceDetail object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'config';
    yield serializers.serialize(
      object.config,
      specifiedType: const FullType(InstanceConfig),
    );
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(RunStatus),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    InstanceDetail object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required InstanceDetailBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'config':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(InstanceConfig),
          ) as InstanceConfig;
          result.config.replace(valueDes);
          break;
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(RunStatus),
          ) as RunStatus;
          result.status.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  InstanceDetail deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = InstanceDetailBuilder();
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

