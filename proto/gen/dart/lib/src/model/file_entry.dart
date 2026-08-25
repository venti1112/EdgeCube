//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'file_entry.g.dart';

/// FileEntry
///
/// Properties:
/// * [name] 
/// * [path] - 相对实例 cwd 的路径
/// * [isDirectory] 
/// * [sizeBytes] 
/// * [modifiedAt] 
/// * [executable] 
@BuiltValue()
abstract class FileEntry implements Built<FileEntry, FileEntryBuilder> {
  @BuiltValueField(wireName: r'name')
  String get name;

  /// 相对实例 cwd 的路径
  @BuiltValueField(wireName: r'path')
  String get path;

  @BuiltValueField(wireName: r'isDirectory')
  bool get isDirectory;

  @BuiltValueField(wireName: r'sizeBytes')
  int get sizeBytes;

  @BuiltValueField(wireName: r'modifiedAt')
  DateTime get modifiedAt;

  @BuiltValueField(wireName: r'executable')
  bool? get executable;

  FileEntry._();

  factory FileEntry([void updates(FileEntryBuilder b)]) = _$FileEntry;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(FileEntryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<FileEntry> get serializer => _$FileEntrySerializer();
}

class _$FileEntrySerializer implements PrimitiveSerializer<FileEntry> {
  @override
  final Iterable<Type> types = const [FileEntry, _$FileEntry];

  @override
  final String wireName = r'FileEntry';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    FileEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    yield r'path';
    yield serializers.serialize(
      object.path,
      specifiedType: const FullType(String),
    );
    yield r'isDirectory';
    yield serializers.serialize(
      object.isDirectory,
      specifiedType: const FullType(bool),
    );
    yield r'sizeBytes';
    yield serializers.serialize(
      object.sizeBytes,
      specifiedType: const FullType(int),
    );
    yield r'modifiedAt';
    yield serializers.serialize(
      object.modifiedAt,
      specifiedType: const FullType(DateTime),
    );
    if (object.executable != null) {
      yield r'executable';
      yield serializers.serialize(
        object.executable,
        specifiedType: const FullType.nullable(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    FileEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required FileEntryBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'path':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.path = valueDes;
          break;
        case r'isDirectory':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.isDirectory = valueDes;
          break;
        case r'sizeBytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.sizeBytes = valueDes;
          break;
        case r'modifiedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.modifiedAt = valueDes;
          break;
        case r'executable':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.executable = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  FileEntry deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = FileEntryBuilder();
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

