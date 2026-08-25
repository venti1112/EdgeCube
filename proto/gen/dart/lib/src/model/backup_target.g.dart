// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'backup_target.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$BackupTarget extends BackupTarget {
  @override
  final String id;
  @override
  final String name;
  @override
  final BackupTargetType type;
  @override
  final String? host;
  @override
  final int? port;
  @override
  final String? username;
  @override
  final String path;
  @override
  final String? encryptedPassword;
  @override
  final DateTime? createdAt;

  factory _$BackupTarget([void Function(BackupTargetBuilder)? updates]) =>
      (BackupTargetBuilder()..update(updates))._build();

  _$BackupTarget._(
      {required this.id,
      required this.name,
      required this.type,
      this.host,
      this.port,
      this.username,
      required this.path,
      this.encryptedPassword,
      this.createdAt})
      : super._();
  @override
  BackupTarget rebuild(void Function(BackupTargetBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BackupTargetBuilder toBuilder() => BackupTargetBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BackupTarget &&
        id == other.id &&
        name == other.name &&
        type == other.type &&
        host == other.host &&
        port == other.port &&
        username == other.username &&
        path == other.path &&
        encryptedPassword == other.encryptedPassword &&
        createdAt == other.createdAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, type.hashCode);
    _$hash = $jc(_$hash, host.hashCode);
    _$hash = $jc(_$hash, port.hashCode);
    _$hash = $jc(_$hash, username.hashCode);
    _$hash = $jc(_$hash, path.hashCode);
    _$hash = $jc(_$hash, encryptedPassword.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BackupTarget')
          ..add('id', id)
          ..add('name', name)
          ..add('type', type)
          ..add('host', host)
          ..add('port', port)
          ..add('username', username)
          ..add('path', path)
          ..add('encryptedPassword', encryptedPassword)
          ..add('createdAt', createdAt))
        .toString();
  }
}

class BackupTargetBuilder
    implements Builder<BackupTarget, BackupTargetBuilder> {
  _$BackupTarget? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  BackupTargetType? _type;
  BackupTargetType? get type => _$this._type;
  set type(BackupTargetType? type) => _$this._type = type;

  String? _host;
  String? get host => _$this._host;
  set host(String? host) => _$this._host = host;

  int? _port;
  int? get port => _$this._port;
  set port(int? port) => _$this._port = port;

  String? _username;
  String? get username => _$this._username;
  set username(String? username) => _$this._username = username;

  String? _path;
  String? get path => _$this._path;
  set path(String? path) => _$this._path = path;

  String? _encryptedPassword;
  String? get encryptedPassword => _$this._encryptedPassword;
  set encryptedPassword(String? encryptedPassword) =>
      _$this._encryptedPassword = encryptedPassword;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  BackupTargetBuilder() {
    BackupTarget._defaults(this);
  }

  BackupTargetBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _name = $v.name;
      _type = $v.type;
      _host = $v.host;
      _port = $v.port;
      _username = $v.username;
      _path = $v.path;
      _encryptedPassword = $v.encryptedPassword;
      _createdAt = $v.createdAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BackupTarget other) {
    _$v = other as _$BackupTarget;
  }

  @override
  void update(void Function(BackupTargetBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BackupTarget build() => _build();

  _$BackupTarget _build() {
    final _$result = _$v ??
        _$BackupTarget._(
          id: BuiltValueNullFieldError.checkNotNull(id, r'BackupTarget', 'id'),
          name: BuiltValueNullFieldError.checkNotNull(
              name, r'BackupTarget', 'name'),
          type: BuiltValueNullFieldError.checkNotNull(
              type, r'BackupTarget', 'type'),
          host: host,
          port: port,
          username: username,
          path: BuiltValueNullFieldError.checkNotNull(
              path, r'BackupTarget', 'path'),
          encryptedPassword: encryptedPassword,
          createdAt: createdAt,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
