// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'runtime_info.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RuntimeInfo extends RuntimeInfo {
  @override
  final String id;
  @override
  final RuntimeType type;
  @override
  final String version;
  @override
  final String? arch;
  @override
  final String path;
  @override
  final int? sizeBytes;
  @override
  final DateTime installedAt;
  @override
  final bool? default_;

  factory _$RuntimeInfo([void Function(RuntimeInfoBuilder)? updates]) =>
      (RuntimeInfoBuilder()..update(updates))._build();

  _$RuntimeInfo._(
      {required this.id,
      required this.type,
      required this.version,
      this.arch,
      required this.path,
      this.sizeBytes,
      required this.installedAt,
      this.default_})
      : super._();
  @override
  RuntimeInfo rebuild(void Function(RuntimeInfoBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RuntimeInfoBuilder toBuilder() => RuntimeInfoBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RuntimeInfo &&
        id == other.id &&
        type == other.type &&
        version == other.version &&
        arch == other.arch &&
        path == other.path &&
        sizeBytes == other.sizeBytes &&
        installedAt == other.installedAt &&
        default_ == other.default_;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, type.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jc(_$hash, arch.hashCode);
    _$hash = $jc(_$hash, path.hashCode);
    _$hash = $jc(_$hash, sizeBytes.hashCode);
    _$hash = $jc(_$hash, installedAt.hashCode);
    _$hash = $jc(_$hash, default_.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RuntimeInfo')
          ..add('id', id)
          ..add('type', type)
          ..add('version', version)
          ..add('arch', arch)
          ..add('path', path)
          ..add('sizeBytes', sizeBytes)
          ..add('installedAt', installedAt)
          ..add('default_', default_))
        .toString();
  }
}

class RuntimeInfoBuilder implements Builder<RuntimeInfo, RuntimeInfoBuilder> {
  _$RuntimeInfo? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  RuntimeType? _type;
  RuntimeType? get type => _$this._type;
  set type(RuntimeType? type) => _$this._type = type;

  String? _version;
  String? get version => _$this._version;
  set version(String? version) => _$this._version = version;

  String? _arch;
  String? get arch => _$this._arch;
  set arch(String? arch) => _$this._arch = arch;

  String? _path;
  String? get path => _$this._path;
  set path(String? path) => _$this._path = path;

  int? _sizeBytes;
  int? get sizeBytes => _$this._sizeBytes;
  set sizeBytes(int? sizeBytes) => _$this._sizeBytes = sizeBytes;

  DateTime? _installedAt;
  DateTime? get installedAt => _$this._installedAt;
  set installedAt(DateTime? installedAt) => _$this._installedAt = installedAt;

  bool? _default_;
  bool? get default_ => _$this._default_;
  set default_(bool? default_) => _$this._default_ = default_;

  RuntimeInfoBuilder() {
    RuntimeInfo._defaults(this);
  }

  RuntimeInfoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _type = $v.type;
      _version = $v.version;
      _arch = $v.arch;
      _path = $v.path;
      _sizeBytes = $v.sizeBytes;
      _installedAt = $v.installedAt;
      _default_ = $v.default_;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RuntimeInfo other) {
    _$v = other as _$RuntimeInfo;
  }

  @override
  void update(void Function(RuntimeInfoBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RuntimeInfo build() => _build();

  _$RuntimeInfo _build() {
    final _$result = _$v ??
        _$RuntimeInfo._(
          id: BuiltValueNullFieldError.checkNotNull(id, r'RuntimeInfo', 'id'),
          type: BuiltValueNullFieldError.checkNotNull(
              type, r'RuntimeInfo', 'type'),
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'RuntimeInfo', 'version'),
          arch: arch,
          path: BuiltValueNullFieldError.checkNotNull(
              path, r'RuntimeInfo', 'path'),
          sizeBytes: sizeBytes,
          installedAt: BuiltValueNullFieldError.checkNotNull(
              installedAt, r'RuntimeInfo', 'installedAt'),
          default_: default_,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
