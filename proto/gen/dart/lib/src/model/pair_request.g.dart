// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pair_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PairRequest extends PairRequest {
  @override
  final String code;
  @override
  final String deviceName;

  factory _$PairRequest([void Function(PairRequestBuilder)? updates]) =>
      (PairRequestBuilder()..update(updates))._build();

  _$PairRequest._({required this.code, required this.deviceName}) : super._();
  @override
  PairRequest rebuild(void Function(PairRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PairRequestBuilder toBuilder() => PairRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PairRequest &&
        code == other.code &&
        deviceName == other.deviceName;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, code.hashCode);
    _$hash = $jc(_$hash, deviceName.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PairRequest')
          ..add('code', code)
          ..add('deviceName', deviceName))
        .toString();
  }
}

class PairRequestBuilder implements Builder<PairRequest, PairRequestBuilder> {
  _$PairRequest? _$v;

  String? _code;
  String? get code => _$this._code;
  set code(String? code) => _$this._code = code;

  String? _deviceName;
  String? get deviceName => _$this._deviceName;
  set deviceName(String? deviceName) => _$this._deviceName = deviceName;

  PairRequestBuilder() {
    PairRequest._defaults(this);
  }

  PairRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _code = $v.code;
      _deviceName = $v.deviceName;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PairRequest other) {
    _$v = other as _$PairRequest;
  }

  @override
  void update(void Function(PairRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PairRequest build() => _build();

  _$PairRequest _build() {
    final _$result = _$v ??
        _$PairRequest._(
          code: BuiltValueNullFieldError.checkNotNull(
              code, r'PairRequest', 'code'),
          deviceName: BuiltValueNullFieldError.checkNotNull(
              deviceName, r'PairRequest', 'deviceName'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
