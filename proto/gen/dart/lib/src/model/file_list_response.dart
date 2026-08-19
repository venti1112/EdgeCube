//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:edgecube_api_client/src/model/file_entry.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'file_list_response.g.dart';

/// FileListResponse
///
/// Properties:
/// * [path] 
/// * [entries] 
@BuiltValue()
abstract class FileListResponse implements Built<FileListResponse, FileListResponseBuilder> {
  @BuiltValueField(wireName: r'path')
  String get path;

  @BuiltValueField(wireName: r'entries')
  BuiltList<FileEntry> get entries;

  FileListResponse._();

  factory FileListResponse([void updates(FileListResponseBuilder b)]) = _$FileListResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(FileListResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<FileListResponse> get serializer => _$FileListResponseSerializer();
}

class _$FileListResponseSerializer implements PrimitiveSerializer<FileListResponse> {
  @override
  final Iterable<Type> types = const [FileListResponse, _$FileListResponse];

  @override
  final String wireName = r'FileListResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    FileListResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'path';
    yield serializers.serialize(
      object.path,
      specifiedType: const FullType(String),
    );
    yield r'entries';
    yield serializers.serialize(
      object.entries,
      specifiedType: const FullType(BuiltList, [FullType(FileEntry)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    FileListResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required FileListResponseBuilder result,
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
        case r'entries':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(FileEntry)]),
          ) as BuiltList<FileEntry>;
          result.entries.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  FileListResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = FileListResponseBuilder();
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

