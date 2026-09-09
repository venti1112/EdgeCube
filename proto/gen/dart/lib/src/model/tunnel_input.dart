//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:edgecube_api_client/src/model/tunnel_proxy.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'tunnel_input.g.dart';

/// TunnelInput
///
/// Properties:
/// * [name] 
/// * [serverAddr] 
/// * [serverPort] 
/// * [user] 
/// * [authToken] 
/// * [proxies] 
@BuiltValue()
abstract class TunnelInput implements Built<TunnelInput, TunnelInputBuilder> {
  @BuiltValueField(wireName: r'name')
  String get name;

  @BuiltValueField(wireName: r'serverAddr')
  String get serverAddr;

  @BuiltValueField(wireName: r'serverPort')
  int get serverPort;

  @BuiltValueField(wireName: r'user')
  String? get user;

  @BuiltValueField(wireName: r'authToken')
  String? get authToken;

  @BuiltValueField(wireName: r'proxies')
  BuiltList<TunnelProxy> get proxies;

  TunnelInput._();

  factory TunnelInput([void updates(TunnelInputBuilder b)]) = _$TunnelInput;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(TunnelInputBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<TunnelInput> get serializer => _$TunnelInputSerializer();
}

class _$TunnelInputSerializer implements PrimitiveSerializer<TunnelInput> {
  @override
  final Iterable<Type> types = const [TunnelInput, _$TunnelInput];

  @override
  final String wireName = r'TunnelInput';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    TunnelInput object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
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
  }

  @override
  Object serialize(
    Serializers serializers,
    TunnelInput object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required TunnelInputBuilder result,
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  TunnelInput deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = TunnelInputBuilder();
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

