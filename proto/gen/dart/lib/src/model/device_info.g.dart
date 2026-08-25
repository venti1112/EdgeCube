// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_info.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DeviceInfo extends DeviceInfo {
  @override
  final String id;
  @override
  final String name;
  @override
  final DateTime? lastSeenAt;
  @override
  final DateTime createdAt;

  factory _$DeviceInfo([void Function(DeviceInfoBuilder)? updates]) =>
      (DeviceInfoBuilder()..update(updates))._build();

  _$DeviceInfo._(
      {required this.id,
      required this.name,
      this.lastSeenAt,
      required this.createdAt})
      : super._();
  @override
  DeviceInfo rebuild(void Function(DeviceInfoBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DeviceInfoBuilder toBuilder() => DeviceInfoBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DeviceInfo &&
        id == other.id &&
        name == other.name &&
        lastSeenAt == other.lastSeenAt &&
        createdAt == other.createdAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, lastSeenAt.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DeviceInfo')
          ..add('id', id)
          ..add('name', name)
          ..add('lastSeenAt', lastSeenAt)
          ..add('createdAt', createdAt))
        .toString();
  }
}

class DeviceInfoBuilder implements Builder<DeviceInfo, DeviceInfoBuilder> {
  _$DeviceInfo? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  DateTime? _lastSeenAt;
  DateTime? get lastSeenAt => _$this._lastSeenAt;
  set lastSeenAt(DateTime? lastSeenAt) => _$this._lastSeenAt = lastSeenAt;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  DeviceInfoBuilder() {
    DeviceInfo._defaults(this);
  }

  DeviceInfoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _name = $v.name;
      _lastSeenAt = $v.lastSeenAt;
      _createdAt = $v.createdAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DeviceInfo other) {
    _$v = other as _$DeviceInfo;
  }

  @override
  void update(void Function(DeviceInfoBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DeviceInfo build() => _build();

  _$DeviceInfo _build() {
    final _$result = _$v ??
        _$DeviceInfo._(
          id: BuiltValueNullFieldError.checkNotNull(id, r'DeviceInfo', 'id'),
          name: BuiltValueNullFieldError.checkNotNull(
              name, r'DeviceInfo', 'name'),
          lastSeenAt: lastSeenAt,
          createdAt: BuiltValueNullFieldError.checkNotNull(
              createdAt, r'DeviceInfo', 'createdAt'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
