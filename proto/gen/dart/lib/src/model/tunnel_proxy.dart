//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:edgecube_api_client/src/model/proxy_type.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'tunnel_proxy.g.dart';

/// TunnelProxy
///
/// Properties:
/// * [name] - 代理名称(隧道内唯一)
/// * [type] 
/// * [localIp] - 本地服务地址(如 127.0.0.1)
/// * [localPort] 
/// * [remotePort] - tcp/udp 必填;http/https 无需
/// * [customDomains] - http/https 必填(至少一个域名);tcp/udp 忽略
@BuiltValue()
abstract class TunnelProxy implements Built<TunnelProxy, TunnelProxyBuilder> {
  /// 代理名称(隧道内唯一)
  @BuiltValueField(wireName: r'name')
  String get name;

  @BuiltValueField(wireName: r'type')
  ProxyType get type;
  // enum typeEnum {  tcp,  udp,  http,  https,  };

  /// 本地服务地址(如 127.0.0.1)
  @BuiltValueField(wireName: r'localIp')
  String get localIp;

  @BuiltValueField(wireName: r'localPort')
  int get localPort;

  /// tcp/udp 必填;http/https 无需
  @BuiltValueField(wireName: r'remotePort')
  int? get remotePort;

  /// http/https 必填(至少一个域名);tcp/udp 忽略
  @BuiltValueField(wireName: r'customDomains')
  BuiltList<String>? get customDomains;

  TunnelProxy._();

  factory TunnelProxy([void updates(TunnelProxyBuilder b)]) = _$TunnelProxy;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(TunnelProxyBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<TunnelProxy> get serializer => _$TunnelProxySerializer();
}

class _$TunnelProxySerializer implements PrimitiveSerializer<TunnelProxy> {
  @override
  final Iterable<Type> types = const [TunnelProxy, _$TunnelProxy];

  @override
  final String wireName = r'TunnelProxy';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    TunnelProxy object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    yield r'type';
    yield serializers.serialize(
      object.type,
      specifiedType: const FullType(ProxyType),
    );
    yield r'localIp';
    yield serializers.serialize(
      object.localIp,
      specifiedType: const FullType(String),
    );
    yield r'localPort';
    yield serializers.serialize(
      object.localPort,
      specifiedType: const FullType(int),
    );
    if (object.remotePort != null) {
      yield r'remotePort';
      yield serializers.serialize(
        object.remotePort,
        specifiedType: const FullType(int),
      );
    }
    if (object.customDomains != null) {
      yield r'customDomains';
      yield serializers.serialize(
        object.customDomains,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    TunnelProxy object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required TunnelProxyBuilder result,
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
        case r'type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ProxyType),
          ) as ProxyType;
          result.type = valueDes;
          break;
        case r'localIp':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.localIp = valueDes;
          break;
        case r'localPort':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.localPort = valueDes;
          break;
        case r'remotePort':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.remotePort = valueDes;
          break;
        case r'customDomains':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(String)]),
          ) as BuiltList<String>?;
          if (valueDes == null) continue;
          result.customDomains.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  TunnelProxy deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = TunnelProxyBuilder();
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

