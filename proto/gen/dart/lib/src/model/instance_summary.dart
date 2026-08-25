//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:edgecube_api_client/src/model/instance_status.dart';
import 'package:edgecube_api_client/src/model/instance_type.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'instance_summary.g.dart';

/// InstanceSummary
///
/// Properties:
/// * [id] 
/// * [name] 
/// * [status] 
/// * [type] 
/// * [pid] 
/// * [runningSince] 
/// * [autoRestart] 
/// * [autoStartOnBoot] 
/// * [port] - 附加层解析出的服务端监听端口
/// * [onlinePlayers] - 附加层解析出的在线人数
@BuiltValue()
abstract class InstanceSummary implements Built<InstanceSummary, InstanceSummaryBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'name')
  String get name;

  @BuiltValueField(wireName: r'status')
  InstanceStatus get status;
  // enum statusEnum {  busy,  stopped,  stopping,  starting,  running,  };

  @BuiltValueField(wireName: r'type')
  InstanceType get type;
  // enum typeEnum {  minecraft-java,  minecraft-bedrock,  pocketmine,  generic,  };

  @BuiltValueField(wireName: r'pid')
  int? get pid;

  @BuiltValueField(wireName: r'runningSince')
  DateTime? get runningSince;

  @BuiltValueField(wireName: r'autoRestart')
  bool? get autoRestart;

  @BuiltValueField(wireName: r'autoStartOnBoot')
  bool? get autoStartOnBoot;

  /// 附加层解析出的服务端监听端口
  @BuiltValueField(wireName: r'port')
  int? get port;

  /// 附加层解析出的在线人数
  @BuiltValueField(wireName: r'onlinePlayers')
  int? get onlinePlayers;

  InstanceSummary._();

  factory InstanceSummary([void updates(InstanceSummaryBuilder b)]) = _$InstanceSummary;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(InstanceSummaryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<InstanceSummary> get serializer => _$InstanceSummarySerializer();
}

class _$InstanceSummarySerializer implements PrimitiveSerializer<InstanceSummary> {
  @override
  final Iterable<Type> types = const [InstanceSummary, _$InstanceSummary];

  @override
  final String wireName = r'InstanceSummary';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    InstanceSummary object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(InstanceStatus),
    );
    yield r'type';
    yield serializers.serialize(
      object.type,
      specifiedType: const FullType(InstanceType),
    );
    if (object.pid != null) {
      yield r'pid';
      yield serializers.serialize(
        object.pid,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.runningSince != null) {
      yield r'runningSince';
      yield serializers.serialize(
        object.runningSince,
        specifiedType: const FullType.nullable(DateTime),
      );
    }
    if (object.autoRestart != null) {
      yield r'autoRestart';
      yield serializers.serialize(
        object.autoRestart,
        specifiedType: const FullType(bool),
      );
    }
    if (object.autoStartOnBoot != null) {
      yield r'autoStartOnBoot';
      yield serializers.serialize(
        object.autoStartOnBoot,
        specifiedType: const FullType(bool),
      );
    }
    if (object.port != null) {
      yield r'port';
      yield serializers.serialize(
        object.port,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.onlinePlayers != null) {
      yield r'onlinePlayers';
      yield serializers.serialize(
        object.onlinePlayers,
        specifiedType: const FullType.nullable(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    InstanceSummary object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required InstanceSummaryBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(InstanceStatus),
          ) as InstanceStatus;
          result.status = valueDes;
          break;
        case r'type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(InstanceType),
          ) as InstanceType;
          result.type = valueDes;
          break;
        case r'pid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.pid = valueDes;
          break;
        case r'runningSince':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(DateTime),
          ) as DateTime?;
          if (valueDes == null) continue;
          result.runningSince = valueDes;
          break;
        case r'autoRestart':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.autoRestart = valueDes;
          break;
        case r'autoStartOnBoot':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.autoStartOnBoot = valueDes;
          break;
        case r'port':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.port = valueDes;
          break;
        case r'onlinePlayers':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.onlinePlayers = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  InstanceSummary deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = InstanceSummaryBuilder();
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

