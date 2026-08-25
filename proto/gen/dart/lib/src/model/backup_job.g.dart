// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'backup_job.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const BackupJobLastResultEnum _$backupJobLastResultEnum_success =
    const BackupJobLastResultEnum._('success');
const BackupJobLastResultEnum _$backupJobLastResultEnum_failed =
    const BackupJobLastResultEnum._('failed');
const BackupJobLastResultEnum _$backupJobLastResultEnum_running =
    const BackupJobLastResultEnum._('running');

BackupJobLastResultEnum _$backupJobLastResultEnumValueOf(String name) {
  switch (name) {
    case 'success':
      return _$backupJobLastResultEnum_success;
    case 'failed':
      return _$backupJobLastResultEnum_failed;
    case 'running':
      return _$backupJobLastResultEnum_running;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<BackupJobLastResultEnum> _$backupJobLastResultEnumValues =
    BuiltSet<BackupJobLastResultEnum>(const <BackupJobLastResultEnum>[
  _$backupJobLastResultEnum_success,
  _$backupJobLastResultEnum_failed,
  _$backupJobLastResultEnum_running,
]);

Serializer<BackupJobLastResultEnum> _$backupJobLastResultEnumSerializer =
    _$BackupJobLastResultEnumSerializer();

class _$BackupJobLastResultEnumSerializer
    implements PrimitiveSerializer<BackupJobLastResultEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'success': 'success',
    'failed': 'failed',
    'running': 'running',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'success': 'success',
    'failed': 'failed',
    'running': 'running',
  };

  @override
  final Iterable<Type> types = const <Type>[BackupJobLastResultEnum];
  @override
  final String wireName = 'BackupJobLastResultEnum';

  @override
  Object serialize(Serializers serializers, BackupJobLastResultEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  BackupJobLastResultEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      BackupJobLastResultEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$BackupJob extends BackupJob {
  @override
  final String id;
  @override
  final String name;
  @override
  final String instanceId;
  @override
  final String? scheduleCron;
  @override
  final BuiltList<String>? targetIds;
  @override
  final bool? enabled;
  @override
  final int? maxKeep;
  @override
  final BuiltList<String>? includeDirs;
  @override
  final DateTime? lastRunAt;
  @override
  final BackupJobLastResultEnum? lastResult;

  factory _$BackupJob([void Function(BackupJobBuilder)? updates]) =>
      (BackupJobBuilder()..update(updates))._build();

  _$BackupJob._(
      {required this.id,
      required this.name,
      required this.instanceId,
      this.scheduleCron,
      this.targetIds,
      this.enabled,
      this.maxKeep,
      this.includeDirs,
      this.lastRunAt,
      this.lastResult})
      : super._();
  @override
  BackupJob rebuild(void Function(BackupJobBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BackupJobBuilder toBuilder() => BackupJobBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BackupJob &&
        id == other.id &&
        name == other.name &&
        instanceId == other.instanceId &&
        scheduleCron == other.scheduleCron &&
        targetIds == other.targetIds &&
        enabled == other.enabled &&
        maxKeep == other.maxKeep &&
        includeDirs == other.includeDirs &&
        lastRunAt == other.lastRunAt &&
        lastResult == other.lastResult;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, instanceId.hashCode);
    _$hash = $jc(_$hash, scheduleCron.hashCode);
    _$hash = $jc(_$hash, targetIds.hashCode);
    _$hash = $jc(_$hash, enabled.hashCode);
    _$hash = $jc(_$hash, maxKeep.hashCode);
    _$hash = $jc(_$hash, includeDirs.hashCode);
    _$hash = $jc(_$hash, lastRunAt.hashCode);
    _$hash = $jc(_$hash, lastResult.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BackupJob')
          ..add('id', id)
          ..add('name', name)
          ..add('instanceId', instanceId)
          ..add('scheduleCron', scheduleCron)
          ..add('targetIds', targetIds)
          ..add('enabled', enabled)
          ..add('maxKeep', maxKeep)
          ..add('includeDirs', includeDirs)
          ..add('lastRunAt', lastRunAt)
          ..add('lastResult', lastResult))
        .toString();
  }
}

class BackupJobBuilder implements Builder<BackupJob, BackupJobBuilder> {
  _$BackupJob? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _instanceId;
  String? get instanceId => _$this._instanceId;
  set instanceId(String? instanceId) => _$this._instanceId = instanceId;

  String? _scheduleCron;
  String? get scheduleCron => _$this._scheduleCron;
  set scheduleCron(String? scheduleCron) => _$this._scheduleCron = scheduleCron;

  ListBuilder<String>? _targetIds;
  ListBuilder<String> get targetIds =>
      _$this._targetIds ??= ListBuilder<String>();
  set targetIds(ListBuilder<String>? targetIds) =>
      _$this._targetIds = targetIds;

  bool? _enabled;
  bool? get enabled => _$this._enabled;
  set enabled(bool? enabled) => _$this._enabled = enabled;

  int? _maxKeep;
  int? get maxKeep => _$this._maxKeep;
  set maxKeep(int? maxKeep) => _$this._maxKeep = maxKeep;

  ListBuilder<String>? _includeDirs;
  ListBuilder<String> get includeDirs =>
      _$this._includeDirs ??= ListBuilder<String>();
  set includeDirs(ListBuilder<String>? includeDirs) =>
      _$this._includeDirs = includeDirs;

  DateTime? _lastRunAt;
  DateTime? get lastRunAt => _$this._lastRunAt;
  set lastRunAt(DateTime? lastRunAt) => _$this._lastRunAt = lastRunAt;

  BackupJobLastResultEnum? _lastResult;
  BackupJobLastResultEnum? get lastResult => _$this._lastResult;
  set lastResult(BackupJobLastResultEnum? lastResult) =>
      _$this._lastResult = lastResult;

  BackupJobBuilder() {
    BackupJob._defaults(this);
  }

  BackupJobBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _name = $v.name;
      _instanceId = $v.instanceId;
      _scheduleCron = $v.scheduleCron;
      _targetIds = $v.targetIds?.toBuilder();
      _enabled = $v.enabled;
      _maxKeep = $v.maxKeep;
      _includeDirs = $v.includeDirs?.toBuilder();
      _lastRunAt = $v.lastRunAt;
      _lastResult = $v.lastResult;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BackupJob other) {
    _$v = other as _$BackupJob;
  }

  @override
  void update(void Function(BackupJobBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BackupJob build() => _build();

  _$BackupJob _build() {
    _$BackupJob _$result;
    try {
      _$result = _$v ??
          _$BackupJob._(
            id: BuiltValueNullFieldError.checkNotNull(id, r'BackupJob', 'id'),
            name: BuiltValueNullFieldError.checkNotNull(
                name, r'BackupJob', 'name'),
            instanceId: BuiltValueNullFieldError.checkNotNull(
                instanceId, r'BackupJob', 'instanceId'),
            scheduleCron: scheduleCron,
            targetIds: _targetIds?.build(),
            enabled: enabled,
            maxKeep: maxKeep,
            includeDirs: _includeDirs?.build(),
            lastRunAt: lastRunAt,
            lastResult: lastResult,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'targetIds';
        _targetIds?.build();

        _$failedField = 'includeDirs';
        _includeDirs?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'BackupJob', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
