// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pairing_code.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PairingCode extends PairingCode {
  @override
  final String code;
  @override
  final DateTime expiresAt;

  factory _$PairingCode([void Function(PairingCodeBuilder)? updates]) =>
      (PairingCodeBuilder()..update(updates))._build();

  _$PairingCode._({required this.code, required this.expiresAt}) : super._();
  @override
  PairingCode rebuild(void Function(PairingCodeBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PairingCodeBuilder toBuilder() => PairingCodeBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PairingCode &&
        code == other.code &&
        expiresAt == other.expiresAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, code.hashCode);
    _$hash = $jc(_$hash, expiresAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PairingCode')
          ..add('code', code)
          ..add('expiresAt', expiresAt))
        .toString();
  }
}

class PairingCodeBuilder implements Builder<PairingCode, PairingCodeBuilder> {
  _$PairingCode? _$v;

  String? _code;
  String? get code => _$this._code;
  set code(String? code) => _$this._code = code;

  DateTime? _expiresAt;
  DateTime? get expiresAt => _$this._expiresAt;
  set expiresAt(DateTime? expiresAt) => _$this._expiresAt = expiresAt;

  PairingCodeBuilder() {
    PairingCode._defaults(this);
  }

  PairingCodeBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _code = $v.code;
      _expiresAt = $v.expiresAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PairingCode other) {
    _$v = other as _$PairingCode;
  }

  @override
  void update(void Function(PairingCodeBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PairingCode build() => _build();

  _$PairingCode _build() {
    final _$result = _$v ??
        _$PairingCode._(
          code: BuiltValueNullFieldError.checkNotNull(
              code, r'PairingCode', 'code'),
          expiresAt: BuiltValueNullFieldError.checkNotNull(
              expiresAt, r'PairingCode', 'expiresAt'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
