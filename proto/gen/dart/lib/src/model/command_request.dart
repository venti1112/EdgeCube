//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'command_request.g.dart';

/// CommandRequest
///
/// Properties:
/// * [command] - 一行命令(自动补换行)
@BuiltValue()
abstract class CommandRequest implements Built<CommandRequest, CommandRequestBuilder> {
  /// 一行命令(自动补换行)
  @BuiltValueField(wireName: r'command')
  String get command;

  CommandRequest._();

  factory CommandRequest([void updates(CommandRequestBuilder b)]) = _$CommandRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CommandRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CommandRequest> get serializer => _$CommandRequestSerializer();
}

class _$CommandRequestSerializer implements PrimitiveSerializer<CommandRequest> {
  @override
  final Iterable<Type> types = const [CommandRequest, _$CommandRequest];

  @override
  final String wireName = r'CommandRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CommandRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'command';
    yield serializers.serialize(
      object.command,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CommandRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CommandRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'command':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.command = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CommandRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CommandRequestBuilder();
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

