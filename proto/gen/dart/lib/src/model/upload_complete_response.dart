//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'upload_complete_response.g.dart';

/// UploadCompleteResponse
///
/// Properties:
/// * [path] - 落盘路径(相对实例 cwd)
@BuiltValue()
abstract class UploadCompleteResponse implements Built<UploadCompleteResponse, UploadCompleteResponseBuilder> {
  /// 落盘路径(相对实例 cwd)
  @BuiltValueField(wireName: r'path')
  String get path;

  UploadCompleteResponse._();

  factory UploadCompleteResponse([void updates(UploadCompleteResponseBuilder b)]) = _$UploadCompleteResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UploadCompleteResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UploadCompleteResponse> get serializer => _$UploadCompleteResponseSerializer();
}

class _$UploadCompleteResponseSerializer implements PrimitiveSerializer<UploadCompleteResponse> {
  @override
  final Iterable<Type> types = const [UploadCompleteResponse, _$UploadCompleteResponse];

  @override
  final String wireName = r'UploadCompleteResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UploadCompleteResponse object, {
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
    UploadCompleteResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required UploadCompleteResponseBuilder result,
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
  UploadCompleteResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UploadCompleteResponseBuilder();
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

