// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ftp_status.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$FtpStatus extends FtpStatus {
  @override
  final bool? running;
  @override
  final int? connections;
  @override
  final bool enabled;
  @override
  final int port;
  @override
  final String username;
  @override
  final String? password;
  @override
  final String? rootDir;

  factory _$FtpStatus([void Function(FtpStatusBuilder)? updates]) =>
      (FtpStatusBuilder()..update(updates))._build();

  _$FtpStatus._(
      {this.running,
      this.connections,
      required this.enabled,
      required this.port,
      required this.username,
      this.password,
      this.rootDir})
      : super._();
  @override
  FtpStatus rebuild(void Function(FtpStatusBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  FtpStatusBuilder toBuilder() => FtpStatusBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is FtpStatus &&
        running == other.running &&
        connections == other.connections &&
        enabled == other.enabled &&
        port == other.port &&
        username == other.username &&
        password == other.password &&
        rootDir == other.rootDir;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, running.hashCode);
    _$hash = $jc(_$hash, connections.hashCode);
    _$hash = $jc(_$hash, enabled.hashCode);
    _$hash = $jc(_$hash, port.hashCode);
    _$hash = $jc(_$hash, username.hashCode);
    _$hash = $jc(_$hash, password.hashCode);
    _$hash = $jc(_$hash, rootDir.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'FtpStatus')
          ..add('running', running)
          ..add('connections', connections)
          ..add('enabled', enabled)
          ..add('port', port)
          ..add('username', username)
          ..add('password', password)
          ..add('rootDir', rootDir))
        .toString();
  }
}

class FtpStatusBuilder
    implements Builder<FtpStatus, FtpStatusBuilder>, FtpConfigBuilder {
  _$FtpStatus? _$v;

  bool? _running;
  bool? get running => _$this._running;
  set running(covariant bool? running) => _$this._running = running;

  int? _connections;
  int? get connections => _$this._connections;
  set connections(covariant int? connections) =>
      _$this._connections = connections;

  bool? _enabled;
  bool? get enabled => _$this._enabled;
  set enabled(covariant bool? enabled) => _$this._enabled = enabled;

  int? _port;
  int? get port => _$this._port;
  set port(covariant int? port) => _$this._port = port;

  String? _username;
  String? get username => _$this._username;
  set username(covariant String? username) => _$this._username = username;

  String? _password;
  String? get password => _$this._password;
  set password(covariant String? password) => _$this._password = password;

  String? _rootDir;
  String? get rootDir => _$this._rootDir;
  set rootDir(covariant String? rootDir) => _$this._rootDir = rootDir;

  FtpStatusBuilder() {
    FtpStatus._defaults(this);
  }

  FtpStatusBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _running = $v.running;
      _connections = $v.connections;
      _enabled = $v.enabled;
      _port = $v.port;
      _username = $v.username;
      _password = $v.password;
      _rootDir = $v.rootDir;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(covariant FtpStatus other) {
    _$v = other as _$FtpStatus;
  }

  @override
  void update(void Function(FtpStatusBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  FtpStatus build() => _build();

  _$FtpStatus _build() {
    final _$result = _$v ??
        _$FtpStatus._(
          running: running,
          connections: connections,
          enabled: BuiltValueNullFieldError.checkNotNull(
              enabled, r'FtpStatus', 'enabled'),
          port:
              BuiltValueNullFieldError.checkNotNull(port, r'FtpStatus', 'port'),
          username: BuiltValueNullFieldError.checkNotNull(
              username, r'FtpStatus', 'username'),
          password: password,
          rootDir: rootDir,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
