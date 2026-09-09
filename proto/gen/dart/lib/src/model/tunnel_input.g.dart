// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tunnel_input.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$TunnelInput extends TunnelInput {
  @override
  final String name;
  @override
  final String serverAddr;
  @override
  final int serverPort;
  @override
  final String? user;
  @override
  final String? authToken;
  @override
  final BuiltList<TunnelProxy> proxies;

  factory _$TunnelInput([void Function(TunnelInputBuilder)? updates]) =>
      (TunnelInputBuilder()..update(updates))._build();

  _$TunnelInput._(
      {required this.name,
      required this.serverAddr,
      required this.serverPort,
      this.user,
      this.authToken,
      required this.proxies})
      : super._();
  @override
  TunnelInput rebuild(void Function(TunnelInputBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  TunnelInputBuilder toBuilder() => TunnelInputBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is TunnelInput &&
        name == other.name &&
        serverAddr == other.serverAddr &&
        serverPort == other.serverPort &&
        user == other.user &&
        authToken == other.authToken &&
        proxies == other.proxies;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, serverAddr.hashCode);
    _$hash = $jc(_$hash, serverPort.hashCode);
    _$hash = $jc(_$hash, user.hashCode);
    _$hash = $jc(_$hash, authToken.hashCode);
    _$hash = $jc(_$hash, proxies.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'TunnelInput')
          ..add('name', name)
          ..add('serverAddr', serverAddr)
          ..add('serverPort', serverPort)
          ..add('user', user)
          ..add('authToken', authToken)
          ..add('proxies', proxies))
        .toString();
  }
}

class TunnelInputBuilder implements Builder<TunnelInput, TunnelInputBuilder> {
  _$TunnelInput? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _serverAddr;
  String? get serverAddr => _$this._serverAddr;
  set serverAddr(String? serverAddr) => _$this._serverAddr = serverAddr;

  int? _serverPort;
  int? get serverPort => _$this._serverPort;
  set serverPort(int? serverPort) => _$this._serverPort = serverPort;

  String? _user;
  String? get user => _$this._user;
  set user(String? user) => _$this._user = user;

  String? _authToken;
  String? get authToken => _$this._authToken;
  set authToken(String? authToken) => _$this._authToken = authToken;

  ListBuilder<TunnelProxy>? _proxies;
  ListBuilder<TunnelProxy> get proxies =>
      _$this._proxies ??= ListBuilder<TunnelProxy>();
  set proxies(ListBuilder<TunnelProxy>? proxies) => _$this._proxies = proxies;

  TunnelInputBuilder() {
    TunnelInput._defaults(this);
  }

  TunnelInputBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _serverAddr = $v.serverAddr;
      _serverPort = $v.serverPort;
      _user = $v.user;
      _authToken = $v.authToken;
      _proxies = $v.proxies.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(TunnelInput other) {
    _$v = other as _$TunnelInput;
  }

  @override
  void update(void Function(TunnelInputBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  TunnelInput build() => _build();

  _$TunnelInput _build() {
    _$TunnelInput _$result;
    try {
      _$result = _$v ??
          _$TunnelInput._(
            name: BuiltValueNullFieldError.checkNotNull(
                name, r'TunnelInput', 'name'),
            serverAddr: BuiltValueNullFieldError.checkNotNull(
                serverAddr, r'TunnelInput', 'serverAddr'),
            serverPort: BuiltValueNullFieldError.checkNotNull(
                serverPort, r'TunnelInput', 'serverPort'),
            user: user,
            authToken: authToken,
            proxies: proxies.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'proxies';
        proxies.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'TunnelInput', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
