// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'monitor_snapshot_disks_inner.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MonitorSnapshotDisksInner extends MonitorSnapshotDisksInner {
  @override
  final String? path;
  @override
  final int? totalBytes;
  @override
  final int? usedBytes;

  factory _$MonitorSnapshotDisksInner(
          [void Function(MonitorSnapshotDisksInnerBuilder)? updates]) =>
      (MonitorSnapshotDisksInnerBuilder()..update(updates))._build();

  _$MonitorSnapshotDisksInner._({this.path, this.totalBytes, this.usedBytes})
      : super._();
  @override
  MonitorSnapshotDisksInner rebuild(
          void Function(MonitorSnapshotDisksInnerBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MonitorSnapshotDisksInnerBuilder toBuilder() =>
      MonitorSnapshotDisksInnerBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MonitorSnapshotDisksInner &&
        path == other.path &&
        totalBytes == other.totalBytes &&
        usedBytes == other.usedBytes;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, path.hashCode);
    _$hash = $jc(_$hash, totalBytes.hashCode);
    _$hash = $jc(_$hash, usedBytes.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MonitorSnapshotDisksInner')
          ..add('path', path)
          ..add('totalBytes', totalBytes)
          ..add('usedBytes', usedBytes))
        .toString();
  }
}

class MonitorSnapshotDisksInnerBuilder
    implements
        Builder<MonitorSnapshotDisksInner, MonitorSnapshotDisksInnerBuilder> {
  _$MonitorSnapshotDisksInner? _$v;

  String? _path;
  String? get path => _$this._path;
  set path(String? path) => _$this._path = path;

  int? _totalBytes;
  int? get totalBytes => _$this._totalBytes;
  set totalBytes(int? totalBytes) => _$this._totalBytes = totalBytes;

  int? _usedBytes;
  int? get usedBytes => _$this._usedBytes;
  set usedBytes(int? usedBytes) => _$this._usedBytes = usedBytes;

  MonitorSnapshotDisksInnerBuilder() {
    MonitorSnapshotDisksInner._defaults(this);
  }

  MonitorSnapshotDisksInnerBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _path = $v.path;
      _totalBytes = $v.totalBytes;
      _usedBytes = $v.usedBytes;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MonitorSnapshotDisksInner other) {
    _$v = other as _$MonitorSnapshotDisksInner;
  }

  @override
  void update(void Function(MonitorSnapshotDisksInnerBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MonitorSnapshotDisksInner build() => _build();

  _$MonitorSnapshotDisksInner _build() {
    final _$result = _$v ??
        _$MonitorSnapshotDisksInner._(
          path: path,
          totalBytes: totalBytes,
          usedBytes: usedBytes,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
