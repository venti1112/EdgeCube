// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'monitor_snapshot.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MonitorSnapshot extends MonitorSnapshot {
  @override
  final double cpuPercent;
  @override
  final int memoryTotalBytes;
  @override
  final int memoryUsedBytes;
  @override
  final BuiltList<MonitorSnapshotDisksInner>? disks;
  @override
  final int? networkRxBytesPerSec;
  @override
  final int? networkTxBytesPerSec;
  @override
  final int uptimeSeconds;

  factory _$MonitorSnapshot([void Function(MonitorSnapshotBuilder)? updates]) =>
      (MonitorSnapshotBuilder()..update(updates))._build();

  _$MonitorSnapshot._(
      {required this.cpuPercent,
      required this.memoryTotalBytes,
      required this.memoryUsedBytes,
      this.disks,
      this.networkRxBytesPerSec,
      this.networkTxBytesPerSec,
      required this.uptimeSeconds})
      : super._();
  @override
  MonitorSnapshot rebuild(void Function(MonitorSnapshotBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MonitorSnapshotBuilder toBuilder() => MonitorSnapshotBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MonitorSnapshot &&
        cpuPercent == other.cpuPercent &&
        memoryTotalBytes == other.memoryTotalBytes &&
        memoryUsedBytes == other.memoryUsedBytes &&
        disks == other.disks &&
        networkRxBytesPerSec == other.networkRxBytesPerSec &&
        networkTxBytesPerSec == other.networkTxBytesPerSec &&
        uptimeSeconds == other.uptimeSeconds;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, cpuPercent.hashCode);
    _$hash = $jc(_$hash, memoryTotalBytes.hashCode);
    _$hash = $jc(_$hash, memoryUsedBytes.hashCode);
    _$hash = $jc(_$hash, disks.hashCode);
    _$hash = $jc(_$hash, networkRxBytesPerSec.hashCode);
    _$hash = $jc(_$hash, networkTxBytesPerSec.hashCode);
    _$hash = $jc(_$hash, uptimeSeconds.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MonitorSnapshot')
          ..add('cpuPercent', cpuPercent)
          ..add('memoryTotalBytes', memoryTotalBytes)
          ..add('memoryUsedBytes', memoryUsedBytes)
          ..add('disks', disks)
          ..add('networkRxBytesPerSec', networkRxBytesPerSec)
          ..add('networkTxBytesPerSec', networkTxBytesPerSec)
          ..add('uptimeSeconds', uptimeSeconds))
        .toString();
  }
}

class MonitorSnapshotBuilder
    implements Builder<MonitorSnapshot, MonitorSnapshotBuilder> {
  _$MonitorSnapshot? _$v;

  double? _cpuPercent;
  double? get cpuPercent => _$this._cpuPercent;
  set cpuPercent(double? cpuPercent) => _$this._cpuPercent = cpuPercent;

  int? _memoryTotalBytes;
  int? get memoryTotalBytes => _$this._memoryTotalBytes;
  set memoryTotalBytes(int? memoryTotalBytes) =>
      _$this._memoryTotalBytes = memoryTotalBytes;

  int? _memoryUsedBytes;
  int? get memoryUsedBytes => _$this._memoryUsedBytes;
  set memoryUsedBytes(int? memoryUsedBytes) =>
      _$this._memoryUsedBytes = memoryUsedBytes;

  ListBuilder<MonitorSnapshotDisksInner>? _disks;
  ListBuilder<MonitorSnapshotDisksInner> get disks =>
      _$this._disks ??= ListBuilder<MonitorSnapshotDisksInner>();
  set disks(ListBuilder<MonitorSnapshotDisksInner>? disks) =>
      _$this._disks = disks;

  int? _networkRxBytesPerSec;
  int? get networkRxBytesPerSec => _$this._networkRxBytesPerSec;
  set networkRxBytesPerSec(int? networkRxBytesPerSec) =>
      _$this._networkRxBytesPerSec = networkRxBytesPerSec;

  int? _networkTxBytesPerSec;
  int? get networkTxBytesPerSec => _$this._networkTxBytesPerSec;
  set networkTxBytesPerSec(int? networkTxBytesPerSec) =>
      _$this._networkTxBytesPerSec = networkTxBytesPerSec;

  int? _uptimeSeconds;
  int? get uptimeSeconds => _$this._uptimeSeconds;
  set uptimeSeconds(int? uptimeSeconds) =>
      _$this._uptimeSeconds = uptimeSeconds;

  MonitorSnapshotBuilder() {
    MonitorSnapshot._defaults(this);
  }

  MonitorSnapshotBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _cpuPercent = $v.cpuPercent;
      _memoryTotalBytes = $v.memoryTotalBytes;
      _memoryUsedBytes = $v.memoryUsedBytes;
      _disks = $v.disks?.toBuilder();
      _networkRxBytesPerSec = $v.networkRxBytesPerSec;
      _networkTxBytesPerSec = $v.networkTxBytesPerSec;
      _uptimeSeconds = $v.uptimeSeconds;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MonitorSnapshot other) {
    _$v = other as _$MonitorSnapshot;
  }

  @override
  void update(void Function(MonitorSnapshotBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MonitorSnapshot build() => _build();

  _$MonitorSnapshot _build() {
    _$MonitorSnapshot _$result;
    try {
      _$result = _$v ??
          _$MonitorSnapshot._(
            cpuPercent: BuiltValueNullFieldError.checkNotNull(
                cpuPercent, r'MonitorSnapshot', 'cpuPercent'),
            memoryTotalBytes: BuiltValueNullFieldError.checkNotNull(
                memoryTotalBytes, r'MonitorSnapshot', 'memoryTotalBytes'),
            memoryUsedBytes: BuiltValueNullFieldError.checkNotNull(
                memoryUsedBytes, r'MonitorSnapshot', 'memoryUsedBytes'),
            disks: _disks?.build(),
            networkRxBytesPerSec: networkRxBytesPerSec,
            networkTxBytesPerSec: networkTxBytesPerSec,
            uptimeSeconds: BuiltValueNullFieldError.checkNotNull(
                uptimeSeconds, r'MonitorSnapshot', 'uptimeSeconds'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'disks';
        _disks?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'MonitorSnapshot', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
