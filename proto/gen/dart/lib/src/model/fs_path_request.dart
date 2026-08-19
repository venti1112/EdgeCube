//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'fs_path_request.g.dart';

/// FsPathRequest
///
/// Properties:
/// * [instanceId] 
/// * [path] 
@BuiltValue()
abstract class FsPathRequest implements Built<FsPathRequest, FsPathRequestBuilder> {
  @BuiltValueField(wireName: r'instanceId')
  String get instanceId;

  @BuiltValueField(wireName: r'path')
  String get path;

  FsPathRequest._();

  factory FsPathRequest([void updates(FsPathRequestBuilder b)]) = _$FsPathRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(FsPathRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<FsPathRequest> get serializer => _$FsPathRequestSerializer();
}

class _$FsPathRequestSerializer implements PrimitiveSerializer<FsPathRequest> {
  @override
  final Iterable<Type> types = const [FsPathRequest, _$FsPathRequest];

  @override
  final String wireName = r'FsPathRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    FsPathRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'instanceId';
    yield serializers.serialize(
      object.instanceId,
      specifiedType: const FullType(String),
    );
    yield r'path';
    yield serializers.serialize(
      object.path,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    FsPathRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required FsPathRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'instanceId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.instanceId = valueDes;
          break;
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
  FsPathRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = FsPathRequestBuilder();
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

