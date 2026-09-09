//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:edgecube_api_client/src/model/mod_loader.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'mod_metadata.g.dart';

/// ModMetadata
///
/// Properties:
/// * [name] 
/// * [version] 
/// * [description] 
/// * [modId] - 模组 id / 插件主类等标识
/// * [authors] - 逗号分隔的作者/贡献者
/// * [url] 
/// * [loader] 
@BuiltValue()
abstract class ModMetadata implements Built<ModMetadata, ModMetadataBuilder> {
  @BuiltValueField(wireName: r'name')
  String get name;

  @BuiltValueField(wireName: r'version')
  String? get version;

  @BuiltValueField(wireName: r'description')
  String? get description;

  /// 模组 id / 插件主类等标识
  @BuiltValueField(wireName: r'modId')
  String? get modId;

  /// 逗号分隔的作者/贡献者
  @BuiltValueField(wireName: r'authors')
  String? get authors;

  @BuiltValueField(wireName: r'url')
  String? get url;

  @BuiltValueField(wireName: r'loader')
  ModLoader get loader;
  // enum loaderEnum {  fabric,  forge,  quilt,  neoforge,  bukkit,  bungeecord,  velocity,  pocketmine,  unknown,  };

  ModMetadata._();

  factory ModMetadata([void updates(ModMetadataBuilder b)]) = _$ModMetadata;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ModMetadataBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ModMetadata> get serializer => _$ModMetadataSerializer();
}

class _$ModMetadataSerializer implements PrimitiveSerializer<ModMetadata> {
  @override
  final Iterable<Type> types = const [ModMetadata, _$ModMetadata];

  @override
  final String wireName = r'ModMetadata';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ModMetadata object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    if (object.version != null) {
      yield r'version';
      yield serializers.serialize(
        object.version,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.description != null) {
      yield r'description';
      yield serializers.serialize(
        object.description,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.modId != null) {
      yield r'modId';
      yield serializers.serialize(
        object.modId,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.authors != null) {
      yield r'authors';
      yield serializers.serialize(
        object.authors,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.url != null) {
      yield r'url';
      yield serializers.serialize(
        object.url,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'loader';
    yield serializers.serialize(
      object.loader,
      specifiedType: const FullType(ModLoader),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ModMetadata object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ModMetadataBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'version':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.version = valueDes;
          break;
        case r'description':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.description = valueDes;
          break;
        case r'modId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.modId = valueDes;
          break;
        case r'authors':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.authors = valueDes;
          break;
        case r'url':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.url = valueDes;
          break;
        case r'loader':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ModLoader),
          ) as ModLoader;
          result.loader = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ModMetadata deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ModMetadataBuilder();
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

