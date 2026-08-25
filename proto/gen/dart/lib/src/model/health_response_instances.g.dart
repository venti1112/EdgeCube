// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'health_response_instances.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$HealthResponseInstances extends HealthResponseInstances {
  @override
  final int? running;
  @override
  final int? total;

  factory _$HealthResponseInstances(
          [void Function(HealthResponseInstancesBuilder)? updates]) =>
      (HealthResponseInstancesBuilder()..update(updates))._build();

  _$HealthResponseInstances._({this.running, this.total}) : super._();
  @override
  HealthResponseInstances rebuild(
          void Function(HealthResponseInstancesBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  HealthResponseInstancesBuilder toBuilder() =>
      HealthResponseInstancesBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is HealthResponseInstances &&
        running == other.running &&
        total == other.total;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, running.hashCode);
    _$hash = $jc(_$hash, total.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'HealthResponseInstances')
          ..add('running', running)
          ..add('total', total))
        .toString();
  }
}

class HealthResponseInstancesBuilder
    implements
        Builder<HealthResponseInstances, HealthResponseInstancesBuilder> {
  _$HealthResponseInstances? _$v;

  int? _running;
  int? get running => _$this._running;
  set running(int? running) => _$this._running = running;

  int? _total;
  int? get total => _$this._total;
  set total(int? total) => _$this._total = total;

  HealthResponseInstancesBuilder() {
    HealthResponseInstances._defaults(this);
  }

  HealthResponseInstancesBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _running = $v.running;
      _total = $v.total;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(HealthResponseInstances other) {
    _$v = other as _$HealthResponseInstances;
  }

  @override
  void update(void Function(HealthResponseInstancesBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  HealthResponseInstances build() => _build();

  _$HealthResponseInstances _build() {
    final _$result = _$v ??
        _$HealthResponseInstances._(
          running: running,
          total: total,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
