// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'task_status.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const TaskStatus _$queued = const TaskStatus._('queued');
const TaskStatus _$running = const TaskStatus._('running');
const TaskStatus _$succeeded = const TaskStatus._('succeeded');
const TaskStatus _$failed = const TaskStatus._('failed');
const TaskStatus _$cancelled = const TaskStatus._('cancelled');

TaskStatus _$valueOf(String name) {
  switch (name) {
    case 'queued':
      return _$queued;
    case 'running':
      return _$running;
    case 'succeeded':
      return _$succeeded;
    case 'failed':
      return _$failed;
    case 'cancelled':
      return _$cancelled;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<TaskStatus> _$values = BuiltSet<TaskStatus>(const <TaskStatus>[
  _$queued,
  _$running,
  _$succeeded,
  _$failed,
  _$cancelled,
]);

class _$TaskStatusMeta {
  const _$TaskStatusMeta();
  TaskStatus get queued => _$queued;
  TaskStatus get running => _$running;
  TaskStatus get succeeded => _$succeeded;
  TaskStatus get failed => _$failed;
  TaskStatus get cancelled => _$cancelled;
  TaskStatus valueOf(String name) => _$valueOf(name);
  BuiltSet<TaskStatus> get values => _$values;
}

abstract class _$TaskStatusMixin {
  // ignore: non_constant_identifier_names
  _$TaskStatusMeta get TaskStatus => const _$TaskStatusMeta();
}

Serializer<TaskStatus> _$taskStatusSerializer = _$TaskStatusSerializer();

class _$TaskStatusSerializer implements PrimitiveSerializer<TaskStatus> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'queued': 'queued',
    'running': 'running',
    'succeeded': 'succeeded',
    'failed': 'failed',
    'cancelled': 'cancelled',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'queued': 'queued',
    'running': 'running',
    'succeeded': 'succeeded',
    'failed': 'failed',
    'cancelled': 'cancelled',
  };

  @override
  final Iterable<Type> types = const <Type>[TaskStatus];
  @override
  final String wireName = 'TaskStatus';

  @override
  Object serialize(Serializers serializers, TaskStatus object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  TaskStatus deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      TaskStatus.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
