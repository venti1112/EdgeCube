//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'server_type_info.g.dart';

/// 服务端类型静态定义。「下载服务端」向导数据源,分类结构与 V1 对齐。 
///
/// Properties:
/// * [type] - 类型 id,如 vanilla / paper / spigot / craftbukkit / purpur / leaf / leaves / velocity / bungeecord / fabric / pocketmine / powernukkitx / allay
/// * [category] 
/// * [hasLoader] - true 时版本页选择 MC 版本后需经 /catalog/loaders 选加载器版本(目前仅 fabric)
/// * [fileName] - 该类型默认落盘文件名(如 server.jar / bungeecord.jar / PocketMine-MP.phar);下载信息可覆盖
@BuiltValue()
abstract class ServerTypeInfo implements Built<ServerTypeInfo, ServerTypeInfoBuilder> {
  /// 类型 id,如 vanilla / paper / spigot / craftbukkit / purpur / leaf / leaves / velocity / bungeecord / fabric / pocketmine / powernukkitx / allay
  @BuiltValueField(wireName: r'type')
  String get type;

  @BuiltValueField(wireName: r'category')
  ServerTypeInfoCategoryEnum get category;
  // enum categoryEnum {  vanilla,  plugin,  mod,  proxy,  bedrock,  };

  /// true 时版本页选择 MC 版本后需经 /catalog/loaders 选加载器版本(目前仅 fabric)
  @BuiltValueField(wireName: r'hasLoader')
  bool? get hasLoader;

  /// 该类型默认落盘文件名(如 server.jar / bungeecord.jar / PocketMine-MP.phar);下载信息可覆盖
  @BuiltValueField(wireName: r'fileName')
  String get fileName;

  ServerTypeInfo._();

  factory ServerTypeInfo([void updates(ServerTypeInfoBuilder b)]) = _$ServerTypeInfo;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ServerTypeInfoBuilder b) => b
      ..hasLoader = false;

  @BuiltValueSerializer(custom: true)
  static Serializer<ServerTypeInfo> get serializer => _$ServerTypeInfoSerializer();
}

class _$ServerTypeInfoSerializer implements PrimitiveSerializer<ServerTypeInfo> {
  @override
  final Iterable<Type> types = const [ServerTypeInfo, _$ServerTypeInfo];

  @override
  final String wireName = r'ServerTypeInfo';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ServerTypeInfo object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'type';
    yield serializers.serialize(
      object.type,
      specifiedType: const FullType(String),
    );
    yield r'category';
    yield serializers.serialize(
      object.category,
      specifiedType: const FullType(ServerTypeInfoCategoryEnum),
    );
    if (object.hasLoader != null) {
      yield r'hasLoader';
      yield serializers.serialize(
        object.hasLoader,
        specifiedType: const FullType(bool),
      );
    }
    yield r'fileName';
    yield serializers.serialize(
      object.fileName,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ServerTypeInfo object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ServerTypeInfoBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.type = valueDes;
          break;
        case r'category':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ServerTypeInfoCategoryEnum),
          ) as ServerTypeInfoCategoryEnum;
          result.category = valueDes;
          break;
        case r'hasLoader':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.hasLoader = valueDes;
          break;
        case r'fileName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.fileName = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ServerTypeInfo deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ServerTypeInfoBuilder();
    final serializedList = (serialized as Iterable<Object?>).toList();
    final unhandled = <Object?>[];
    _deserializeProperties(
      serializers,
      serialized,
      specifiedType: specifiedType,
      serializedList: serializedList,
      unhandled: unhandled,
      result: result,
    );
    return result.build();
  }
}

class ServerTypeInfoCategoryEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'vanilla')
  static const ServerTypeInfoCategoryEnum vanilla = _$serverTypeInfoCategoryEnum_vanilla;
  @BuiltValueEnumConst(wireName: r'plugin')
  static const ServerTypeInfoCategoryEnum plugin = _$serverTypeInfoCategoryEnum_plugin;
  @BuiltValueEnumConst(wireName: r'mod')
  static const ServerTypeInfoCategoryEnum mod = _$serverTypeInfoCategoryEnum_mod;
  @BuiltValueEnumConst(wireName: r'proxy')
  static const ServerTypeInfoCategoryEnum proxy = _$serverTypeInfoCategoryEnum_proxy;
  @BuiltValueEnumConst(wireName: r'bedrock')
  static const ServerTypeInfoCategoryEnum bedrock = _$serverTypeInfoCategoryEnum_bedrock;

  static Serializer<ServerTypeInfoCategoryEnum> get serializer => _$serverTypeInfoCategoryEnumSerializer;

  const ServerTypeInfoCategoryEnum._(String name): super(name);

  static BuiltSet<ServerTypeInfoCategoryEnum> get values => _$serverTypeInfoCategoryEnumValues;
  static ServerTypeInfoCategoryEnum valueOf(String name) => _$serverTypeInfoCategoryEnumValueOf(name);
}

