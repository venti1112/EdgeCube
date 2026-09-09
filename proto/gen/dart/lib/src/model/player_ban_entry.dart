//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'player_ban_entry.g.dart';

/// PlayerBanEntry
///
/// Properties:
/// * [name] 
/// * [uuid] 
/// * [reason] - 封禁原因;文本名单为空串
/// * [source_] - 封禁来源(执行人);文本名单为空串
/// * [expires] - 过期时间(Java 用 expires,PNX 用 expireDate,已归一化);文本名单为空串
/// * [created] - 创建时间(Java 用 created,PNX 用 creationDate,已归一化);文本名单为空串
@BuiltValue()
abstract class PlayerBanEntry implements Built<PlayerBanEntry, PlayerBanEntryBuilder> {
  @BuiltValueField(wireName: r'name')
  String get name;

  @BuiltValueField(wireName: r'uuid')
  String? get uuid;

  /// 封禁原因;文本名单为空串
  @BuiltValueField(wireName: r'reason')
  String? get reason;

  /// 封禁来源(执行人);文本名单为空串
  @BuiltValueField(wireName: r'source')
  String? get source_;

  /// 过期时间(Java 用 expires,PNX 用 expireDate,已归一化);文本名单为空串
  @BuiltValueField(wireName: r'expires')
  String? get expires;

  /// 创建时间(Java 用 created,PNX 用 creationDate,已归一化);文本名单为空串
  @BuiltValueField(wireName: r'created')
  String? get created;

  PlayerBanEntry._();

  factory PlayerBanEntry([void updates(PlayerBanEntryBuilder b)]) = _$PlayerBanEntry;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlayerBanEntryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlayerBanEntry> get serializer => _$PlayerBanEntrySerializer();
}

class _$PlayerBanEntrySerializer implements PrimitiveSerializer<PlayerBanEntry> {
  @override
  final Iterable<Type> types = const [PlayerBanEntry, _$PlayerBanEntry];

  @override
  final String wireName = r'PlayerBanEntry';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlayerBanEntry object, {
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
    if (object.reason != null) {
      yield r'reason';
      yield serializers.serialize(
        object.reason,
        specifiedType: const FullType(String),
      );
    }
    if (object.source_ != null) {
      yield r'source';
      yield serializers.serialize(
        object.source_,
        specifiedType: const FullType(String),
      );
    }
    if (object.expires != null) {
      yield r'expires';
      yield serializers.serialize(
        object.expires,
        specifiedType: const FullType(String),
      );
    }
    if (object.created != null) {
      yield r'created';
      yield serializers.serialize(
        object.created,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    PlayerBanEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlayerBanEntryBuilder result,
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
        case r'reason':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.reason = valueDes;
          break;
        case r'source':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.source_ = valueDes;
          break;
        case r'expires':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.expires = valueDes;
          break;
        case r'created':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.created = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PlayerBanEntry deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlayerBanEntryBuilder();
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

