// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'command_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CommandRequest extends CommandRequest {
  @override
  final String command;

  factory _$CommandRequest([void Function(CommandRequestBuilder)? updates]) =>
      (CommandRequestBuilder()..update(updates))._build();

  _$CommandRequest._({required this.command}) : super._();
  @override
  CommandRequest rebuild(void Function(CommandRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CommandRequestBuilder toBuilder() => CommandRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CommandRequest && command == other.command;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, command.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CommandRequest')
          ..add('command', command))
        .toString();
  }
}

class CommandRequestBuilder
    implements Builder<CommandRequest, CommandRequestBuilder> {
  _$CommandRequest? _$v;

  String? _command;
  String? get command => _$this._command;
  set command(String? command) => _$this._command = command;

  CommandRequestBuilder() {
    CommandRequest._defaults(this);
  }

  CommandRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _command = $v.command;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CommandRequest other) {
    _$v = other as _$CommandRequest;
  }

  @override
  void update(void Function(CommandRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CommandRequest build() => _build();

  _$CommandRequest _build() {
    final _$result = _$v ??
        _$CommandRequest._(
          command: BuiltValueNullFieldError.checkNotNull(
              command, r'CommandRequest', 'command'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
