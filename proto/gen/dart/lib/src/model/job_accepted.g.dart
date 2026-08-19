// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'job_accepted.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$JobAccepted extends JobAccepted {
  @override
  final String jobId;

  factory _$JobAccepted([void Function(JobAcceptedBuilder)? updates]) =>
      (JobAcceptedBuilder()..update(updates))._build();

  _$JobAccepted._({required this.jobId}) : super._();
  @override
  JobAccepted rebuild(void Function(JobAcceptedBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  JobAcceptedBuilder toBuilder() => JobAcceptedBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is JobAccepted && jobId == other.jobId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, jobId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'JobAccepted')..add('jobId', jobId))
        .toString();
  }
}

class JobAcceptedBuilder implements Builder<JobAccepted, JobAcceptedBuilder> {
  _$JobAccepted? _$v;

  String? _jobId;
  String? get jobId => _$this._jobId;
  set jobId(String? jobId) => _$this._jobId = jobId;

  JobAcceptedBuilder() {
    JobAccepted._defaults(this);
  }

  JobAcceptedBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _jobId = $v.jobId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(JobAccepted other) {
    _$v = other as _$JobAccepted;
  }

  @override
  void update(void Function(JobAcceptedBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  JobAccepted build() => _build();

  _$JobAccepted _build() {
    final _$result = _$v ??
        _$JobAccepted._(
          jobId: BuiltValueNullFieldError.checkNotNull(
              jobId, r'JobAccepted', 'jobId'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
