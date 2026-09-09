//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'server_version.g.dart';

/// ServerVersion
///
/// Properties:
/// * [version] - 版本号(降序)
/// * [meta] - 附加信息(可选):raw.githubusercontent.com 等来源的说明字段,如 pocketmine/powernukkitx 的客户端版本
@BuiltValue()
abstract class ServerVersion implements Built<ServerVersion, ServerVersionBuilder> {
  /// 版本号(降序)
  @BuiltValueField(wireName: r'version')
  String get version;

  /// 附加信息(可选):raw.githubusercontent.com 等来源的说明字段,如 pocketmine/powernukkitx 的客户端版本
  @BuiltValueField(wireName: r'meta')
  BuiltMap<String, JsonObject?>? get meta;

  ServerVersion._();

  factory ServerVersion([void updates(ServerVersionBuilder b)]) = _$ServerVersion;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ServerVersionBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ServerVersion> get serializer => _$ServerVersionSerializer();
}

class _$ServerVersionSerializer implements PrimitiveSerializer<ServerVersion> {
  @override
  final Iterable<Type> types = const [ServerVersion, _$ServerVersion];

  @override
  final String wireName = r'ServerVersion';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ServerVersion object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'version';
    yield serializers.serialize(
      object.version,
      specifiedType: const FullType(String),
    );
    if (object.meta != null) {
      yield r'meta';
      yield serializers.serialize(
        object.meta,
        specifiedType: const FullType(BuiltMap, [FullType(String), FullType.nullable(JsonObject)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ServerVersion object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ServerVersionBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'version':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.version = valueDes;
          break;
        case r'meta':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltMap, [FullType(String), FullType.nullable(JsonObject)]),
          ) as BuiltMap<String, JsonObject?>?;
          if (valueDes == null) continue;
          result.meta.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ServerVersion deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ServerVersionBuilder();
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

