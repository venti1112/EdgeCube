//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'mod_loader.g.dart';

class ModLoader extends EnumClass {

  /// 插件/模组加载器类型(lowercase)
  @BuiltValueEnumConst(wireName: r'fabric')
  static const ModLoader fabric = _$fabric;
  /// 插件/模组加载器类型(lowercase)
  @BuiltValueEnumConst(wireName: r'forge')
  static const ModLoader forge = _$forge;
  /// 插件/模组加载器类型(lowercase)
  @BuiltValueEnumConst(wireName: r'quilt')
  static const ModLoader quilt = _$quilt;
  /// 插件/模组加载器类型(lowercase)
  @BuiltValueEnumConst(wireName: r'neoforge')
  static const ModLoader neoforge = _$neoforge;
  /// 插件/模组加载器类型(lowercase)
  @BuiltValueEnumConst(wireName: r'bukkit')
  static const ModLoader bukkit = _$bukkit;
  /// 插件/模组加载器类型(lowercase)
  @BuiltValueEnumConst(wireName: r'bungeecord')
  static const ModLoader bungeecord = _$bungeecord;
  /// 插件/模组加载器类型(lowercase)
  @BuiltValueEnumConst(wireName: r'velocity')
  static const ModLoader velocity = _$velocity;
  /// 插件/模组加载器类型(lowercase)
  @BuiltValueEnumConst(wireName: r'pocketmine')
  static const ModLoader pocketmine = _$pocketmine;
  /// 插件/模组加载器类型(lowercase)
  @BuiltValueEnumConst(wireName: r'unknown')
  static const ModLoader unknown = _$unknown;

  static Serializer<ModLoader> get serializer => _$modLoaderSerializer;

  const ModLoader._(String name): super(name);

  static BuiltSet<ModLoader> get values => _$values;
  static ModLoader valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class ModLoaderMixin = Object with _$ModLoaderMixin;

