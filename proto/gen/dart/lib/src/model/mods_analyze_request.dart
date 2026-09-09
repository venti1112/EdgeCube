//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'mods_analyze_request.g.dart';

/// ModsAnalyzeRequest
///
/// Properties:
/// * [path] - 相对实例 cwd 的目录,如 plugins / mods
@BuiltValue()
abstract class ModsAnalyzeRequest implements Built<ModsAnalyzeRequest, ModsAnalyzeRequestBuilder> {
  /// 相对实例 cwd 的目录,如 plugins / mods
  @BuiltValueField(wireName: r'path')
  String get path;

  ModsAnalyzeRequest._();

  factory ModsAnalyzeRequest([void updates(ModsAnalyzeRequestBuilder b)]) = _$ModsAnalyzeRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ModsAnalyzeRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ModsAnalyzeRequest> get serializer => _$ModsAnalyzeRequestSerializer();
}

class _$ModsAnalyzeRequestSerializer implements PrimitiveSerializer<ModsAnalyzeRequest> {
  @override
  final Iterable<Type> types = const [ModsAnalyzeRequest, _$ModsAnalyzeRequest];

  @override
  final String wireName = r'ModsAnalyzeRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ModsAnalyzeRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'path';
    yield serializers.serialize(
      object.path,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ModsAnalyzeRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ModsAnalyzeRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'path':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.path = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ModsAnalyzeRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ModsAnalyzeRequestBuilder();
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

