//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'player_named_entry.g.dart';

/// PlayerNamedEntry
///
/// Properties:
/// * [name] - 玩家名(文本名单无 uuid 时为空串)
/// * [uuid] - 玩家 UUID,文本名单(white-list.txt 等)为空串
@BuiltValue()
abstract class PlayerNamedEntry implements Built<PlayerNamedEntry, PlayerNamedEntryBuilder> {
  /// 玩家名(文本名单无 uuid 时为空串)
  @BuiltValueField(wireName: r'name')
  String get name;

  /// 玩家 UUID,文本名单(white-list.txt 等)为空串
  @BuiltValueField(wireName: r'uuid')
  String? get uuid;

  PlayerNamedEntry._();

  factory PlayerNamedEntry([void updates(PlayerNamedEntryBuilder b)]) = _$PlayerNamedEntry;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlayerNamedEntryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlayerNamedEntry> get serializer => _$PlayerNamedEntrySerializer();
}

class _$PlayerNamedEntrySerializer implements PrimitiveSerializer<PlayerNamedEntry> {
  @override
  final Iterable<Type> types = const [PlayerNamedEntry, _$PlayerNamedEntry];

  @override
  final String wireName = r'PlayerNamedEntry';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlayerNamedEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    if (object.uuid != null) {
      yield r'uuid';
      yield serializers.serialize(
        object.uuid,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    PlayerNamedEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlayerNamedEntryBuilder result,
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
        case r'uuid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.uuid = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PlayerNamedEntry deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlayerNamedEntryBuilder();
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

