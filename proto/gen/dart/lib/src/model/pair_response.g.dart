// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pair_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PairResponse extends PairResponse {
  @override
  final String token;
  @override
  final String deviceId;

  factory _$PairResponse([void Function(PairResponseBuilder)? updates]) =>
      (PairResponseBuilder()..update(updates))._build();

  _$PairResponse._({required this.token, required this.deviceId}) : super._();
  @override
  PairResponse rebuild(void Function(PairResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PairResponseBuilder toBuilder() => PairResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PairResponse &&
        token == other.token &&
        deviceId == other.deviceId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, token.hashCode);
    _$hash = $jc(_$hash, deviceId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PairResponse')
          ..add('token', token)
          ..add('deviceId', deviceId))
        .toString();
  }
}

class PairResponseBuilder
    implements Builder<PairResponse, PairResponseBuilder> {
  _$PairResponse? _$v;

  String? _token;
  String? get token => _$this._token;
  set token(String? token) => _$this._token = token;

  String? _deviceId;
  String? get deviceId => _$this._deviceId;
  set deviceId(String? deviceId) => _$this._deviceId = deviceId;

  PairResponseBuilder() {
    PairResponse._defaults(this);
  }

  PairResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _token = $v.token;
      _deviceId = $v.deviceId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PairResponse other) {
    _$v = other as _$PairResponse;
  }

  @override
  void update(void Function(PairResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PairResponse build() => _build();

  _$PairResponse _build() {
    final _$result = _$v ??
        _$PairResponse._(
          token: BuiltValueNullFieldError.checkNotNull(
              token, r'PairResponse', 'token'),
          deviceId: BuiltValueNullFieldError.checkNotNull(
              deviceId, r'PairResponse', 'deviceId'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
