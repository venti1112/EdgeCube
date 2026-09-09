//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'clear_finished_mod_downloads200_response.g.dart';

/// ClearFinishedModDownloads200Response
///
/// Properties:
/// * [cleared] - 被清除的任务数量
@BuiltValue()
abstract class ClearFinishedModDownloads200Response implements Built<ClearFinishedModDownloads200Response, ClearFinishedModDownloads200ResponseBuilder> {
  /// 被清除的任务数量
  @BuiltValueField(wireName: r'cleared')
  int? get cleared;

  ClearFinishedModDownloads200Response._();

  factory ClearFinishedModDownloads200Response([void updates(ClearFinishedModDownloads200ResponseBuilder b)]) = _$ClearFinishedModDownloads200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ClearFinishedModDownloads200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ClearFinishedModDownloads200Response> get serializer => _$ClearFinishedModDownloads200ResponseSerializer();
}

class _$ClearFinishedModDownloads200ResponseSerializer implements PrimitiveSerializer<ClearFinishedModDownloads200Response> {
  @override
  final Iterable<Type> types = const [ClearFinishedModDownloads200Response, _$ClearFinishedModDownloads200Response];

  @override
  final String wireName = r'ClearFinishedModDownloads200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ClearFinishedModDownloads200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.cleared != null) {
      yield r'cleared';
      yield serializers.serialize(
        object.cleared,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ClearFinishedModDownloads200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ClearFinishedModDownloads200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'cleared':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.cleared = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ClearFinishedModDownloads200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ClearFinishedModDownloads200ResponseBuilder();
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

