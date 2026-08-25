//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'backup_target_type.g.dart';

class BackupTargetType extends EnumClass {

  @BuiltValueEnumConst(wireName: r'local')
  static const BackupTargetType local = _$local;
  @BuiltValueEnumConst(wireName: r'ftp')
  static const BackupTargetType ftp = _$ftp;
  @BuiltValueEnumConst(wireName: r'sftp')
  static const BackupTargetType sftp = _$sftp;

  static Serializer<BackupTargetType> get serializer => _$backupTargetTypeSerializer;

  const BackupTargetType._(String name): super(name);

  static BuiltSet<BackupTargetType> get values => _$values;
  static BackupTargetType valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class BackupTargetTypeMixin = Object with _$BackupTargetTypeMixin;

