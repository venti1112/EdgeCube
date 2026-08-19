//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'upload_session.g.dart';

/// UploadSession
///
/// Properties:
/// * [uploadId] 
/// * [receivedBytes] - 已接收字节(断点续传:重连后从该偏移继续)
@BuiltValue()
abstract class UploadSession implements Built<UploadSession, UploadSessionBuilder> {
  @BuiltValueField(wireName: r'uploadId')
  String get uploadId;

  /// 已接收字节(断点续传:重连后从该偏移继续)
  @BuiltValueField(wireName: r'receivedBytes')
  int get receivedBytes;

  UploadSession._();

  factory UploadSession([void updates(UploadSessionBuilder b)]) = _$UploadSession;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UploadSessionBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UploadSession> get serializer => _$UploadSessionSerializer();
}

class _$UploadSessionSerializer implements PrimitiveSerializer<UploadSession> {
  @override
  final Iterable<Type> types = const [UploadSession, _$UploadSession];

  @override
  final String wireName = r'UploadSession';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UploadSession object, {
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
  }

  @override
  Object serialize(
    Serializers serializers,
    UploadSession object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required UploadSessionBuilder result,
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UploadSession deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UploadSessionBuilder();
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

