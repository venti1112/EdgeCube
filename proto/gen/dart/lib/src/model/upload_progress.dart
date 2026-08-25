//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'upload_progress.g.dart';

/// UploadProgress
///
/// Properties:
/// * [uploadId] 
/// * [receivedBytes] 
/// * [totalBytes] 
@BuiltValue()
abstract class UploadProgress implements Built<UploadProgress, UploadProgressBuilder> {
  @BuiltValueField(wireName: r'uploadId')
  String get uploadId;

  @BuiltValueField(wireName: r'receivedBytes')
  int get receivedBytes;

  @BuiltValueField(wireName: r'totalBytes')
  int get totalBytes;

  UploadProgress._();

  factory UploadProgress([void updates(UploadProgressBuilder b)]) = _$UploadProgress;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UploadProgressBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UploadProgress> get serializer => _$UploadProgressSerializer();
}

class _$UploadProgressSerializer implements PrimitiveSerializer<UploadProgress> {
  @override
  final Iterable<Type> types = const [UploadProgress, _$UploadProgress];

  @override
  final String wireName = r'UploadProgress';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UploadProgress object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'uploadId';
    yield serializers.serialize(
      object.uploadId,
      specifiedType: const FullType(String),
    );
    yield r'receivedBytes';
    yield serializers.serialize(
      object.receivedBytes,
      specifiedType: const FullType(int),
    );
    yield r'totalBytes';
    yield serializers.serialize(
      object.totalBytes,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    UploadProgress object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required UploadProgressBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'uploadId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.uploadId = valueDes;
          break;
        case r'receivedBytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.receivedBytes = valueDes;
          break;
        case r'totalBytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.totalBytes = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UploadProgress deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UploadProgressBuilder();
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

