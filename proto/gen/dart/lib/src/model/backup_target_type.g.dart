// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'backup_target_type.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const BackupTargetType _$local = const BackupTargetType._('local');
const BackupTargetType _$ftp = const BackupTargetType._('ftp');
const BackupTargetType _$sftp = const BackupTargetType._('sftp');

BackupTargetType _$valueOf(String name) {
  switch (name) {
    case 'local':
      return _$local;
    case 'ftp':
      return _$ftp;
    case 'sftp':
      return _$sftp;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<BackupTargetType> _$values =
    BuiltSet<BackupTargetType>(const <BackupTargetType>[
  _$local,
  _$ftp,
  _$sftp,
]);

class _$BackupTargetTypeMeta {
  const _$BackupTargetTypeMeta();
  BackupTargetType get local => _$local;
  BackupTargetType get ftp => _$ftp;
  BackupTargetType get sftp => _$sftp;
  BackupTargetType valueOf(String name) => _$valueOf(name);
  BuiltSet<BackupTargetType> get values => _$values;
}

abstract class _$BackupTargetTypeMixin {
  // ignore: non_constant_identifier_names
  _$BackupTargetTypeMeta get BackupTargetType => const _$BackupTargetTypeMeta();
}

Serializer<BackupTargetType> _$backupTargetTypeSerializer =
    _$BackupTargetTypeSerializer();

class _$BackupTargetTypeSerializer
    implements PrimitiveSerializer<BackupTargetType> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'local': 'local',
    'ftp': 'ftp',
    'sftp': 'sftp',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'local': 'local',
    'ftp': 'ftp',
    'sftp': 'sftp',
  };

  @override
  final Iterable<Type> types = const <Type>[BackupTargetType];
  @override
  final String wireName = 'BackupTargetType';

  @override
  Object serialize(Serializers serializers, BackupTargetType object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  BackupTargetType deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      BackupTargetType.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
