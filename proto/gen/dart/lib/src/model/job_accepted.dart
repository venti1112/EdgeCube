//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'job_accepted.g.dart';

/// JobAccepted
///
/// Properties:
/// * [jobId] - 异步任务 id(进度经 WS 同名事件推送)
@BuiltValue()
abstract class JobAccepted implements Built<JobAccepted, JobAcceptedBuilder> {
  /// 异步任务 id(进度经 WS 同名事件推送)
  @BuiltValueField(wireName: r'jobId')
  String get jobId;

  JobAccepted._();

  factory JobAccepted([void updates(JobAcceptedBuilder b)]) = _$JobAccepted;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(JobAcceptedBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<JobAccepted> get serializer => _$JobAcceptedSerializer();
}

class _$JobAcceptedSerializer implements PrimitiveSerializer<JobAccepted> {
  @override
  final Iterable<Type> types = const [JobAccepted, _$JobAccepted];

  @override
  final String wireName = r'JobAccepted';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    JobAccepted object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'jobId';
    yield serializers.serialize(
      object.jobId,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    JobAccepted object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required JobAcceptedBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'jobId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.jobId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  JobAccepted deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = JobAcceptedBuilder();
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

