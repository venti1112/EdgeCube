// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mod_loader.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const ModLoader _$fabric = const ModLoader._('fabric');
const ModLoader _$forge = const ModLoader._('forge');
const ModLoader _$quilt = const ModLoader._('quilt');
const ModLoader _$neoforge = const ModLoader._('neoforge');
const ModLoader _$bukkit = const ModLoader._('bukkit');
const ModLoader _$bungeecord = const ModLoader._('bungeecord');
const ModLoader _$velocity = const ModLoader._('velocity');
const ModLoader _$pocketmine = const ModLoader._('pocketmine');
const ModLoader _$unknown = const ModLoader._('unknown');

ModLoader _$valueOf(String name) {
  switch (name) {
    case 'fabric':
      return _$fabric;
    case 'forge':
      return _$forge;
    case 'quilt':
      return _$quilt;
    case 'neoforge':
      return _$neoforge;
    case 'bukkit':
      return _$bukkit;
    case 'bungeecord':
      return _$bungeecord;
    case 'velocity':
      return _$velocity;
    case 'pocketmine':
      return _$pocketmine;
    case 'unknown':
      return _$unknown;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<ModLoader> _$values = BuiltSet<ModLoader>(const <ModLoader>[
  _$fabric,
  _$forge,
  _$quilt,
  _$neoforge,
  _$bukkit,
  _$bungeecord,
  _$velocity,
  _$pocketmine,
  _$unknown,
]);

class _$ModLoaderMeta {
  const _$ModLoaderMeta();
  ModLoader get fabric => _$fabric;
  ModLoader get forge => _$forge;
  ModLoader get quilt => _$quilt;
  ModLoader get neoforge => _$neoforge;
  ModLoader get bukkit => _$bukkit;
  ModLoader get bungeecord => _$bungeecord;
  ModLoader get velocity => _$velocity;
  ModLoader get pocketmine => _$pocketmine;
  ModLoader get unknown => _$unknown;
  ModLoader valueOf(String name) => _$valueOf(name);
  BuiltSet<ModLoader> get values => _$values;
}

abstract class _$ModLoaderMixin {
  // ignore: non_constant_identifier_names
  _$ModLoaderMeta get ModLoader => const _$ModLoaderMeta();
}

Serializer<ModLoader> _$modLoaderSerializer = _$ModLoaderSerializer();

class _$ModLoaderSerializer implements PrimitiveSerializer<ModLoader> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'fabric': 'fabric',
    'forge': 'forge',
    'quilt': 'quilt',
    'neoforge': 'neoforge',
    'bukkit': 'bukkit',
    'bungeecord': 'bungeecord',
    'velocity': 'velocity',
    'pocketmine': 'pocketmine',
    'unknown': 'unknown',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'fabric': 'fabric',
    'forge': 'forge',
    'quilt': 'quilt',
    'neoforge': 'neoforge',
    'bukkit': 'bukkit',
    'bungeecord': 'bungeecord',
    'velocity': 'velocity',
    'pocketmine': 'pocketmine',
    'unknown': 'unknown',
  };

  @override
  final Iterable<Type> types = const <Type>[ModLoader];
  @override
  final String wireName = 'ModLoader';

  @override
  Object serialize(Serializers serializers, ModLoader object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  ModLoader deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      ModLoader.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
