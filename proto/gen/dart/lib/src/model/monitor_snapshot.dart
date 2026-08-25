//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:edgecube_api_client/src/model/monitor_snapshot_disks_inner.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'monitor_snapshot.g.dart';

/// MonitorSnapshot
///
/// Properties:
/// * [cpuPercent] 
/// * [memoryTotalBytes] 
/// * [memoryUsedBytes] 
/// * [disks] 
/// * [networkRxBytesPerSec] 
/// * [networkTxBytesPerSec] 
/// * [uptimeSeconds] 
@BuiltValue()
abstract class MonitorSnapshot implements Built<MonitorSnapshot, MonitorSnapshotBuilder> {
  @BuiltValueField(wireName: r'cpuPercent')
  double get cpuPercent;

  @BuiltValueField(wireName: r'memoryTotalBytes')
  int get memoryTotalBytes;

  @BuiltValueField(wireName: r'memoryUsedBytes')
  int get memoryUsedBytes;

  @BuiltValueField(wireName: r'disks')
  BuiltList<MonitorSnapshotDisksInner>? get disks;

  @BuiltValueField(wireName: r'networkRxBytesPerSec')
  int? get networkRxBytesPerSec;

  @BuiltValueField(wireName: r'networkTxBytesPerSec')
  int? get networkTxBytesPerSec;

  @BuiltValueField(wireName: r'uptimeSeconds')
  int get uptimeSeconds;

  MonitorSnapshot._();

  factory MonitorSnapshot([void updates(MonitorSnapshotBuilder b)]) = _$MonitorSnapshot;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MonitorSnapshotBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MonitorSnapshot> get serializer => _$MonitorSnapshotSerializer();
}

class _$MonitorSnapshotSerializer implements PrimitiveSerializer<MonitorSnapshot> {
  @override
  final Iterable<Type> types = const [MonitorSnapshot, _$MonitorSnapshot];

  @override
  final String wireName = r'MonitorSnapshot';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MonitorSnapshot object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'cpuPercent';
    yield serializers.serialize(
      object.cpuPercent,
      specifiedType: const FullType(double),
    );
    yield r'memoryTotalBytes';
    yield serializers.serialize(
      object.memoryTotalBytes,
      specifiedType: const FullType(int),
    );
    yield r'memoryUsedBytes';
    yield serializers.serialize(
      object.memoryUsedBytes,
      specifiedType: const FullType(int),
    );
    if (object.disks != null) {
      yield r'disks';
      yield serializers.serialize(
        object.disks,
        specifiedType: const FullType(BuiltList, [FullType(MonitorSnapshotDisksInner)]),
      );
    }
    if (object.networkRxBytesPerSec != null) {
      yield r'networkRxBytesPerSec';
      yield serializers.serialize(
        object.networkRxBytesPerSec,
        specifiedType: const FullType(int),
      );
    }
    if (object.networkTxBytesPerSec != null) {
      yield r'networkTxBytesPerSec';
      yield serializers.serialize(
        object.networkTxBytesPerSec,
        specifiedType: const FullType(int),
      );
    }
    yield r'uptimeSeconds';
    yield serializers.serialize(
      object.uptimeSeconds,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    MonitorSnapshot object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required MonitorSnapshotBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'cpuPercent':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.cpuPercent = valueDes;
          break;
        case r'memoryTotalBytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.memoryTotalBytes = valueDes;
          break;
        case r'memoryUsedBytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.memoryUsedBytes = valueDes;
          break;
        case r'disks':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(MonitorSnapshotDisksInner)]),
          ) as BuiltList<MonitorSnapshotDisksInner>?;
          if (valueDes == null) continue;
          result.disks.replace(valueDes);
          break;
        case r'networkRxBytesPerSec':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.networkRxBytesPerSec = valueDes;
          break;
        case r'networkTxBytesPerSec':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.networkTxBytesPerSec = valueDes;
          break;
        case r'uptimeSeconds':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.uptimeSeconds = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MonitorSnapshot deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MonitorSnapshotBuilder();
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

