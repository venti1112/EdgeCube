//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'instance_type.g.dart';

class InstanceType extends EnumClass {

  /// 附加层类型;generic 为纯通用进程
  @BuiltValueEnumConst(wireName: r'minecraft-java')
  static const InstanceType minecraftJava = _$minecraftJava;
  /// 附加层类型;generic 为纯通用进程
  @BuiltValueEnumConst(wireName: r'minecraft-bedrock')
  static const InstanceType minecraftBedrock = _$minecraftBedrock;
  /// 附加层类型;generic 为纯通用进程
  @BuiltValueEnumConst(wireName: r'pocketmine')
  static const InstanceType pocketmine = _$pocketmine;
  /// 附加层类型;generic 为纯通用进程
  @BuiltValueEnumConst(wireName: r'generic')
  static const InstanceType generic = _$generic;

  static Serializer<InstanceType> get serializer => _$instanceTypeSerializer;

  const InstanceType._(String name): super(name);

  static BuiltSet<InstanceType> get values => _$values;
  static InstanceType valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class InstanceTypeMixin = Object with _$InstanceTypeMixin;

