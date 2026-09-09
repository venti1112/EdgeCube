// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fs_write_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$FsWriteRequest extends FsWriteRequest {
  @override
  final String instanceId;
  @override
  final String path;
  @override
  final String content;

  factory _$FsWriteRequest([void Function(FsWriteRequestBuilder)? updates]) =>
      (FsWriteRequestBuilder()..update(updates))._build();

  _$FsWriteRequest._(
      {required this.instanceId, required this.path, required this.content})
      : super._();
  @override
  FsWriteRequest rebuild(void Function(FsWriteRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  FsWriteRequestBuilder toBuilder() => FsWriteRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is FsWriteRequest &&
        instanceId == other.instanceId &&
        path == other.path &&
        content == other.content;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, instanceId.hashCode);
    _$hash = $jc(_$hash, path.hashCode);
    _$hash = $jc(_$hash, content.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'FsWriteRequest')
          ..add('instanceId', instanceId)
          ..add('path', path)
          ..add('content', content))
        .toString();
  }
}

class FsWriteRequestBuilder
    implements Builder<FsWriteRequest, FsWriteRequestBuilder> {
  _$FsWriteRequest? _$v;

  String? _instanceId;
  String? get instanceId => _$this._instanceId;
  set instanceId(String? instanceId) => _$this._instanceId = instanceId;

  String? _path;
  String? get path => _$this._path;
  set path(String? path) => _$this._path = path;

  String? _content;
  String? get content => _$this._content;
  set content(String? content) => _$this._content = content;

  FsWriteRequestBuilder() {
    FsWriteRequest._defaults(this);
  }

  FsWriteRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _instanceId = $v.instanceId;
      _path = $v.path;
      _content = $v.content;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(FsWriteRequest other) {
    _$v = other as _$FsWriteRequest;
  }

  @override
  void update(void Function(FsWriteRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  FsWriteRequest build() => _build();

  _$FsWriteRequest _build() {
    final _$result = _$v ??
        _$FsWriteRequest._(
          instanceId: BuiltValueNullFieldError.checkNotNull(
              instanceId, r'FsWriteRequest', 'instanceId'),
          path: BuiltValueNullFieldError.checkNotNull(
              path, r'FsWriteRequest', 'path'),
          content: BuiltValueNullFieldError.checkNotNull(
              content, r'FsWriteRequest', 'content'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
