// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'task_progress.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$TaskProgress extends TaskProgress {
  @override
  final int? receivedBytes;
  @override
  final int? totalBytes;
  @override
  final int? speedBytesPerSec;
  @override
  final int? etaSeconds;
  @override
  final double? percent;

  factory _$TaskProgress([void Function(TaskProgressBuilder)? updates]) =>
      (TaskProgressBuilder()..update(updates))._build();

  _$TaskProgress._(
      {this.receivedBytes,
      this.totalBytes,
      this.speedBytesPerSec,
      this.etaSeconds,
      this.percent})
      : super._();
  @override
  TaskProgress rebuild(void Function(TaskProgressBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  TaskProgressBuilder toBuilder() => TaskProgressBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is TaskProgress &&
        receivedBytes == other.receivedBytes &&
        totalBytes == other.totalBytes &&
        speedBytesPerSec == other.speedBytesPerSec &&
        etaSeconds == other.etaSeconds &&
        percent == other.percent;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, receivedBytes.hashCode);
    _$hash = $jc(_$hash, totalBytes.hashCode);
    _$hash = $jc(_$hash, speedBytesPerSec.hashCode);
    _$hash = $jc(_$hash, etaSeconds.hashCode);
    _$hash = $jc(_$hash, percent.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'TaskProgress')
          ..add('receivedBytes', receivedBytes)
          ..add('totalBytes', totalBytes)
          ..add('speedBytesPerSec', speedBytesPerSec)
          ..add('etaSeconds', etaSeconds)
          ..add('percent', percent))
        .toString();
  }
}

class TaskProgressBuilder
    implements Builder<TaskProgress, TaskProgressBuilder> {
  _$TaskProgress? _$v;

  int? _receivedBytes;
  int? get receivedBytes => _$this._receivedBytes;
  set receivedBytes(int? receivedBytes) =>
      _$this._receivedBytes = receivedBytes;

  int? _totalBytes;
  int? get totalBytes => _$this._totalBytes;
  set totalBytes(int? totalBytes) => _$this._totalBytes = totalBytes;

  int? _speedBytesPerSec;
  int? get speedBytesPerSec => _$this._speedBytesPerSec;
  set speedBytesPerSec(int? speedBytesPerSec) =>
      _$this._speedBytesPerSec = speedBytesPerSec;

  int? _etaSeconds;
  int? get etaSeconds => _$this._etaSeconds;
  set etaSeconds(int? etaSeconds) => _$this._etaSeconds = etaSeconds;

  double? _percent;
  double? get percent => _$this._percent;
  set percent(double? percent) => _$this._percent = percent;

  TaskProgressBuilder() {
    TaskProgress._defaults(this);
  }

  TaskProgressBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _receivedBytes = $v.receivedBytes;
      _totalBytes = $v.totalBytes;
      _speedBytesPerSec = $v.speedBytesPerSec;
      _etaSeconds = $v.etaSeconds;
      _percent = $v.percent;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(TaskProgress other) {
    _$v = other as _$TaskProgress;
  }

  @override
  void update(void Function(TaskProgressBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  TaskProgress build() => _build();

  _$TaskProgress _build() {
    final _$result = _$v ??
        _$TaskProgress._(
          receivedBytes: receivedBytes,
          totalBytes: totalBytes,
          speedBytesPerSec: speedBytesPerSec,
          etaSeconds: etaSeconds,
          percent: percent,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
