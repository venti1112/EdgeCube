// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'instance_type.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const InstanceType _$minecraftJava = const InstanceType._('minecraftJava');
const InstanceType _$minecraftBedrock =
    const InstanceType._('minecraftBedrock');
const InstanceType _$pocketmine = const InstanceType._('pocketmine');
const InstanceType _$generic = const InstanceType._('generic');

InstanceType _$valueOf(String name) {
  switch (name) {
    case 'minecraftJava':
      return _$minecraftJava;
    case 'minecraftBedrock':
      return _$minecraftBedrock;
    case 'pocketmine':
      return _$pocketmine;
    case 'generic':
      return _$generic;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<InstanceType> _$values =
    BuiltSet<InstanceType>(const <InstanceType>[
  _$minecraftJava,
  _$minecraftBedrock,
  _$pocketmine,
  _$generic,
]);

class _$InstanceTypeMeta {
  const _$InstanceTypeMeta();
  InstanceType get minecraftJava => _$minecraftJava;
  InstanceType get minecraftBedrock => _$minecraftBedrock;
  InstanceType get pocketmine => _$pocketmine;
  InstanceType get generic => _$generic;
  InstanceType valueOf(String name) => _$valueOf(name);
  BuiltSet<InstanceType> get values => _$values;
}

abstract class _$InstanceTypeMixin {
  // ignore: non_constant_identifier_names
  _$InstanceTypeMeta get InstanceType => const _$InstanceTypeMeta();
}

Serializer<InstanceType> _$instanceTypeSerializer = _$InstanceTypeSerializer();

class _$InstanceTypeSerializer implements PrimitiveSerializer<InstanceType> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'minecraftJava': 'minecraft-java',
    'minecraftBedrock': 'minecraft-bedrock',
    'pocketmine': 'pocketmine',
    'generic': 'generic',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'minecraft-java': 'minecraftJava',
    'minecraft-bedrock': 'minecraftBedrock',
    'pocketmine': 'pocketmine',
    'generic': 'generic',
  };

  @override
  final Iterable<Type> types = const <Type>[InstanceType];
  @override
  final String wireName = 'InstanceType';

  @override
  Object serialize(Serializers serializers, InstanceType object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  InstanceType deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      InstanceType.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
