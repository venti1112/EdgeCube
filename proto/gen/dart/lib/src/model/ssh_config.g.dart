// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ssh_config.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

abstract class SshConfigBuilder {
  void replace(SshConfig other);
  void update(void Function(SshConfigBuilder) updates);
  bool? get enabled;
  set enabled(bool? enabled);

  int? get port;
  set port(int? port);

  String? get username;
  set username(String? username);

  String? get password;
  set password(String? password);

  String? get rootDir;
  set rootDir(String? rootDir);
}

class _$$SshConfig extends $SshConfig {
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

  factory _$$SshConfig([void Function($SshConfigBuilder)? updates]) =>
      ($SshConfigBuilder()..update(updates))._build();

  _$$SshConfig._(
      {required this.enabled,
      required this.port,
      required this.username,
      this.password,
      this.rootDir})
      : super._();
  @override
  $SshConfig rebuild(void Function($SshConfigBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  $SshConfigBuilder toBuilder() => $SshConfigBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is $SshConfig &&
        enabled == other.enabled &&
        port == other.port &&
        username == other.username &&
        password == other.password &&
        rootDir == other.rootDir;
  }

  @override
  int get hashCode {
    var _$hash = 0;
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
    return (newBuiltValueToStringHelper(r'$SshConfig')
          ..add('enabled', enabled)
          ..add('port', port)
          ..add('username', username)
          ..add('password', password)
          ..add('rootDir', rootDir))
        .toString();
  }
}

class $SshConfigBuilder
    implements Builder<$SshConfig, $SshConfigBuilder>, SshConfigBuilder {
  _$$SshConfig? _$v;

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

  $SshConfigBuilder() {
    $SshConfig._defaults(this);
  }

  $SshConfigBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
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
  void replace(covariant $SshConfig other) {
    _$v = other as _$$SshConfig;
  }

  @override
  void update(void Function($SshConfigBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  $SshConfig build() => _build();

  _$$SshConfig _build() {
    final _$result = _$v ??
        _$$SshConfig._(
          enabled: BuiltValueNullFieldError.checkNotNull(
              enabled, r'$SshConfig', 'enabled'),
          port: BuiltValueNullFieldError.checkNotNull(
              port, r'$SshConfig', 'port'),
          username: BuiltValueNullFieldError.checkNotNull(
              username, r'$SshConfig', 'username'),
          password: password,
          rootDir: rootDir,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
