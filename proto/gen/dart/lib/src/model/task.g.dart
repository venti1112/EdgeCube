// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'task.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$Task extends Task {
  @override
  final String id;
  @override
  final TaskKind kind;
  @override
  final String? displayName;
  @override
  final String? instanceId;
  @override
  final TaskStatus status;
  @override
  final String? phase;
  @override
  final TaskProgress? progress;
  @override
  final TaskError? error;
  @override
  final DateTime createdAt;
  @override
  final DateTime? startedAt;
  @override
  final DateTime? finishedAt;

  factory _$Task([void Function(TaskBuilder)? updates]) =>
      (TaskBuilder()..update(updates))._build();

  _$Task._(
      {required this.id,
      required this.kind,
      this.displayName,
      this.instanceId,
      required this.status,
      this.phase,
      this.progress,
      this.error,
      required this.createdAt,
      this.startedAt,
      this.finishedAt})
      : super._();
  @override
  Task rebuild(void Function(TaskBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  TaskBuilder toBuilder() => TaskBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is Task &&
        id == other.id &&
        kind == other.kind &&
        displayName == other.displayName &&
        instanceId == other.instanceId &&
        status == other.status &&
        phase == other.phase &&
        progress == other.progress &&
        error == other.error &&
        createdAt == other.createdAt &&
        startedAt == other.startedAt &&
        finishedAt == other.finishedAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, displayName.hashCode);
    _$hash = $jc(_$hash, instanceId.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jc(_$hash, phase.hashCode);
    _$hash = $jc(_$hash, progress.hashCode);
    _$hash = $jc(_$hash, error.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, startedAt.hashCode);
    _$hash = $jc(_$hash, finishedAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'Task')
          ..add('id', id)
          ..add('kind', kind)
          ..add('displayName', displayName)
          ..add('instanceId', instanceId)
          ..add('status', status)
          ..add('phase', phase)
          ..add('progress', progress)
          ..add('error', error)
          ..add('createdAt', createdAt)
          ..add('startedAt', startedAt)
          ..add('finishedAt', finishedAt))
        .toString();
  }
}

class TaskBuilder implements Builder<Task, TaskBuilder> {
  _$Task? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  TaskKind? _kind;
  TaskKind? get kind => _$this._kind;
  set kind(TaskKind? kind) => _$this._kind = kind;

  String? _displayName;
  String? get displayName => _$this._displayName;
  set displayName(String? displayName) => _$this._displayName = displayName;

  String? _instanceId;
  String? get instanceId => _$this._instanceId;
  set instanceId(String? instanceId) => _$this._instanceId = instanceId;

  TaskStatus? _status;
  TaskStatus? get status => _$this._status;
  set status(TaskStatus? status) => _$this._status = status;

  String? _phase;
  String? get phase => _$this._phase;
  set phase(String? phase) => _$this._phase = phase;

  TaskProgressBuilder? _progress;
  TaskProgressBuilder get progress =>
      _$this._progress ??= TaskProgressBuilder();
  set progress(TaskProgressBuilder? progress) => _$this._progress = progress;

  TaskErrorBuilder? _error;
  TaskErrorBuilder get error => _$this._error ??= TaskErrorBuilder();
  set error(TaskErrorBuilder? error) => _$this._error = error;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  DateTime? _startedAt;
  DateTime? get startedAt => _$this._startedAt;
  set startedAt(DateTime? startedAt) => _$this._startedAt = startedAt;

  DateTime? _finishedAt;
  DateTime? get finishedAt => _$this._finishedAt;
  set finishedAt(DateTime? finishedAt) => _$this._finishedAt = finishedAt;

  TaskBuilder() {
    Task._defaults(this);
  }

  TaskBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _kind = $v.kind;
      _displayName = $v.displayName;
      _instanceId = $v.instanceId;
      _status = $v.status;
      _phase = $v.phase;
      _progress = $v.progress?.toBuilder();
      _error = $v.error?.toBuilder();
      _createdAt = $v.createdAt;
      _startedAt = $v.startedAt;
      _finishedAt = $v.finishedAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(Task other) {
    _$v = other as _$Task;
  }

  @override
  void update(void Function(TaskBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  Task build() => _build();

  _$Task _build() {
    _$Task _$result;
    try {
      _$result = _$v ??
          _$Task._(
            id: BuiltValueNullFieldError.checkNotNull(id, r'Task', 'id'),
            kind: BuiltValueNullFieldError.checkNotNull(kind, r'Task', 'kind'),
            displayName: displayName,
            instanceId: instanceId,
            status: BuiltValueNullFieldError.checkNotNull(
                status, r'Task', 'status'),
            phase: phase,
            progress: _progress?.build(),
            error: _error?.build(),
            createdAt: BuiltValueNullFieldError.checkNotNull(
                createdAt, r'Task', 'createdAt'),
            startedAt: startedAt,
            finishedAt: finishedAt,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'progress';
        _progress?.build();
        _$failedField = 'error';
        _error?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(r'Task', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
