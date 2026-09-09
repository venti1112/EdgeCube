// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tunnel_info.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$TunnelInfo extends TunnelInfo {
  @override
  final String id;
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
  @override
  final DateTime createdAt;
  @override
  final DateTime updatedAt;

  factory _$TunnelInfo([void Function(TunnelInfoBuilder)? updates]) =>
      (TunnelInfoBuilder()..update(updates))._build();

  _$TunnelInfo._(
      {required this.id,
      required this.name,
      required this.serverAddr,
      required this.serverPort,
      this.user,
      this.authToken,
      required this.proxies,
      required this.createdAt,
      required this.updatedAt})
      : super._();
  @override
  TunnelInfo rebuild(void Function(TunnelInfoBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  TunnelInfoBuilder toBuilder() => TunnelInfoBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is TunnelInfo &&
        id == other.id &&
        name == other.name &&
        serverAddr == other.serverAddr &&
        serverPort == other.serverPort &&
        user == other.user &&
        authToken == other.authToken &&
        proxies == other.proxies &&
        createdAt == other.createdAt &&
        updatedAt == other.updatedAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, serverAddr.hashCode);
    _$hash = $jc(_$hash, serverPort.hashCode);
    _$hash = $jc(_$hash, user.hashCode);
    _$hash = $jc(_$hash, authToken.hashCode);
    _$hash = $jc(_$hash, proxies.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'TunnelInfo')
          ..add('id', id)
          ..add('name', name)
          ..add('serverAddr', serverAddr)
          ..add('serverPort', serverPort)
          ..add('user', user)
          ..add('authToken', authToken)
          ..add('proxies', proxies)
          ..add('createdAt', createdAt)
          ..add('updatedAt', updatedAt))
        .toString();
  }
}

class TunnelInfoBuilder implements Builder<TunnelInfo, TunnelInfoBuilder> {
  _$TunnelInfo? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

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

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  DateTime? _updatedAt;
  DateTime? get updatedAt => _$this._updatedAt;
  set updatedAt(DateTime? updatedAt) => _$this._updatedAt = updatedAt;

  TunnelInfoBuilder() {
    TunnelInfo._defaults(this);
  }

  TunnelInfoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _name = $v.name;
      _serverAddr = $v.serverAddr;
      _serverPort = $v.serverPort;
      _user = $v.user;
      _authToken = $v.authToken;
      _proxies = $v.proxies.toBuilder();
      _createdAt = $v.createdAt;
      _updatedAt = $v.updatedAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(TunnelInfo other) {
    _$v = other as _$TunnelInfo;
  }

  @override
  void update(void Function(TunnelInfoBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  TunnelInfo build() => _build();

  _$TunnelInfo _build() {
    _$TunnelInfo _$result;
    try {
      _$result = _$v ??
          _$TunnelInfo._(
            id: BuiltValueNullFieldError.checkNotNull(id, r'TunnelInfo', 'id'),
            name: BuiltValueNullFieldError.checkNotNull(
                name, r'TunnelInfo', 'name'),
            serverAddr: BuiltValueNullFieldError.checkNotNull(
                serverAddr, r'TunnelInfo', 'serverAddr'),
            serverPort: BuiltValueNullFieldError.checkNotNull(
                serverPort, r'TunnelInfo', 'serverPort'),
            user: user,
            authToken: authToken,
            proxies: proxies.build(),
            createdAt: BuiltValueNullFieldError.checkNotNull(
                createdAt, r'TunnelInfo', 'createdAt'),
            updatedAt: BuiltValueNullFieldError.checkNotNull(
                updatedAt, r'TunnelInfo', 'updatedAt'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'proxies';
        proxies.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'TunnelInfo', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
