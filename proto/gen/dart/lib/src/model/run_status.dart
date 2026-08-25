//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:edgecube_api_client/src/model/instance_status.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'run_status.g.dart';

/// RunStatus
///
/// Properties:
/// * [status] 
/// * [pid] - 真实游戏进程 PID(PTY 握手获得)
/// * [exitCode] - 上次退出码
/// * [serverPort] 
/// * [onlineMode] 
/// * [onlinePlayers] - 当前在线玩家名
/// * [logSeq] - 当前日志行序号(供 /log?since= 续拉)
@BuiltValue()
abstract class RunStatus implements Built<RunStatus, RunStatusBuilder> {
  @BuiltValueField(wireName: r'status')
  InstanceStatus get status;
  // enum statusEnum {  busy,  stopped,  stopping,  starting,  running,  };

  /// 真实游戏进程 PID(PTY 握手获得)
  @BuiltValueField(wireName: r'pid')
  int? get pid;

  /// 上次退出码
  @BuiltValueField(wireName: r'exitCode')
  int? get exitCode;

  @BuiltValueField(wireName: r'serverPort')
  int? get serverPort;

  @BuiltValueField(wireName: r'onlineMode')
  bool? get onlineMode;

  /// 当前在线玩家名
  @BuiltValueField(wireName: r'onlinePlayers')
  BuiltList<String>? get onlinePlayers;

  /// 当前日志行序号(供 /log?since= 续拉)
  @BuiltValueField(wireName: r'logSeq')
  int? get logSeq;

  RunStatus._();

  factory RunStatus([void updates(RunStatusBuilder b)]) = _$RunStatus;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RunStatusBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RunStatus> get serializer => _$RunStatusSerializer();
}

class _$RunStatusSerializer implements PrimitiveSerializer<RunStatus> {
  @override
  final Iterable<Type> types = const [RunStatus, _$RunStatus];

  @override
  final String wireName = r'RunStatus';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RunStatus object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(InstanceStatus),
    );
    if (object.pid != null) {
      yield r'pid';
      yield serializers.serialize(
        object.pid,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.exitCode != null) {
      yield r'exitCode';
      yield serializers.serialize(
        object.exitCode,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.serverPort != null) {
      yield r'serverPort';
      yield serializers.serialize(
        object.serverPort,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.onlineMode != null) {
      yield r'onlineMode';
      yield serializers.serialize(
        object.onlineMode,
        specifiedType: const FullType.nullable(bool),
      );
    }
    if (object.onlinePlayers != null) {
      yield r'onlinePlayers';
      yield serializers.serialize(
        object.onlinePlayers,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
    if (object.logSeq != null) {
      yield r'logSeq';
      yield serializers.serialize(
        object.logSeq,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    RunStatus object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RunStatusBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(InstanceStatus),
          ) as InstanceStatus;
          result.status = valueDes;
          break;
        case r'pid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.pid = valueDes;
          break;
        case r'exitCode':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.exitCode = valueDes;
          break;
        case r'serverPort':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.serverPort = valueDes;
          break;
        case r'onlineMode':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.onlineMode = valueDes;
          break;
        case r'onlinePlayers':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(String)]),
          ) as BuiltList<String>?;
          if (valueDes == null) continue;
          result.onlinePlayers.replace(valueDes);
          break;
        case r'logSeq':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.logSeq = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RunStatus deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RunStatusBuilder();
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

