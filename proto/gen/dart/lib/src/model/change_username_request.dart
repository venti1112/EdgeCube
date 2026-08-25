//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'change_username_request.g.dart';

/// ChangeUsernameRequest
///
/// Properties:
/// * [password] - 当前密码(二次验证)
/// * [newUsername] 
@BuiltValue()
abstract class ChangeUsernameRequest implements Built<ChangeUsernameRequest, ChangeUsernameRequestBuilder> {
  /// 当前密码(二次验证)
  @BuiltValueField(wireName: r'password')
  String get password;

  @BuiltValueField(wireName: r'newUsername')
  String get newUsername;

  ChangeUsernameRequest._();

  factory ChangeUsernameRequest([void updates(ChangeUsernameRequestBuilder b)]) = _$ChangeUsernameRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ChangeUsernameRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ChangeUsernameRequest> get serializer => _$ChangeUsernameRequestSerializer();
}

class _$ChangeUsernameRequestSerializer implements PrimitiveSerializer<ChangeUsernameRequest> {
  @override
  final Iterable<Type> types = const [ChangeUsernameRequest, _$ChangeUsernameRequest];

  @override
  final String wireName = r'ChangeUsernameRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ChangeUsernameRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'password';
    yield serializers.serialize(
      object.password,
      specifiedType: const FullType(String),
    );
    yield r'newUsername';
    yield serializers.serialize(
      object.newUsername,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ChangeUsernameRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ChangeUsernameRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'password':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.password = valueDes;
          break;
        case r'newUsername':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.newUsername = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ChangeUsernameRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ChangeUsernameRequestBuilder();
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

