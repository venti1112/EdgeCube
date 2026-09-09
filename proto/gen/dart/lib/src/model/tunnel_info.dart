//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:edgecube_api_client/src/model/tunnel_proxy.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'tunnel_info.g.dart';

/// TunnelInfo
///
/// Properties:
/// * [id] 
/// * [name] 
/// * [serverAddr] - frps 服务端地址(域名/IP)
/// * [serverPort] 
/// * [user] - frps 用户名(可选)
/// * [authToken] - frps 鉴权 token(可选)
/// * [proxies] 
/// * [createdAt] 
/// * [updatedAt] 
@BuiltValue()
abstract class TunnelInfo implements Built<TunnelInfo, TunnelInfoBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'name')
  String get name;

  /// frps 服务端地址(域名/IP)
  @BuiltValueField(wireName: r'serverAddr')
  String get serverAddr;

  @BuiltValueField(wireName: r'serverPort')
  int get serverPort;

  /// frps 用户名(可选)
  @BuiltValueField(wireName: r'user')
  String? get user;

  /// frps 鉴权 token(可选)
  @BuiltValueField(wireName: r'authToken')
  String? get authToken;

  @BuiltValueField(wireName: r'proxies')
  BuiltList<TunnelProxy> get proxies;

  @BuiltValueField(wireName: r'createdAt')
  DateTime get createdAt;

  @BuiltValueField(wireName: r'updatedAt')
  DateTime get updatedAt;

  TunnelInfo._();

  factory TunnelInfo([void updates(TunnelInfoBuilder b)]) = _$TunnelInfo;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(TunnelInfoBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<TunnelInfo> get serializer => _$TunnelInfoSerializer();
}

class _$TunnelInfoSerializer implements PrimitiveSerializer<TunnelInfo> {
  @override
  final Iterable<Type> types = const [TunnelInfo, _$TunnelInfo];

  @override
  final String wireName = r'TunnelInfo';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    TunnelInfo object, {
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
    yield r'serverAddr';
    yield serializers.serialize(
      object.serverAddr,
      specifiedType: const FullType(String),
    );
    yield r'serverPort';
    yield serializers.serialize(
      object.serverPort,
      specifiedType: const FullType(int),
    );
    if (object.user != null) {
      yield r'user';
      yield serializers.serialize(
        object.user,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.authToken != null) {
      yield r'authToken';
      yield serializers.serialize(
        object.authToken,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'proxies';
    yield serializers.serialize(
      object.proxies,
      specifiedType: const FullType(BuiltList, [FullType(TunnelProxy)]),
    );
    yield r'createdAt';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
    yield r'updatedAt';
    yield serializers.serialize(
      object.updatedAt,
      specifiedType: const FullType(DateTime),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    TunnelInfo object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required TunnelInfoBuilder result,
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
        case r'serverAddr':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.serverAddr = valueDes;
          break;
        case r'serverPort':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.serverPort = valueDes;
          break;
        case r'user':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.user = valueDes;
          break;
        case r'authToken':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.authToken = valueDes;
          break;
        case r'proxies':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(TunnelProxy)]),
          ) as BuiltList<TunnelProxy>;
          result.proxies.replace(valueDes);
          break;
        case r'createdAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        case r'updatedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.updatedAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  TunnelInfo deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = TunnelInfoBuilder();
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

