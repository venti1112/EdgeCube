//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'poggit_plugin.g.dart';

/// Poggit releases.min.json 条目(字段为便于前端使用的子集,其它字段忽略)
///
/// Properties:
/// * [name] 
/// * [version] 
/// * [api] 
/// * [tag] 
/// * [lastUpdate] 
/// * [dl] 
/// * [icon] 
/// * [artifactUrl] 
@BuiltValue()
abstract class PoggitPlugin implements Built<PoggitPlugin, PoggitPluginBuilder> {
  @BuiltValueField(wireName: r'name')
  String get name;

  @BuiltValueField(wireName: r'version')
  String? get version;

  @BuiltValueField(wireName: r'api')
  BuiltList<String>? get api;

  @BuiltValueField(wireName: r'tag')
  BuiltList<String>? get tag;

  @BuiltValueField(wireName: r'last_update')
  int? get lastUpdate;

  @BuiltValueField(wireName: r'dl')
  int? get dl;

  @BuiltValueField(wireName: r'icon')
  String? get icon;

  @BuiltValueField(wireName: r'artifact_url')
  String? get artifactUrl;

  PoggitPlugin._();

  factory PoggitPlugin([void updates(PoggitPluginBuilder b)]) = _$PoggitPlugin;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PoggitPluginBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PoggitPlugin> get serializer => _$PoggitPluginSerializer();
}

class _$PoggitPluginSerializer implements PrimitiveSerializer<PoggitPlugin> {
  @override
  final Iterable<Type> types = const [PoggitPlugin, _$PoggitPlugin];

  @override
  final String wireName = r'PoggitPlugin';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PoggitPlugin object, {
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
    if (object.api != null) {
      yield r'api';
      yield serializers.serialize(
        object.api,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
    if (object.tag != null) {
      yield r'tag';
      yield serializers.serialize(
        object.tag,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
    if (object.lastUpdate != null) {
      yield r'last_update';
      yield serializers.serialize(
        object.lastUpdate,
        specifiedType: const FullType(int),
      );
    }
    if (object.dl != null) {
      yield r'dl';
      yield serializers.serialize(
        object.dl,
        specifiedType: const FullType(int),
      );
    }
    if (object.icon != null) {
      yield r'icon';
      yield serializers.serialize(
        object.icon,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.artifactUrl != null) {
      yield r'artifact_url';
      yield serializers.serialize(
        object.artifactUrl,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    PoggitPlugin object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PoggitPluginBuilder result,
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
        case r'api':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(String)]),
          ) as BuiltList<String>?;
          if (valueDes == null) continue;
          result.api.replace(valueDes);
          break;
        case r'tag':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(String)]),
          ) as BuiltList<String>?;
          if (valueDes == null) continue;
          result.tag.replace(valueDes);
          break;
        case r'last_update':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.lastUpdate = valueDes;
          break;
        case r'dl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.dl = valueDes;
          break;
        case r'icon':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.icon = valueDes;
          break;
        case r'artifact_url':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.artifactUrl = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PoggitPlugin deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PoggitPluginBuilder();
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

