// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'log_line.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$LogLine extends LogLine {
  @override
  final int seq;
  @override
  final DateTime? ts;
  @override
  final String text;

  factory _$LogLine([void Function(LogLineBuilder)? updates]) =>
      (LogLineBuilder()..update(updates))._build();

  _$LogLine._({required this.seq, this.ts, required this.text}) : super._();
  @override
  LogLine rebuild(void Function(LogLineBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  LogLineBuilder toBuilder() => LogLineBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is LogLine &&
        seq == other.seq &&
        ts == other.ts &&
        text == other.text;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, seq.hashCode);
    _$hash = $jc(_$hash, ts.hashCode);
    _$hash = $jc(_$hash, text.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'LogLine')
          ..add('seq', seq)
          ..add('ts', ts)
          ..add('text', text))
        .toString();
  }
}

class LogLineBuilder implements Builder<LogLine, LogLineBuilder> {
  _$LogLine? _$v;

  int? _seq;
  int? get seq => _$this._seq;
  set seq(int? seq) => _$this._seq = seq;

  DateTime? _ts;
  DateTime? get ts => _$this._ts;
  set ts(DateTime? ts) => _$this._ts = ts;

  String? _text;
  String? get text => _$this._text;
  set text(String? text) => _$this._text = text;

  LogLineBuilder() {
    LogLine._defaults(this);
  }

  LogLineBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _seq = $v.seq;
      _ts = $v.ts;
      _text = $v.text;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(LogLine other) {
    _$v = other as _$LogLine;
  }

  @override
  void update(void Function(LogLineBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  LogLine build() => _build();

  _$LogLine _build() {
    final _$result = _$v ??
        _$LogLine._(
          seq: BuiltValueNullFieldError.checkNotNull(seq, r'LogLine', 'seq'),
          ts: ts,
          text: BuiltValueNullFieldError.checkNotNull(text, r'LogLine', 'text'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
