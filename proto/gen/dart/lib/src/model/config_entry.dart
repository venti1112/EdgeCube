//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'config_entry.g.dart';

/// ConfigEntry
///
/// Properties:
/// * [key] - 设置项名(locale/theme/network/developer/terminal/download 等)
/// * [value] - 任意 JSON 值
@BuiltValue()
abstract class ConfigEntry implements Built<ConfigEntry, ConfigEntryBuilder> {
  /// 设置项名(locale/theme/network/developer/terminal/download 等)
  @BuiltValueField(wireName: r'key')
  String get key;

  /// 任意 JSON 值
  @BuiltValueField(wireName: r'value')
  BuiltMap<String, JsonObject?> get value;

  ConfigEntry._();

  factory ConfigEntry([void updates(ConfigEntryBuilder b)]) = _$ConfigEntry;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ConfigEntryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ConfigEntry> get serializer => _$ConfigEntrySerializer();
}

class _$ConfigEntrySerializer implements PrimitiveSerializer<ConfigEntry> {
  @override
  final Iterable<Type> types = const [ConfigEntry, _$ConfigEntry];

  @override
  final String wireName = r'ConfigEntry';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ConfigEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'key';
    yield serializers.serialize(
      object.key,
      specifiedType: const FullType(String),
    );
    yield r'value';
    yield serializers.serialize(
      object.value,
      specifiedType: const FullType(BuiltMap, [FullType(String), FullType.nullable(JsonObject)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ConfigEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ConfigEntryBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'key':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.key = valueDes;
          break;
        case r'value':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltMap, [FullType(String), FullType.nullable(JsonObject)]),
          ) as BuiltMap<String, JsonObject?>;
          result.value.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ConfigEntry deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ConfigEntryBuilder();
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

