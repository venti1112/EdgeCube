// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'task_error.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$TaskError extends TaskError {
  @override
  final String? code;
  @override
  final String? message;

  factory _$TaskError([void Function(TaskErrorBuilder)? updates]) =>
      (TaskErrorBuilder()..update(updates))._build();

  _$TaskError._({this.code, this.message}) : super._();
  @override
  TaskError rebuild(void Function(TaskErrorBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  TaskErrorBuilder toBuilder() => TaskErrorBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is TaskError && code == other.code && message == other.message;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, code.hashCode);
    _$hash = $jc(_$hash, message.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'TaskError')
          ..add('code', code)
          ..add('message', message))
        .toString();
  }
}

class TaskErrorBuilder implements Builder<TaskError, TaskErrorBuilder> {
  _$TaskError? _$v;

  String? _code;
  String? get code => _$this._code;
  set code(String? code) => _$this._code = code;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  TaskErrorBuilder() {
    TaskError._defaults(this);
  }

  TaskErrorBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _code = $v.code;
      _message = $v.message;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(TaskError other) {
    _$v = other as _$TaskError;
  }

  @override
  void update(void Function(TaskErrorBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  TaskError build() => _build();

  _$TaskError _build() {
    final _$result = _$v ??
        _$TaskError._(
          code: code,
          message: message,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
