//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'modrinth_version_files_request.g.dart';

/// ModrinthVersionFilesRequest
///
/// Properties:
/// * [hashes] - 文件 SHA1(小写 hex)列表
@BuiltValue()
abstract class ModrinthVersionFilesRequest implements Built<ModrinthVersionFilesRequest, ModrinthVersionFilesRequestBuilder> {
  /// 文件 SHA1(小写 hex)列表
  @BuiltValueField(wireName: r'hashes')
  BuiltList<String> get hashes;

  ModrinthVersionFilesRequest._();

  factory ModrinthVersionFilesRequest([void updates(ModrinthVersionFilesRequestBuilder b)]) = _$ModrinthVersionFilesRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ModrinthVersionFilesRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ModrinthVersionFilesRequest> get serializer => _$ModrinthVersionFilesRequestSerializer();
}

class _$ModrinthVersionFilesRequestSerializer implements PrimitiveSerializer<ModrinthVersionFilesRequest> {
  @override
  final Iterable<Type> types = const [ModrinthVersionFilesRequest, _$ModrinthVersionFilesRequest];

  @override
  final String wireName = r'ModrinthVersionFilesRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ModrinthVersionFilesRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'hashes';
    yield serializers.serialize(
      object.hashes,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ModrinthVersionFilesRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ModrinthVersionFilesRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'hashes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.hashes.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ModrinthVersionFilesRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ModrinthVersionFilesRequestBuilder();
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

