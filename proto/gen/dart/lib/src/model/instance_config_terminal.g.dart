// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'instance_config_terminal.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$InstanceConfigTerminal extends InstanceConfigTerminal {
  @override
  final bool? pty;
  @override
  final int? initialCols;
  @override
  final int? initialRows;
  @override
  final bool? haveColor;

  factory _$InstanceConfigTerminal(
          [void Function(InstanceConfigTerminalBuilder)? updates]) =>
      (InstanceConfigTerminalBuilder()..update(updates))._build();

  _$InstanceConfigTerminal._(
      {this.pty, this.initialCols, this.initialRows, this.haveColor})
      : super._();
  @override
  InstanceConfigTerminal rebuild(
          void Function(InstanceConfigTerminalBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  InstanceConfigTerminalBuilder toBuilder() =>
      InstanceConfigTerminalBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is InstanceConfigTerminal &&
        pty == other.pty &&
        initialCols == other.initialCols &&
        initialRows == other.initialRows &&
        haveColor == other.haveColor;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pty.hashCode);
    _$hash = $jc(_$hash, initialCols.hashCode);
    _$hash = $jc(_$hash, initialRows.hashCode);
    _$hash = $jc(_$hash, haveColor.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'InstanceConfigTerminal')
          ..add('pty', pty)
          ..add('initialCols', initialCols)
          ..add('initialRows', initialRows)
          ..add('haveColor', haveColor))
        .toString();
  }
}

class InstanceConfigTerminalBuilder
    implements Builder<InstanceConfigTerminal, InstanceConfigTerminalBuilder> {
  _$InstanceConfigTerminal? _$v;

  bool? _pty;
  bool? get pty => _$this._pty;
  set pty(bool? pty) => _$this._pty = pty;

  int? _initialCols;
  int? get initialCols => _$this._initialCols;
  set initialCols(int? initialCols) => _$this._initialCols = initialCols;

  int? _initialRows;
  int? get initialRows => _$this._initialRows;
  set initialRows(int? initialRows) => _$this._initialRows = initialRows;

  bool? _haveColor;
  bool? get haveColor => _$this._haveColor;
  set haveColor(bool? haveColor) => _$this._haveColor = haveColor;

  InstanceConfigTerminalBuilder() {
    InstanceConfigTerminal._defaults(this);
  }

  InstanceConfigTerminalBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pty = $v.pty;
      _initialCols = $v.initialCols;
      _initialRows = $v.initialRows;
      _haveColor = $v.haveColor;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(InstanceConfigTerminal other) {
    _$v = other as _$InstanceConfigTerminal;
  }

  @override
  void update(void Function(InstanceConfigTerminalBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  InstanceConfigTerminal build() => _build();

  _$InstanceConfigTerminal _build() {
    final _$result = _$v ??
        _$InstanceConfigTerminal._(
          pty: pty,
          initialCols: initialCols,
          initialRows: initialRows,
          haveColor: haveColor,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
