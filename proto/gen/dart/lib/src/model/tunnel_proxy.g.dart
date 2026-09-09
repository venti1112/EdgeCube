// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tunnel_proxy.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$TunnelProxy extends TunnelProxy {
  @override
  final String name;
  @override
  final ProxyType type;
  @override
  final String localIp;
  @override
  final int localPort;
  @override
  final int? remotePort;
  @override
  final BuiltList<String>? customDomains;

  factory _$TunnelProxy([void Function(TunnelProxyBuilder)? updates]) =>
      (TunnelProxyBuilder()..update(updates))._build();

  _$TunnelProxy._(
      {required this.name,
      required this.type,
      required this.localIp,
      required this.localPort,
      this.remotePort,
      this.customDomains})
      : super._();
  @override
  TunnelProxy rebuild(void Function(TunnelProxyBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  TunnelProxyBuilder toBuilder() => TunnelProxyBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is TunnelProxy &&
        name == other.name &&
        type == other.type &&
        localIp == other.localIp &&
        localPort == other.localPort &&
        remotePort == other.remotePort &&
        customDomains == other.customDomains;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, type.hashCode);
    _$hash = $jc(_$hash, localIp.hashCode);
    _$hash = $jc(_$hash, localPort.hashCode);
    _$hash = $jc(_$hash, remotePort.hashCode);
    _$hash = $jc(_$hash, customDomains.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'TunnelProxy')
          ..add('name', name)
          ..add('type', type)
          ..add('localIp', localIp)
          ..add('localPort', localPort)
          ..add('remotePort', remotePort)
          ..add('customDomains', customDomains))
        .toString();
  }
}

class TunnelProxyBuilder implements Builder<TunnelProxy, TunnelProxyBuilder> {
  _$TunnelProxy? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  ProxyType? _type;
  ProxyType? get type => _$this._type;
  set type(ProxyType? type) => _$this._type = type;

  String? _localIp;
  String? get localIp => _$this._localIp;
  set localIp(String? localIp) => _$this._localIp = localIp;

  int? _localPort;
  int? get localPort => _$this._localPort;
  set localPort(int? localPort) => _$this._localPort = localPort;

  int? _remotePort;
  int? get remotePort => _$this._remotePort;
  set remotePort(int? remotePort) => _$this._remotePort = remotePort;

  ListBuilder<String>? _customDomains;
  ListBuilder<String> get customDomains =>
      _$this._customDomains ??= ListBuilder<String>();
  set customDomains(ListBuilder<String>? customDomains) =>
      _$this._customDomains = customDomains;

  TunnelProxyBuilder() {
    TunnelProxy._defaults(this);
  }

  TunnelProxyBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _type = $v.type;
      _localIp = $v.localIp;
      _localPort = $v.localPort;
      _remotePort = $v.remotePort;
      _customDomains = $v.customDomains?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(TunnelProxy other) {
    _$v = other as _$TunnelProxy;
  }

  @override
  void update(void Function(TunnelProxyBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  TunnelProxy build() => _build();

  _$TunnelProxy _build() {
    _$TunnelProxy _$result;
    try {
      _$result = _$v ??
          _$TunnelProxy._(
            name: BuiltValueNullFieldError.checkNotNull(
                name, r'TunnelProxy', 'name'),
            type: BuiltValueNullFieldError.checkNotNull(
                type, r'TunnelProxy', 'type'),
            localIp: BuiltValueNullFieldError.checkNotNull(
                localIp, r'TunnelProxy', 'localIp'),
            localPort: BuiltValueNullFieldError.checkNotNull(
                localPort, r'TunnelProxy', 'localPort'),
            remotePort: remotePort,
            customDomains: _customDomains?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'customDomains';
        _customDomains?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'TunnelProxy', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
