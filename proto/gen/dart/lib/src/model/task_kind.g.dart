// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'task_kind.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const TaskKind _$start = const TaskKind._('start');
const TaskKind _$stop = const TaskKind._('stop');
const TaskKind _$restart = const TaskKind._('restart');
const TaskKind _$kill = const TaskKind._('kill');
const TaskKind _$download = const TaskKind._('download');
const TaskKind _$export_ = const TaskKind._('export_');
const TaskKind _$import_ = const TaskKind._('import_');
const TaskKind _$backup = const TaskKind._('backup');
const TaskKind _$compress = const TaskKind._('compress');
const TaskKind _$extract = const TaskKind._('extract');
const TaskKind _$analyze = const TaskKind._('analyze');
const TaskKind _$downloadSingleFile = const TaskKind._('downloadSingleFile');
const TaskKind _$coreUpdate = const TaskKind._('coreUpdate');

TaskKind _$valueOf(String name) {
  switch (name) {
    case 'start':
      return _$start;
    case 'stop':
      return _$stop;
    case 'restart':
      return _$restart;
    case 'kill':
      return _$kill;
    case 'download':
      return _$download;
    case 'export_':
      return _$export_;
    case 'import_':
      return _$import_;
    case 'backup':
      return _$backup;
    case 'compress':
      return _$compress;
    case 'extract':
      return _$extract;
    case 'analyze':
      return _$analyze;
    case 'downloadSingleFile':
      return _$downloadSingleFile;
    case 'coreUpdate':
      return _$coreUpdate;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<TaskKind> _$values = BuiltSet<TaskKind>(const <TaskKind>[
  _$start,
  _$stop,
  _$restart,
  _$kill,
  _$download,
  _$export_,
  _$import_,
  _$backup,
  _$compress,
  _$extract,
  _$analyze,
  _$downloadSingleFile,
  _$coreUpdate,
]);

class _$TaskKindMeta {
  const _$TaskKindMeta();
  TaskKind get start => _$start;
  TaskKind get stop => _$stop;
  TaskKind get restart => _$restart;
  TaskKind get kill => _$kill;
  TaskKind get download => _$download;
  TaskKind get export_ => _$export_;
  TaskKind get import_ => _$import_;
  TaskKind get backup => _$backup;
  TaskKind get compress => _$compress;
  TaskKind get extract => _$extract;
  TaskKind get analyze => _$analyze;
  TaskKind get downloadSingleFile => _$downloadSingleFile;
  TaskKind get coreUpdate => _$coreUpdate;
  TaskKind valueOf(String name) => _$valueOf(name);
  BuiltSet<TaskKind> get values => _$values;
}

abstract class _$TaskKindMixin {
  // ignore: non_constant_identifier_names
  _$TaskKindMeta get TaskKind => const _$TaskKindMeta();
}

Serializer<TaskKind> _$taskKindSerializer = _$TaskKindSerializer();

class _$TaskKindSerializer implements PrimitiveSerializer<TaskKind> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'start': 'start',
    'stop': 'stop',
    'restart': 'restart',
    'kill': 'kill',
    'download': 'download',
    'export_': 'export',
    'import_': 'import',
    'backup': 'backup',
    'compress': 'compress',
    'extract': 'extract',
    'analyze': 'analyze',
    'downloadSingleFile': 'download_single_file',
    'coreUpdate': 'core_update',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'start': 'start',
    'stop': 'stop',
    'restart': 'restart',
    'kill': 'kill',
    'download': 'download',
    'export': 'export_',
    'import': 'import_',
    'backup': 'backup',
    'compress': 'compress',
    'extract': 'extract',
    'analyze': 'analyze',
    'download_single_file': 'downloadSingleFile',
    'core_update': 'coreUpdate',
  };

  @override
  final Iterable<Type> types = const <Type>[TaskKind];
  @override
  final String wireName = 'TaskKind';

  @override
  Object serialize(Serializers serializers, TaskKind object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  TaskKind deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      TaskKind.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
