// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fs_compress_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$FsCompressRequest extends FsCompressRequest {
  @override
  final String instanceId;
  @override
  final String path;
  @override
  final String? destName;

  factory _$FsCompressRequest(
          [void Function(FsCompressRequestBuilder)? updates]) =>
      (FsCompressRequestBuilder()..update(updates))._build();

  _$FsCompressRequest._(
      {required this.instanceId, required this.path, this.destName})
      : super._();
  @override
  FsCompressRequest rebuild(void Function(FsCompressRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  FsCompressRequestBuilder toBuilder() =>
      FsCompressRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is FsCompressRequest &&
        instanceId == other.instanceId &&
        path == other.path &&
        destName == other.destName;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, instanceId.hashCode);
    _$hash = $jc(_$hash, path.hashCode);
    _$hash = $jc(_$hash, destName.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'FsCompressRequest')
          ..add('instanceId', instanceId)
          ..add('path', path)
          ..add('destName', destName))
        .toString();
  }
}

class FsCompressRequestBuilder
    implements Builder<FsCompressRequest, FsCompressRequestBuilder> {
  _$FsCompressRequest? _$v;

  String? _instanceId;
  String? get instanceId => _$this._instanceId;
  set instanceId(String? instanceId) => _$this._instanceId = instanceId;

  String? _path;
  String? get path => _$this._path;
  set path(String? path) => _$this._path = path;

  String? _destName;
  String? get destName => _$this._destName;
  set destName(String? destName) => _$this._destName = destName;

  FsCompressRequestBuilder() {
    FsCompressRequest._defaults(this);
  }

  FsCompressRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _instanceId = $v.instanceId;
      _path = $v.path;
      _destName = $v.destName;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(FsCompressRequest other) {
    _$v = other as _$FsCompressRequest;
  }

  @override
  void update(void Function(FsCompressRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  FsCompressRequest build() => _build();

  _$FsCompressRequest _build() {
    final _$result = _$v ??
        _$FsCompressRequest._(
          instanceId: BuiltValueNullFieldError.checkNotNull(
              instanceId, r'FsCompressRequest', 'instanceId'),
          path: BuiltValueNullFieldError.checkNotNull(
              path, r'FsCompressRequest', 'path'),
          destName: destName,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
