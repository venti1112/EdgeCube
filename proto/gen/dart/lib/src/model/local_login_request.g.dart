// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_login_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$LocalLoginRequest extends LocalLoginRequest {
  @override
  final String challenge;
  @override
  final String signature;
  @override
  final String? deviceName;

  factory _$LocalLoginRequest(
          [void Function(LocalLoginRequestBuilder)? updates]) =>
      (LocalLoginRequestBuilder()..update(updates))._build();

  _$LocalLoginRequest._(
      {required this.challenge, required this.signature, this.deviceName})
      : super._();
  @override
  LocalLoginRequest rebuild(void Function(LocalLoginRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  LocalLoginRequestBuilder toBuilder() =>
      LocalLoginRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is LocalLoginRequest &&
        challenge == other.challenge &&
        signature == other.signature &&
        deviceName == other.deviceName;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, challenge.hashCode);
    _$hash = $jc(_$hash, signature.hashCode);
    _$hash = $jc(_$hash, deviceName.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'LocalLoginRequest')
          ..add('challenge', challenge)
          ..add('signature', signature)
          ..add('deviceName', deviceName))
        .toString();
  }
}

class LocalLoginRequestBuilder
    implements Builder<LocalLoginRequest, LocalLoginRequestBuilder> {
  _$LocalLoginRequest? _$v;

  String? _challenge;
  String? get challenge => _$this._challenge;
  set challenge(String? challenge) => _$this._challenge = challenge;

  String? _signature;
  String? get signature => _$this._signature;
  set signature(String? signature) => _$this._signature = signature;

  String? _deviceName;
  String? get deviceName => _$this._deviceName;
  set deviceName(String? deviceName) => _$this._deviceName = deviceName;

  LocalLoginRequestBuilder() {
    LocalLoginRequest._defaults(this);
  }

  LocalLoginRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _challenge = $v.challenge;
      _signature = $v.signature;
      _deviceName = $v.deviceName;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(LocalLoginRequest other) {
    _$v = other as _$LocalLoginRequest;
  }

  @override
  void update(void Function(LocalLoginRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  LocalLoginRequest build() => _build();

  _$LocalLoginRequest _build() {
    final _$result = _$v ??
        _$LocalLoginRequest._(
          challenge: BuiltValueNullFieldError.checkNotNull(
              challenge, r'LocalLoginRequest', 'challenge'),
          signature: BuiltValueNullFieldError.checkNotNull(
              signature, r'LocalLoginRequest', 'signature'),
          deviceName: deviceName,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
