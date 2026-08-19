// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fs_path_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$FsPathRequest extends FsPathRequest {
  @override
  final String instanceId;
  @override
  final String path;

  factory _$FsPathRequest([void Function(FsPathRequestBuilder)? updates]) =>
      (FsPathRequestBuilder()..update(updates))._build();

  _$FsPathRequest._({required this.instanceId, required this.path}) : super._();
  @override
  FsPathRequest rebuild(void Function(FsPathRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  FsPathRequestBuilder toBuilder() => FsPathRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is FsPathRequest &&
        instanceId == other.instanceId &&
        path == other.path;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, instanceId.hashCode);
    _$hash = $jc(_$hash, path.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'FsPathRequest')
          ..add('instanceId', instanceId)
          ..add('path', path))
        .toString();
  }
}

class FsPathRequestBuilder
    implements Builder<FsPathRequest, FsPathRequestBuilder> {
  _$FsPathRequest? _$v;

  String? _instanceId;
  String? get instanceId => _$this._instanceId;
  set instanceId(String? instanceId) => _$this._instanceId = instanceId;

  String? _path;
  String? get path => _$this._path;
  set path(String? path) => _$this._path = path;

  FsPathRequestBuilder() {
    FsPathRequest._defaults(this);
  }

  FsPathRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _instanceId = $v.instanceId;
      _path = $v.path;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(FsPathRequest other) {
    _$v = other as _$FsPathRequest;
  }

  @override
  void update(void Function(FsPathRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  FsPathRequest build() => _build();

  _$FsPathRequest _build() {
    final _$result = _$v ??
        _$FsPathRequest._(
          instanceId: BuiltValueNullFieldError.checkNotNull(
              instanceId, r'FsPathRequest', 'instanceId'),
          path: BuiltValueNullFieldError.checkNotNull(
              path, r'FsPathRequest', 'path'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
