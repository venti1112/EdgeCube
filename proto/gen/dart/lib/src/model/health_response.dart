//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:edgecube_api_client/src/model/health_response_instances.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'health_response.g.dart';

/// HealthResponse
///
/// Properties:
/// * [status] 
/// * [version] - daemon 版本
/// * [daemon] 
/// * [platform] 
/// * [uptimeSeconds] 
/// * [instances] 
@BuiltValue()
abstract class HealthResponse implements Built<HealthResponse, HealthResponseBuilder> {
  @BuiltValueField(wireName: r'status')
  HealthResponseStatusEnum get status;
  // enum statusEnum {  ok,  degraded,  };

  /// daemon 版本
  @BuiltValueField(wireName: r'version')
  String get version;

  @BuiltValueField(wireName: r'daemon')
  HealthResponseDaemonEnum get daemon;
  // enum daemonEnum {  rust,  kotlin,  };

  @BuiltValueField(wireName: r'platform')
  String get platform;

  @BuiltValueField(wireName: r'uptimeSeconds')
  int get uptimeSeconds;

  @BuiltValueField(wireName: r'instances')
  HealthResponseInstances? get instances;

  HealthResponse._();

  factory HealthResponse([void updates(HealthResponseBuilder b)]) = _$HealthResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(HealthResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<HealthResponse> get serializer => _$HealthResponseSerializer();
}

class _$HealthResponseSerializer implements PrimitiveSerializer<HealthResponse> {
  @override
  final Iterable<Type> types = const [HealthResponse, _$HealthResponse];

  @override
  final String wireName = r'HealthResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    HealthResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(HealthResponseStatusEnum),
    );
    yield r'version';
    yield serializers.serialize(
      object.version,
      specifiedType: const FullType(String),
    );
    yield r'daemon';
    yield serializers.serialize(
      object.daemon,
      specifiedType: const FullType(HealthResponseDaemonEnum),
    );
    yield r'platform';
    yield serializers.serialize(
      object.platform,
      specifiedType: const FullType(String),
    );
    yield r'uptimeSeconds';
    yield serializers.serialize(
      object.uptimeSeconds,
      specifiedType: const FullType(int),
    );
    if (object.instances != null) {
      yield r'instances';
      yield serializers.serialize(
        object.instances,
        specifiedType: const FullType(HealthResponseInstances),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    HealthResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required HealthResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(HealthResponseStatusEnum),
          ) as HealthResponseStatusEnum;
          result.status = valueDes;
          break;
        case r'version':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.version = valueDes;
          break;
        case r'daemon':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(HealthResponseDaemonEnum),
          ) as HealthResponseDaemonEnum;
          result.daemon = valueDes;
          break;
        case r'platform':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.platform = valueDes;
          break;
        case r'uptimeSeconds':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.uptimeSeconds = valueDes;
          break;
        case r'instances':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(HealthResponseInstances),
          ) as HealthResponseInstances?;
          if (valueDes == null) continue;
          result.instances.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  HealthResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = HealthResponseBuilder();
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

class HealthResponseStatusEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'ok')
  static const HealthResponseStatusEnum ok = _$healthResponseStatusEnum_ok;
  @BuiltValueEnumConst(wireName: r'degraded')
  static const HealthResponseStatusEnum degraded = _$healthResponseStatusEnum_degraded;

  static Serializer<HealthResponseStatusEnum> get serializer => _$healthResponseStatusEnumSerializer;

  const HealthResponseStatusEnum._(String name): super(name);

  static BuiltSet<HealthResponseStatusEnum> get values => _$healthResponseStatusEnumValues;
  static HealthResponseStatusEnum valueOf(String name) => _$healthResponseStatusEnumValueOf(name);
}

class HealthResponseDaemonEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'rust')
  static const HealthResponseDaemonEnum rust = _$healthResponseDaemonEnum_rust;
  @BuiltValueEnumConst(wireName: r'kotlin')
  static const HealthResponseDaemonEnum kotlin = _$healthResponseDaemonEnum_kotlin;

  static Serializer<HealthResponseDaemonEnum> get serializer => _$healthResponseDaemonEnumSerializer;

  const HealthResponseDaemonEnum._(String name): super(name);

  static BuiltSet<HealthResponseDaemonEnum> get values => _$healthResponseDaemonEnumValues;
  static HealthResponseDaemonEnum valueOf(String name) => _$healthResponseDaemonEnumValueOf(name);
}

