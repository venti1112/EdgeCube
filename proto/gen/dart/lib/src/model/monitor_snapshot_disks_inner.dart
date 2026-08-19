//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'monitor_snapshot_disks_inner.g.dart';

/// MonitorSnapshotDisksInner
///
/// Properties:
/// * [path] 
/// * [totalBytes] 
/// * [usedBytes] 
@BuiltValue()
abstract class MonitorSnapshotDisksInner implements Built<MonitorSnapshotDisksInner, MonitorSnapshotDisksInnerBuilder> {
  @BuiltValueField(wireName: r'path')
  String? get path;

  @BuiltValueField(wireName: r'totalBytes')
  int? get totalBytes;

  @BuiltValueField(wireName: r'usedBytes')
  int? get usedBytes;

  MonitorSnapshotDisksInner._();

  factory MonitorSnapshotDisksInner([void updates(MonitorSnapshotDisksInnerBuilder b)]) = _$MonitorSnapshotDisksInner;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MonitorSnapshotDisksInnerBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MonitorSnapshotDisksInner> get serializer => _$MonitorSnapshotDisksInnerSerializer();
}

class _$MonitorSnapshotDisksInnerSerializer implements PrimitiveSerializer<MonitorSnapshotDisksInner> {
  @override
  final Iterable<Type> types = const [MonitorSnapshotDisksInner, _$MonitorSnapshotDisksInner];

  @override
  final String wireName = r'MonitorSnapshotDisksInner';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MonitorSnapshotDisksInner object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.path != null) {
      yield r'path';
      yield serializers.serialize(
        object.path,
        specifiedType: const FullType(String),
      );
    }
    if (object.totalBytes != null) {
      yield r'totalBytes';
      yield serializers.serialize(
        object.totalBytes,
        specifiedType: const FullType(int),
      );
    }
    if (object.usedBytes != null) {
      yield r'usedBytes';
      yield serializers.serialize(
        object.usedBytes,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    MonitorSnapshotDisksInner object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required MonitorSnapshotDisksInnerBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'path':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.path = valueDes;
          break;
        case r'totalBytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.totalBytes = valueDes;
          break;
        case r'usedBytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.usedBytes = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MonitorSnapshotDisksInner deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MonitorSnapshotDisksInnerBuilder();
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

