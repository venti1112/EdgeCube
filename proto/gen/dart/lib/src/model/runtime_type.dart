//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'runtime_type.g.dart';

class RuntimeType extends EnumClass {

  @BuiltValueEnumConst(wireName: r'java')
  static const RuntimeType java = _$java;
  @BuiltValueEnumConst(wireName: r'php')
  static const RuntimeType php = _$php;
  @BuiltValueEnumConst(wireName: r'frpc')
  static const RuntimeType frpc = _$frpc;

  static Serializer<RuntimeType> get serializer => _$runtimeTypeSerializer;

  const RuntimeType._(String name): super(name);

  static BuiltSet<RuntimeType> get values => _$values;
  static RuntimeType valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class RuntimeTypeMixin = Object with _$RuntimeTypeMixin;

