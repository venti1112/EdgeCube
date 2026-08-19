// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'instance_detail.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$InstanceDetail extends InstanceDetail {
  @override
  final InstanceConfig config;
  @override
  final RunStatus status;

  factory _$InstanceDetail([void Function(InstanceDetailBuilder)? updates]) =>
      (InstanceDetailBuilder()..update(updates))._build();

  _$InstanceDetail._({required this.config, required this.status}) : super._();
  @override
  InstanceDetail rebuild(void Function(InstanceDetailBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  InstanceDetailBuilder toBuilder() => InstanceDetailBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is InstanceDetail &&
        config == other.config &&
        status == other.status;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, config.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'InstanceDetail')
          ..add('config', config)
          ..add('status', status))
        .toString();
  }
}

class InstanceDetailBuilder
    implements Builder<InstanceDetail, InstanceDetailBuilder> {
  _$InstanceDetail? _$v;

  InstanceConfigBuilder? _config;
  InstanceConfigBuilder get config =>
      _$this._config ??= InstanceConfigBuilder();
  set config(InstanceConfigBuilder? config) => _$this._config = config;

  RunStatusBuilder? _status;
  RunStatusBuilder get status => _$this._status ??= RunStatusBuilder();
  set status(RunStatusBuilder? status) => _$this._status = status;

  InstanceDetailBuilder() {
    InstanceDetail._defaults(this);
  }

  InstanceDetailBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _config = $v.config.toBuilder();
      _status = $v.status.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(InstanceDetail other) {
    _$v = other as _$InstanceDetail;
  }

  @override
  void update(void Function(InstanceDetailBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  InstanceDetail build() => _build();

  _$InstanceDetail _build() {
    _$InstanceDetail _$result;
    try {
      _$result = _$v ??
          _$InstanceDetail._(
            config: config.build(),
            status: status.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'config';
        config.build();
        _$failedField = 'status';
        status.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'InstanceDetail', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
