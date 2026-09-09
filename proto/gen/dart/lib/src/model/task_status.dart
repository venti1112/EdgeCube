//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'task_status.g.dart';

class TaskStatus extends EnumClass {

  /// 任务状态机:queued 排队 → running 执行中 → succeeded/failed 终结;queued/running 可被取消 → cancelled
  @BuiltValueEnumConst(wireName: r'queued')
  static const TaskStatus queued = _$queued;
  /// 任务状态机:queued 排队 → running 执行中 → succeeded/failed 终结;queued/running 可被取消 → cancelled
  @BuiltValueEnumConst(wireName: r'running')
  static const TaskStatus running = _$running;
  /// 任务状态机:queued 排队 → running 执行中 → succeeded/failed 终结;queued/running 可被取消 → cancelled
  @BuiltValueEnumConst(wireName: r'succeeded')
  static const TaskStatus succeeded = _$succeeded;
  /// 任务状态机:queued 排队 → running 执行中 → succeeded/failed 终结;queued/running 可被取消 → cancelled
  @BuiltValueEnumConst(wireName: r'failed')
  static const TaskStatus failed = _$failed;
  /// 任务状态机:queued 排队 → running 执行中 → succeeded/failed 终结;queued/running 可被取消 → cancelled
  @BuiltValueEnumConst(wireName: r'cancelled')
  static const TaskStatus cancelled = _$cancelled;

  static Serializer<TaskStatus> get serializer => _$taskStatusSerializer;

  const TaskStatus._(String name): super(name);

  static BuiltSet<TaskStatus> get values => _$values;
  static TaskStatus valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class TaskStatusMixin = Object with _$TaskStatusMixin;

