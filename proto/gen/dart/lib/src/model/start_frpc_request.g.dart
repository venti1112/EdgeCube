// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'start_frpc_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$StartFrpcRequest extends StartFrpcRequest {
  @override
  final String tunnelId;

  factory _$StartFrpcRequest(
          [void Function(StartFrpcRequestBuilder)? updates]) =>
      (StartFrpcRequestBuilder()..update(updates))._build();

  _$StartFrpcRequest._({required this.tunnelId}) : super._();
  @override
  StartFrpcRequest rebuild(void Function(StartFrpcRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  StartFrpcRequestBuilder toBuilder() =>
      StartFrpcRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is StartFrpcRequest && tunnelId == other.tunnelId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, tunnelId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'StartFrpcRequest')
          ..add('tunnelId', tunnelId))
        .toString();
  }
}

class StartFrpcRequestBuilder
    implements Builder<StartFrpcRequest, StartFrpcRequestBuilder> {
  _$StartFrpcRequest? _$v;

  String? _tunnelId;
  String? get tunnelId => _$this._tunnelId;
  set tunnelId(String? tunnelId) => _$this._tunnelId = tunnelId;

  StartFrpcRequestBuilder() {
    StartFrpcRequest._defaults(this);
  }

  StartFrpcRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _tunnelId = $v.tunnelId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(StartFrpcRequest other) {
    _$v = other as _$StartFrpcRequest;
  }

  @override
  void update(void Function(StartFrpcRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  StartFrpcRequest build() => _build();

  _$StartFrpcRequest _build() {
    final _$result = _$v ??
        _$StartFrpcRequest._(
          tunnelId: BuiltValueNullFieldError.checkNotNull(
              tunnelId, r'StartFrpcRequest', 'tunnelId'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
