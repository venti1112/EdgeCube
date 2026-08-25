//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:edgecube_api_client/src/model/instance_summary.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'instance_overview.g.dart';

/// InstanceOverview
///
/// Properties:
/// * [items] 
/// * [running] 
/// * [total] 
@BuiltValue()
abstract class InstanceOverview implements Built<InstanceOverview, InstanceOverviewBuilder> {
  @BuiltValueField(wireName: r'items')
  BuiltList<InstanceSummary> get items;

  @BuiltValueField(wireName: r'running')
  int get running;

  @BuiltValueField(wireName: r'total')
  int get total;

  InstanceOverview._();

  factory InstanceOverview([void updates(InstanceOverviewBuilder b)]) = _$InstanceOverview;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(InstanceOverviewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<InstanceOverview> get serializer => _$InstanceOverviewSerializer();
}

class _$InstanceOverviewSerializer implements PrimitiveSerializer<InstanceOverview> {
  @override
  final Iterable<Type> types = const [InstanceOverview, _$InstanceOverview];

  @override
  final String wireName = r'InstanceOverview';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    InstanceOverview object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'items';
    yield serializers.serialize(
      object.items,
      specifiedType: const FullType(BuiltList, [FullType(InstanceSummary)]),
    );
    yield r'running';
    yield serializers.serialize(
      object.running,
      specifiedType: const FullType(int),
    );
    yield r'total';
    yield serializers.serialize(
      object.total,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    InstanceOverview object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required InstanceOverviewBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'items':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(InstanceSummary)]),
          ) as BuiltList<InstanceSummary>;
          result.items.replace(valueDes);
          break;
        case r'running':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.running = valueDes;
          break;
        case r'total':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
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
  InstanceOverview deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = InstanceOverviewBuilder();
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

