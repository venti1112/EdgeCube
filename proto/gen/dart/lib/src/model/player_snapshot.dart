//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:edgecube_api_client/src/model/instance_status.dart';
import 'package:edgecube_api_client/src/model/player_ban_entry.dart';
import 'package:edgecube_api_client/src/model/player_ip_ban_entry.dart';
import 'package:built_collection/built_collection.dart';
import 'package:edgecube_api_client/src/model/player_named_entry.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'player_snapshot.g.dart';

/// PlayerSnapshot
///
/// Properties:
/// * [instanceStatus] 
/// * [online] - 在线玩家名(daemon 解析控制台输出维护,按名排序)
/// * [whitelist] 
/// * [ops] 
/// * [bans] 
/// * [banIps] 
@BuiltValue()
abstract class PlayerSnapshot implements Built<PlayerSnapshot, PlayerSnapshotBuilder> {
  @BuiltValueField(wireName: r'instanceStatus')
  InstanceStatus get instanceStatus;
  // enum instanceStatusEnum {  busy,  stopped,  stopping,  starting,  running,  };

  /// 在线玩家名(daemon 解析控制台输出维护,按名排序)
  @BuiltValueField(wireName: r'online')
  BuiltList<String> get online;

  @BuiltValueField(wireName: r'whitelist')
  BuiltList<PlayerNamedEntry> get whitelist;

  @BuiltValueField(wireName: r'ops')
  BuiltList<PlayerNamedEntry> get ops;

  @BuiltValueField(wireName: r'bans')
  BuiltList<PlayerBanEntry> get bans;

  @BuiltValueField(wireName: r'banIps')
  BuiltList<PlayerIpBanEntry> get banIps;

  PlayerSnapshot._();

  factory PlayerSnapshot([void updates(PlayerSnapshotBuilder b)]) = _$PlayerSnapshot;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlayerSnapshotBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlayerSnapshot> get serializer => _$PlayerSnapshotSerializer();
}

class _$PlayerSnapshotSerializer implements PrimitiveSerializer<PlayerSnapshot> {
  @override
  final Iterable<Type> types = const [PlayerSnapshot, _$PlayerSnapshot];

  @override
  final String wireName = r'PlayerSnapshot';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlayerSnapshot object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'instanceStatus';
    yield serializers.serialize(
      object.instanceStatus,
      specifiedType: const FullType(InstanceStatus),
    );
    yield r'online';
    yield serializers.serialize(
      object.online,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
    yield r'whitelist';
    yield serializers.serialize(
      object.whitelist,
      specifiedType: const FullType(BuiltList, [FullType(PlayerNamedEntry)]),
    );
    yield r'ops';
    yield serializers.serialize(
      object.ops,
      specifiedType: const FullType(BuiltList, [FullType(PlayerNamedEntry)]),
    );
    yield r'bans';
    yield serializers.serialize(
      object.bans,
      specifiedType: const FullType(BuiltList, [FullType(PlayerBanEntry)]),
    );
    yield r'banIps';
    yield serializers.serialize(
      object.banIps,
      specifiedType: const FullType(BuiltList, [FullType(PlayerIpBanEntry)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PlayerSnapshot object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlayerSnapshotBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'instanceStatus':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(InstanceStatus),
          ) as InstanceStatus;
          result.instanceStatus = valueDes;
          break;
        case r'online':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.online.replace(valueDes);
          break;
        case r'whitelist':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(PlayerNamedEntry)]),
          ) as BuiltList<PlayerNamedEntry>;
          result.whitelist.replace(valueDes);
          break;
        case r'ops':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(PlayerNamedEntry)]),
          ) as BuiltList<PlayerNamedEntry>;
          result.ops.replace(valueDes);
          break;
        case r'bans':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(PlayerBanEntry)]),
          ) as BuiltList<PlayerBanEntry>;
          result.bans.replace(valueDes);
          break;
        case r'banIps':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(PlayerIpBanEntry)]),
          ) as BuiltList<PlayerIpBanEntry>;
          result.banIps.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PlayerSnapshot deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlayerSnapshotBuilder();
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

