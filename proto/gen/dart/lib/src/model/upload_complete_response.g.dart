// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'upload_complete_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UploadCompleteResponse extends UploadCompleteResponse {
  @override
  final String path;

  factory _$UploadCompleteResponse(
          [void Function(UploadCompleteResponseBuilder)? updates]) =>
      (UploadCompleteResponseBuilder()..update(updates))._build();

  _$UploadCompleteResponse._({required this.path}) : super._();
  @override
  UploadCompleteResponse rebuild(
          void Function(UploadCompleteResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UploadCompleteResponseBuilder toBuilder() =>
      UploadCompleteResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UploadCompleteResponse && path == other.path;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, path.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UploadCompleteResponse')
          ..add('path', path))
        .toString();
  }
}

class UploadCompleteResponseBuilder
    implements Builder<UploadCompleteResponse, UploadCompleteResponseBuilder> {
  _$UploadCompleteResponse? _$v;

  String? _path;
  String? get path => _$this._path;
  set path(String? path) => _$this._path = path;

  UploadCompleteResponseBuilder() {
    UploadCompleteResponse._defaults(this);
  }

  UploadCompleteResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _path = $v.path;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UploadCompleteResponse other) {
    _$v = other as _$UploadCompleteResponse;
  }

  @override
  void update(void Function(UploadCompleteResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UploadCompleteResponse build() => _build();

  _$UploadCompleteResponse _build() {
    final _$result = _$v ??
        _$UploadCompleteResponse._(
          path: BuiltValueNullFieldError.checkNotNull(
              path, r'UploadCompleteResponse', 'path'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
