// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'error_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ErrorResponse extends ErrorResponse {
  @override
  final String code;
  @override
  final String message;
  @override
  final BuiltMap<String, JsonObject?>? details;

  factory _$ErrorResponse([void Function(ErrorResponseBuilder)? updates]) =>
      (ErrorResponseBuilder()..update(updates))._build();

  _$ErrorResponse._({required this.code, required this.message, this.details})
      : super._();
  @override
  ErrorResponse rebuild(void Function(ErrorResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ErrorResponseBuilder toBuilder() => ErrorResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ErrorResponse &&
        code == other.code &&
        message == other.message &&
        details == other.details;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, code.hashCode);
    _$hash = $jc(_$hash, message.hashCode);
    _$hash = $jc(_$hash, details.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ErrorResponse')
          ..add('code', code)
          ..add('message', message)
          ..add('details', details))
        .toString();
  }
}

class ErrorResponseBuilder
    implements Builder<ErrorResponse, ErrorResponseBuilder> {
  _$ErrorResponse? _$v;

  String? _code;
  String? get code => _$this._code;
  set code(String? code) => _$this._code = code;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  MapBuilder<String, JsonObject?>? _details;
  MapBuilder<String, JsonObject?> get details =>
      _$this._details ??= MapBuilder<String, JsonObject?>();
  set details(MapBuilder<String, JsonObject?>? details) =>
      _$this._details = details;

  ErrorResponseBuilder() {
    ErrorResponse._defaults(this);
  }

  ErrorResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _code = $v.code;
      _message = $v.message;
      _details = $v.details?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ErrorResponse other) {
    _$v = other as _$ErrorResponse;
  }

  @override
  void update(void Function(ErrorResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ErrorResponse build() => _build();

  _$ErrorResponse _build() {
    _$ErrorResponse _$result;
    try {
      _$result = _$v ??
          _$ErrorResponse._(
            code: BuiltValueNullFieldError.checkNotNull(
                code, r'ErrorResponse', 'code'),
            message: BuiltValueNullFieldError.checkNotNull(
                message, r'ErrorResponse', 'message'),
            details: _details?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'details';
        _details?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ErrorResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
