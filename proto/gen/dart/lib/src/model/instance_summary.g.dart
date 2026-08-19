// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'instance_summary.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$InstanceSummary extends InstanceSummary {
  @override
  final String id;
  @override
  final String name;
  @override
  final InstanceStatus status;
  @override
  final InstanceType type;
  @override
  final int? pid;
  @override
  final DateTime? runningSince;
  @override
  final bool? autoRestart;
  @override
  final bool? autoStartOnBoot;
  @override
  final int? port;
  @override
  final int? onlinePlayers;

  factory _$InstanceSummary([void Function(InstanceSummaryBuilder)? updates]) =>
      (InstanceSummaryBuilder()..update(updates))._build();

  _$InstanceSummary._(
      {required this.id,
      required this.name,
      required this.status,
      required this.type,
      this.pid,
      this.runningSince,
      this.autoRestart,
      this.autoStartOnBoot,
      this.port,
      this.onlinePlayers})
      : super._();
  @override
  InstanceSummary rebuild(void Function(InstanceSummaryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  InstanceSummaryBuilder toBuilder() => InstanceSummaryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is InstanceSummary &&
        id == other.id &&
        name == other.name &&
        status == other.status &&
        type == other.type &&
        pid == other.pid &&
        runningSince == other.runningSince &&
        autoRestart == other.autoRestart &&
        autoStartOnBoot == other.autoStartOnBoot &&
        port == other.port &&
        onlinePlayers == other.onlinePlayers;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jc(_$hash, type.hashCode);
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, runningSince.hashCode);
    _$hash = $jc(_$hash, autoRestart.hashCode);
    _$hash = $jc(_$hash, autoStartOnBoot.hashCode);
    _$hash = $jc(_$hash, port.hashCode);
    _$hash = $jc(_$hash, onlinePlayers.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'InstanceSummary')
          ..add('id', id)
          ..add('name', name)
          ..add('status', status)
          ..add('type', type)
          ..add('pid', pid)
          ..add('runningSince', runningSince)
          ..add('autoRestart', autoRestart)
          ..add('autoStartOnBoot', autoStartOnBoot)
          ..add('port', port)
          ..add('onlinePlayers', onlinePlayers))
        .toString();
  }
}

class InstanceSummaryBuilder
    implements Builder<InstanceSummary, InstanceSummaryBuilder> {
  _$InstanceSummary? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  InstanceStatus? _status;
  InstanceStatus? get status => _$this._status;
  set status(InstanceStatus? status) => _$this._status = status;

  InstanceType? _type;
  InstanceType? get type => _$this._type;
  set type(InstanceType? type) => _$this._type = type;

  int? _pid;
  int? get pid => _$this._pid;
  set pid(int? pid) => _$this._pid = pid;

  DateTime? _runningSince;
  DateTime? get runningSince => _$this._runningSince;
  set runningSince(DateTime? runningSince) =>
      _$this._runningSince = runningSince;

  bool? _autoRestart;
  bool? get autoRestart => _$this._autoRestart;
  set autoRestart(bool? autoRestart) => _$this._autoRestart = autoRestart;

  bool? _autoStartOnBoot;
  bool? get autoStartOnBoot => _$this._autoStartOnBoot;
  set autoStartOnBoot(bool? autoStartOnBoot) =>
      _$this._autoStartOnBoot = autoStartOnBoot;

  int? _port;
  int? get port => _$this._port;
  set port(int? port) => _$this._port = port;

  int? _onlinePlayers;
  int? get onlinePlayers => _$this._onlinePlayers;
  set onlinePlayers(int? onlinePlayers) =>
      _$this._onlinePlayers = onlinePlayers;

  InstanceSummaryBuilder() {
    InstanceSummary._defaults(this);
  }

  InstanceSummaryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _name = $v.name;
      _status = $v.status;
      _type = $v.type;
      _pid = $v.pid;
      _runningSince = $v.runningSince;
      _autoRestart = $v.autoRestart;
      _autoStartOnBoot = $v.autoStartOnBoot;
      _port = $v.port;
      _onlinePlayers = $v.onlinePlayers;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(InstanceSummary other) {
    _$v = other as _$InstanceSummary;
  }

  @override
  void update(void Function(InstanceSummaryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  InstanceSummary build() => _build();

  _$InstanceSummary _build() {
    final _$result = _$v ??
        _$InstanceSummary._(
          id: BuiltValueNullFieldError.checkNotNull(
              id, r'InstanceSummary', 'id'),
          name: BuiltValueNullFieldError.checkNotNull(
              name, r'InstanceSummary', 'name'),
          status: BuiltValueNullFieldError.checkNotNull(
              status, r'InstanceSummary', 'status'),
          type: BuiltValueNullFieldError.checkNotNull(
              type, r'InstanceSummary', 'type'),
          pid: pid,
          runningSince: runningSince,
          autoRestart: autoRestart,
          autoStartOnBoot: autoStartOnBoot,
          port: port,
          onlinePlayers: onlinePlayers,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
