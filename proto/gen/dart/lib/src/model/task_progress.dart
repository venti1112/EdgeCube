//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'task_progress.g.dart';

/// TaskProgress
///
/// Properties:
/// * [receivedBytes] 
/// * [totalBytes] 
/// * [speedBytesPerSec] - 下载速度(字节/秒)
/// * [etaSeconds] - 预计还需时间(秒,依据当前速度推算;无法推算时为 null)
/// * [percent] - 0~1;未知大小(null)
@BuiltValue()
abstract class TaskProgress implements Built<TaskProgress, TaskProgressBuilder> {
  @BuiltValueField(wireName: r'receivedBytes')
  int? get receivedBytes;

  @BuiltValueField(wireName: r'totalBytes')
  int? get totalBytes;

  /// 下载速度(字节/秒)
  @BuiltValueField(wireName: r'speedBytesPerSec')
  int? get speedBytesPerSec;

  /// 预计还需时间(秒,依据当前速度推算;无法推算时为 null)
  @BuiltValueField(wireName: r'etaSeconds')
  int? get etaSeconds;

  /// 0~1;未知大小(null)
  @BuiltValueField(wireName: r'percent')
  double? get percent;

  TaskProgress._();

  factory TaskProgress([void updates(TaskProgressBuilder b)]) = _$TaskProgress;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(TaskProgressBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<TaskProgress> get serializer => _$TaskProgressSerializer();
}

class _$TaskProgressSerializer implements PrimitiveSerializer<TaskProgress> {
  @override
  final Iterable<Type> types = const [TaskProgress, _$TaskProgress];

  @override
  final String wireName = r'TaskProgress';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    TaskProgress object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.receivedBytes != null) {
      yield r'receivedBytes';
      yield serializers.serialize(
        object.receivedBytes,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.totalBytes != null) {
      yield r'totalBytes';
      yield serializers.serialize(
        object.totalBytes,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.speedBytesPerSec != null) {
      yield r'speedBytesPerSec';
      yield serializers.serialize(
        object.speedBytesPerSec,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.etaSeconds != null) {
      yield r'etaSeconds';
      yield serializers.serialize(
        object.etaSeconds,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.percent != null) {
      yield r'percent';
      yield serializers.serialize(
        object.percent,
        specifiedType: const FullType.nullable(double),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    TaskProgress object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required TaskProgressBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'receivedBytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.receivedBytes = valueDes;
          break;
        case r'totalBytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.totalBytes = valueDes;
          break;
        case r'speedBytesPerSec':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.speedBytesPerSec = valueDes;
          break;
        case r'etaSeconds':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.etaSeconds = valueDes;
          break;
        case r'percent':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(double),
          ) as double?;
          if (valueDes == null) continue;
          result.percent = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  TaskProgress deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = TaskProgressBuilder();
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

