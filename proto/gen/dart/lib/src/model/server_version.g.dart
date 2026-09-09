// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'server_version.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ServerVersion extends ServerVersion {
  @override
  final String version;
  @override
  final BuiltMap<String, JsonObject?>? meta;

  factory _$ServerVersion([void Function(ServerVersionBuilder)? updates]) =>
      (ServerVersionBuilder()..update(updates))._build();

  _$ServerVersion._({required this.version, this.meta}) : super._();
  @override
  ServerVersion rebuild(void Function(ServerVersionBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ServerVersionBuilder toBuilder() => ServerVersionBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ServerVersion &&
        version == other.version &&
        meta == other.meta;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jc(_$hash, meta.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ServerVersion')
          ..add('version', version)
          ..add('meta', meta))
        .toString();
  }
}

class ServerVersionBuilder
    implements Builder<ServerVersion, ServerVersionBuilder> {
  _$ServerVersion? _$v;

  String? _version;
  String? get version => _$this._version;
  set version(String? version) => _$this._version = version;

  MapBuilder<String, JsonObject?>? _meta;
  MapBuilder<String, JsonObject?> get meta =>
      _$this._meta ??= MapBuilder<String, JsonObject?>();
  set meta(MapBuilder<String, JsonObject?>? meta) => _$this._meta = meta;

  ServerVersionBuilder() {
    ServerVersion._defaults(this);
  }

  ServerVersionBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _version = $v.version;
      _meta = $v.meta?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ServerVersion other) {
    _$v = other as _$ServerVersion;
  }

  @override
  void update(void Function(ServerVersionBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ServerVersion build() => _build();

  _$ServerVersion _build() {
    _$ServerVersion _$result;
    try {
      _$result = _$v ??
          _$ServerVersion._(
            version: BuiltValueNullFieldError.checkNotNull(
                version, r'ServerVersion', 'version'),
            meta: _meta?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'meta';
        _meta?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ServerVersion', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
