//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'fs_write_request.g.dart';

/// FsWriteRequest
///
/// Properties:
/// * [instanceId] 
/// * [path] - 目标文件路径(相对实例 cwd),父目录须已存在
/// * [content] - UTF-8 文本内容(上限 16 MiB)
@BuiltValue()
abstract class FsWriteRequest implements Built<FsWriteRequest, FsWriteRequestBuilder> {
  @BuiltValueField(wireName: r'instanceId')
  String get instanceId;

  /// 目标文件路径(相对实例 cwd),父目录须已存在
  @BuiltValueField(wireName: r'path')
  String get path;

  /// UTF-8 文本内容(上限 16 MiB)
  @BuiltValueField(wireName: r'content')
  String get content;

  FsWriteRequest._();

  factory FsWriteRequest([void updates(FsWriteRequestBuilder b)]) = _$FsWriteRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(FsWriteRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<FsWriteRequest> get serializer => _$FsWriteRequestSerializer();
}

class _$FsWriteRequestSerializer implements PrimitiveSerializer<FsWriteRequest> {
  @override
  final Iterable<Type> types = const [FsWriteRequest, _$FsWriteRequest];

  @override
  final String wireName = r'FsWriteRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    FsWriteRequest object, {
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
    yield r'content';
    yield serializers.serialize(
      object.content,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    FsWriteRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required FsWriteRequestBuilder result,
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
        case r'content':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.content = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  FsWriteRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = FsWriteRequestBuilder();
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

