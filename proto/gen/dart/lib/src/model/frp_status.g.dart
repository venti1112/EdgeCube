// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'frp_status.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$FrpStatus extends FrpStatus {
  @override
  final bool running;
  @override
  final String? tunnelId;
  @override
  final DateTime? startedAt;
  @override
  final int? exitCode;

  factory _$FrpStatus([void Function(FrpStatusBuilder)? updates]) =>
      (FrpStatusBuilder()..update(updates))._build();

  _$FrpStatus._(
      {required this.running, this.tunnelId, this.startedAt, this.exitCode})
      : super._();
  @override
  FrpStatus rebuild(void Function(FrpStatusBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  FrpStatusBuilder toBuilder() => FrpStatusBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is FrpStatus &&
        running == other.running &&
        tunnelId == other.tunnelId &&
        startedAt == other.startedAt &&
        exitCode == other.exitCode;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, running.hashCode);
    _$hash = $jc(_$hash, tunnelId.hashCode);
    _$hash = $jc(_$hash, startedAt.hashCode);
    _$hash = $jc(_$hash, exitCode.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'FrpStatus')
          ..add('running', running)
          ..add('tunnelId', tunnelId)
          ..add('startedAt', startedAt)
          ..add('exitCode', exitCode))
        .toString();
  }
}

class FrpStatusBuilder implements Builder<FrpStatus, FrpStatusBuilder> {
  _$FrpStatus? _$v;

  bool? _running;
  bool? get running => _$this._running;
  set running(bool? running) => _$this._running = running;

  String? _tunnelId;
  String? get tunnelId => _$this._tunnelId;
  set tunnelId(String? tunnelId) => _$this._tunnelId = tunnelId;

  DateTime? _startedAt;
  DateTime? get startedAt => _$this._startedAt;
  set startedAt(DateTime? startedAt) => _$this._startedAt = startedAt;

  int? _exitCode;
  int? get exitCode => _$this._exitCode;
  set exitCode(int? exitCode) => _$this._exitCode = exitCode;

  FrpStatusBuilder() {
    FrpStatus._defaults(this);
  }

  FrpStatusBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _running = $v.running;
      _tunnelId = $v.tunnelId;
      _startedAt = $v.startedAt;
      _exitCode = $v.exitCode;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(FrpStatus other) {
    _$v = other as _$FrpStatus;
  }

  @override
  void update(void Function(FrpStatusBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  FrpStatus build() => _build();

  _$FrpStatus _build() {
    final _$result = _$v ??
        _$FrpStatus._(
          running: BuiltValueNullFieldError.checkNotNull(
              running, r'FrpStatus', 'running'),
          tunnelId: tunnelId,
          startedAt: startedAt,
          exitCode: exitCode,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
