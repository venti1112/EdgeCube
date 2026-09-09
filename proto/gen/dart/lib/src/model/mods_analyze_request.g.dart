// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mods_analyze_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ModsAnalyzeRequest extends ModsAnalyzeRequest {
  @override
  final String path;

  factory _$ModsAnalyzeRequest(
          [void Function(ModsAnalyzeRequestBuilder)? updates]) =>
      (ModsAnalyzeRequestBuilder()..update(updates))._build();

  _$ModsAnalyzeRequest._({required this.path}) : super._();
  @override
  ModsAnalyzeRequest rebuild(
          void Function(ModsAnalyzeRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ModsAnalyzeRequestBuilder toBuilder() =>
      ModsAnalyzeRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ModsAnalyzeRequest && path == other.path;
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
    return (newBuiltValueToStringHelper(r'ModsAnalyzeRequest')
          ..add('path', path))
        .toString();
  }
}

class ModsAnalyzeRequestBuilder
    implements Builder<ModsAnalyzeRequest, ModsAnalyzeRequestBuilder> {
  _$ModsAnalyzeRequest? _$v;

  String? _path;
  String? get path => _$this._path;
  set path(String? path) => _$this._path = path;

  ModsAnalyzeRequestBuilder() {
    ModsAnalyzeRequest._defaults(this);
  }

  ModsAnalyzeRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _path = $v.path;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ModsAnalyzeRequest other) {
    _$v = other as _$ModsAnalyzeRequest;
  }

  @override
  void update(void Function(ModsAnalyzeRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ModsAnalyzeRequest build() => _build();

  _$ModsAnalyzeRequest _build() {
    final _$result = _$v ??
        _$ModsAnalyzeRequest._(
          path: BuiltValueNullFieldError.checkNotNull(
              path, r'ModsAnalyzeRequest', 'path'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
