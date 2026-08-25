// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'instance_config.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$InstanceConfig extends InstanceConfig {
  @override
  final String? id;
  @override
  final String name;
  @override
  final String startCommand;
  @override
  final String? stopCommand;
  @override
  final int? stopTimeoutSeconds;
  @override
  final String workingDirectory;
  @override
  final BuiltMap<String, String>? environment;
  @override
  final Encoding? inputEncoding;
  @override
  final Encoding? outputEncoding;
  @override
  final bool? autoRestart;
  @override
  final int? autoRestartMaxTimes;
  @override
  final bool? autoStartOnBoot;
  @override
  final InstanceConfigTerminal? terminal;
  @override
  final InstanceType? type;
  @override
  final DateTime? createdAt;
  @override
  final DateTime? updatedAt;

  factory _$InstanceConfig([void Function(InstanceConfigBuilder)? updates]) =>
      (InstanceConfigBuilder()..update(updates))._build();

  _$InstanceConfig._(
      {this.id,
      required this.name,
      required this.startCommand,
      this.stopCommand,
      this.stopTimeoutSeconds,
      required this.workingDirectory,
      this.environment,
      this.inputEncoding,
      this.outputEncoding,
      this.autoRestart,
      this.autoRestartMaxTimes,
      this.autoStartOnBoot,
      this.terminal,
      this.type,
      this.createdAt,
      this.updatedAt})
      : super._();
  @override
  InstanceConfig rebuild(void Function(InstanceConfigBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  InstanceConfigBuilder toBuilder() => InstanceConfigBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is InstanceConfig &&
        id == other.id &&
        name == other.name &&
        startCommand == other.startCommand &&
        stopCommand == other.stopCommand &&
        stopTimeoutSeconds == other.stopTimeoutSeconds &&
        workingDirectory == other.workingDirectory &&
        environment == other.environment &&
        inputEncoding == other.inputEncoding &&
        outputEncoding == other.outputEncoding &&
        autoRestart == other.autoRestart &&
        autoRestartMaxTimes == other.autoRestartMaxTimes &&
        autoStartOnBoot == other.autoStartOnBoot &&
        terminal == other.terminal &&
        type == other.type &&
        createdAt == other.createdAt &&
        updatedAt == other.updatedAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, startCommand.hashCode);
    _$hash = $jc(_$hash, stopCommand.hashCode);
    _$hash = $jc(_$hash, stopTimeoutSeconds.hashCode);
    _$hash = $jc(_$hash, workingDirectory.hashCode);
    _$hash = $jc(_$hash, environment.hashCode);
    _$hash = $jc(_$hash, inputEncoding.hashCode);
    _$hash = $jc(_$hash, outputEncoding.hashCode);
    _$hash = $jc(_$hash, autoRestart.hashCode);
    _$hash = $jc(_$hash, autoRestartMaxTimes.hashCode);
    _$hash = $jc(_$hash, autoStartOnBoot.hashCode);
    _$hash = $jc(_$hash, terminal.hashCode);
    _$hash = $jc(_$hash, type.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'InstanceConfig')
          ..add('id', id)
          ..add('name', name)
          ..add('startCommand', startCommand)
          ..add('stopCommand', stopCommand)
          ..add('stopTimeoutSeconds', stopTimeoutSeconds)
          ..add('workingDirectory', workingDirectory)
          ..add('environment', environment)
          ..add('inputEncoding', inputEncoding)
          ..add('outputEncoding', outputEncoding)
          ..add('autoRestart', autoRestart)
          ..add('autoRestartMaxTimes', autoRestartMaxTimes)
          ..add('autoStartOnBoot', autoStartOnBoot)
          ..add('terminal', terminal)
          ..add('type', type)
          ..add('createdAt', createdAt)
          ..add('updatedAt', updatedAt))
        .toString();
  }
}

class InstanceConfigBuilder
    implements Builder<InstanceConfig, InstanceConfigBuilder> {
  _$InstanceConfig? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _startCommand;
  String? get startCommand => _$this._startCommand;
  set startCommand(String? startCommand) => _$this._startCommand = startCommand;

  String? _stopCommand;
  String? get stopCommand => _$this._stopCommand;
  set stopCommand(String? stopCommand) => _$this._stopCommand = stopCommand;

  int? _stopTimeoutSeconds;
  int? get stopTimeoutSeconds => _$this._stopTimeoutSeconds;
  set stopTimeoutSeconds(int? stopTimeoutSeconds) =>
      _$this._stopTimeoutSeconds = stopTimeoutSeconds;

  String? _workingDirectory;
  String? get workingDirectory => _$this._workingDirectory;
  set workingDirectory(String? workingDirectory) =>
      _$this._workingDirectory = workingDirectory;

  MapBuilder<String, String>? _environment;
  MapBuilder<String, String> get environment =>
      _$this._environment ??= MapBuilder<String, String>();
  set environment(MapBuilder<String, String>? environment) =>
      _$this._environment = environment;

  Encoding? _inputEncoding;
  Encoding? get inputEncoding => _$this._inputEncoding;
  set inputEncoding(Encoding? inputEncoding) =>
      _$this._inputEncoding = inputEncoding;

  Encoding? _outputEncoding;
  Encoding? get outputEncoding => _$this._outputEncoding;
  set outputEncoding(Encoding? outputEncoding) =>
      _$this._outputEncoding = outputEncoding;

  bool? _autoRestart;
  bool? get autoRestart => _$this._autoRestart;
  set autoRestart(bool? autoRestart) => _$this._autoRestart = autoRestart;

  int? _autoRestartMaxTimes;
  int? get autoRestartMaxTimes => _$this._autoRestartMaxTimes;
  set autoRestartMaxTimes(int? autoRestartMaxTimes) =>
      _$this._autoRestartMaxTimes = autoRestartMaxTimes;

  bool? _autoStartOnBoot;
  bool? get autoStartOnBoot => _$this._autoStartOnBoot;
  set autoStartOnBoot(bool? autoStartOnBoot) =>
      _$this._autoStartOnBoot = autoStartOnBoot;

  InstanceConfigTerminalBuilder? _terminal;
  InstanceConfigTerminalBuilder get terminal =>
      _$this._terminal ??= InstanceConfigTerminalBuilder();
  set terminal(InstanceConfigTerminalBuilder? terminal) =>
      _$this._terminal = terminal;

  InstanceType? _type;
  InstanceType? get type => _$this._type;
  set type(InstanceType? type) => _$this._type = type;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  DateTime? _updatedAt;
  DateTime? get updatedAt => _$this._updatedAt;
  set updatedAt(DateTime? updatedAt) => _$this._updatedAt = updatedAt;

  InstanceConfigBuilder() {
    InstanceConfig._defaults(this);
  }

  InstanceConfigBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _name = $v.name;
      _startCommand = $v.startCommand;
      _stopCommand = $v.stopCommand;
      _stopTimeoutSeconds = $v.stopTimeoutSeconds;
      _workingDirectory = $v.workingDirectory;
      _environment = $v.environment?.toBuilder();
      _inputEncoding = $v.inputEncoding;
      _outputEncoding = $v.outputEncoding;
      _autoRestart = $v.autoRestart;
      _autoRestartMaxTimes = $v.autoRestartMaxTimes;
      _autoStartOnBoot = $v.autoStartOnBoot;
      _terminal = $v.terminal?.toBuilder();
      _type = $v.type;
      _createdAt = $v.createdAt;
      _updatedAt = $v.updatedAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(InstanceConfig other) {
    _$v = other as _$InstanceConfig;
  }

  @override
  void update(void Function(InstanceConfigBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  InstanceConfig build() => _build();

  _$InstanceConfig _build() {
    _$InstanceConfig _$result;
    try {
      _$result = _$v ??
          _$InstanceConfig._(
            id: id,
            name: BuiltValueNullFieldError.checkNotNull(
                name, r'InstanceConfig', 'name'),
            startCommand: BuiltValueNullFieldError.checkNotNull(
                startCommand, r'InstanceConfig', 'startCommand'),
            stopCommand: stopCommand,
            stopTimeoutSeconds: stopTimeoutSeconds,
            workingDirectory: BuiltValueNullFieldError.checkNotNull(
                workingDirectory, r'InstanceConfig', 'workingDirectory'),
            environment: _environment?.build(),
            inputEncoding: inputEncoding,
            outputEncoding: outputEncoding,
            autoRestart: autoRestart,
            autoRestartMaxTimes: autoRestartMaxTimes,
            autoStartOnBoot: autoStartOnBoot,
            terminal: _terminal?.build(),
            type: type,
            createdAt: createdAt,
            updatedAt: updatedAt,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'environment';
        _environment?.build();

        _$failedField = 'terminal';
        _terminal?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'InstanceConfig', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
