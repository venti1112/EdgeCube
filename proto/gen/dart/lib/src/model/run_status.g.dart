// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'run_status.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RunStatus extends RunStatus {
  @override
  final InstanceStatus status;
  @override
  final int? pid;
  @override
  final int? exitCode;
  @override
  final int? serverPort;
  @override
  final bool? onlineMode;
  @override
  final BuiltList<String>? onlinePlayers;
  @override
  final int? logSeq;

  factory _$RunStatus([void Function(RunStatusBuilder)? updates]) =>
      (RunStatusBuilder()..update(updates))._build();

  _$RunStatus._(
      {required this.status,
      this.pid,
      this.exitCode,
      this.serverPort,
      this.onlineMode,
      this.onlinePlayers,
      this.logSeq})
      : super._();
  @override
  RunStatus rebuild(void Function(RunStatusBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RunStatusBuilder toBuilder() => RunStatusBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RunStatus &&
        status == other.status &&
        pid == other.pid &&
        exitCode == other.exitCode &&
        serverPort == other.serverPort &&
        onlineMode == other.onlineMode &&
        onlinePlayers == other.onlinePlayers &&
        logSeq == other.logSeq;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, exitCode.hashCode);
    _$hash = $jc(_$hash, serverPort.hashCode);
    _$hash = $jc(_$hash, onlineMode.hashCode);
    _$hash = $jc(_$hash, onlinePlayers.hashCode);
    _$hash = $jc(_$hash, logSeq.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RunStatus')
          ..add('status', status)
          ..add('pid', pid)
          ..add('exitCode', exitCode)
          ..add('serverPort', serverPort)
          ..add('onlineMode', onlineMode)
          ..add('onlinePlayers', onlinePlayers)
          ..add('logSeq', logSeq))
        .toString();
  }
}

class RunStatusBuilder implements Builder<RunStatus, RunStatusBuilder> {
  _$RunStatus? _$v;

  InstanceStatus? _status;
  InstanceStatus? get status => _$this._status;
  set status(InstanceStatus? status) => _$this._status = status;

  int? _pid;
  int? get pid => _$this._pid;
  set pid(int? pid) => _$this._pid = pid;

  int? _exitCode;
  int? get exitCode => _$this._exitCode;
  set exitCode(int? exitCode) => _$this._exitCode = exitCode;

  int? _serverPort;
  int? get serverPort => _$this._serverPort;
  set serverPort(int? serverPort) => _$this._serverPort = serverPort;

  bool? _onlineMode;
  bool? get onlineMode => _$this._onlineMode;
  set onlineMode(bool? onlineMode) => _$this._onlineMode = onlineMode;

  ListBuilder<String>? _onlinePlayers;
  ListBuilder<String> get onlinePlayers =>
      _$this._onlinePlayers ??= ListBuilder<String>();
  set onlinePlayers(ListBuilder<String>? onlinePlayers) =>
      _$this._onlinePlayers = onlinePlayers;

  int? _logSeq;
  int? get logSeq => _$this._logSeq;
  set logSeq(int? logSeq) => _$this._logSeq = logSeq;

  RunStatusBuilder() {
    RunStatus._defaults(this);
  }

  RunStatusBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _status = $v.status;
      _pid = $v.pid;
      _exitCode = $v.exitCode;
      _serverPort = $v.serverPort;
      _onlineMode = $v.onlineMode;
      _onlinePlayers = $v.onlinePlayers?.toBuilder();
      _logSeq = $v.logSeq;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RunStatus other) {
    _$v = other as _$RunStatus;
  }

  @override
  void update(void Function(RunStatusBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RunStatus build() => _build();

  _$RunStatus _build() {
    _$RunStatus _$result;
    try {
      _$result = _$v ??
          _$RunStatus._(
            status: BuiltValueNullFieldError.checkNotNull(
                status, r'RunStatus', 'status'),
            pid: pid,
            exitCode: exitCode,
            serverPort: serverPort,
            onlineMode: onlineMode,
            onlinePlayers: _onlinePlayers?.build(),
            logSeq: logSeq,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'onlinePlayers';
        _onlinePlayers?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'RunStatus', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
