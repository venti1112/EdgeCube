//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'fs_compress_request.g.dart';

/// FsCompressRequest
///
/// Properties:
/// * [instanceId] 
/// * [path] - 待压缩目录/文件
/// * [destName] - 归档文件名,缺省取源名
@BuiltValue()
abstract class FsCompressRequest implements Built<FsCompressRequest, FsCompressRequestBuilder> {
  @BuiltValueField(wireName: r'instanceId')
  String get instanceId;

  /// 待压缩目录/文件
  @BuiltValueField(wireName: r'path')
  String get path;

  /// 归档文件名,缺省取源名
  @BuiltValueField(wireName: r'destName')
  String? get destName;

  FsCompressRequest._();

  factory FsCompressRequest([void updates(FsCompressRequestBuilder b)]) = _$FsCompressRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(FsCompressRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<FsCompressRequest> get serializer => _$FsCompressRequestSerializer();
}

class _$FsCompressRequestSerializer implements PrimitiveSerializer<FsCompressRequest> {
  @override
  final Iterable<Type> types = const [FsCompressRequest, _$FsCompressRequest];

  @override
  final String wireName = r'FsCompressRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    FsCompressRequest object, {
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
    if (object.destName != null) {
      yield r'destName';
      yield serializers.serialize(
        object.destName,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    FsCompressRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required FsCompressRequestBuilder result,
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
        case r'destName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.destName = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  FsCompressRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = FsCompressRequestBuilder();
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

