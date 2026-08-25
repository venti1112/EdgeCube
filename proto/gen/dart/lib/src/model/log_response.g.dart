// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'log_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$LogResponse extends LogResponse {
  @override
  final BuiltList<LogLine> lines;
  @override
  final int nextSeq;

  factory _$LogResponse([void Function(LogResponseBuilder)? updates]) =>
      (LogResponseBuilder()..update(updates))._build();

  _$LogResponse._({required this.lines, required this.nextSeq}) : super._();
  @override
  LogResponse rebuild(void Function(LogResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  LogResponseBuilder toBuilder() => LogResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is LogResponse &&
        lines == other.lines &&
        nextSeq == other.nextSeq;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, lines.hashCode);
    _$hash = $jc(_$hash, nextSeq.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'LogResponse')
          ..add('lines', lines)
          ..add('nextSeq', nextSeq))
        .toString();
  }
}

class LogResponseBuilder implements Builder<LogResponse, LogResponseBuilder> {
  _$LogResponse? _$v;

  ListBuilder<LogLine>? _lines;
  ListBuilder<LogLine> get lines => _$this._lines ??= ListBuilder<LogLine>();
  set lines(ListBuilder<LogLine>? lines) => _$this._lines = lines;

  int? _nextSeq;
  int? get nextSeq => _$this._nextSeq;
  set nextSeq(int? nextSeq) => _$this._nextSeq = nextSeq;

  LogResponseBuilder() {
    LogResponse._defaults(this);
  }

  LogResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _lines = $v.lines.toBuilder();
      _nextSeq = $v.nextSeq;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(LogResponse other) {
    _$v = other as _$LogResponse;
  }

  @override
  void update(void Function(LogResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  LogResponse build() => _build();

  _$LogResponse _build() {
    _$LogResponse _$result;
    try {
      _$result = _$v ??
          _$LogResponse._(
            lines: lines.build(),
            nextSeq: BuiltValueNullFieldError.checkNotNull(
                nextSeq, r'LogResponse', 'nextSeq'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'lines';
        lines.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'LogResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
