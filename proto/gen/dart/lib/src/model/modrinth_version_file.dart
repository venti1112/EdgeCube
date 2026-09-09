//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:edgecube_api_client/src/model/modrinth_file_hashes.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'modrinth_version_file.g.dart';

/// ModrinthVersionFile
///
/// Properties:
/// * [url] 
/// * [filename] 
/// * [primary] 
/// * [size] 
/// * [hashes] 
@BuiltValue()
abstract class ModrinthVersionFile implements Built<ModrinthVersionFile, ModrinthVersionFileBuilder> {
  @BuiltValueField(wireName: r'url')
  String get url;

  @BuiltValueField(wireName: r'filename')
  String get filename;

  @BuiltValueField(wireName: r'primary')
  bool get primary;

  @BuiltValueField(wireName: r'size')
  int? get size;

  @BuiltValueField(wireName: r'hashes')
  ModrinthFileHashes? get hashes;

  ModrinthVersionFile._();

  factory ModrinthVersionFile([void updates(ModrinthVersionFileBuilder b)]) = _$ModrinthVersionFile;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ModrinthVersionFileBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ModrinthVersionFile> get serializer => _$ModrinthVersionFileSerializer();
}

class _$ModrinthVersionFileSerializer implements PrimitiveSerializer<ModrinthVersionFile> {
  @override
  final Iterable<Type> types = const [ModrinthVersionFile, _$ModrinthVersionFile];

  @override
  final String wireName = r'ModrinthVersionFile';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ModrinthVersionFile object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'url';
    yield serializers.serialize(
      object.url,
      specifiedType: const FullType(String),
    );
    yield r'filename';
    yield serializers.serialize(
      object.filename,
      specifiedType: const FullType(String),
    );
    yield r'primary';
    yield serializers.serialize(
      object.primary,
      specifiedType: const FullType(bool),
    );
    if (object.size != null) {
      yield r'size';
      yield serializers.serialize(
        object.size,
        specifiedType: const FullType(int),
      );
    }
    if (object.hashes != null) {
      yield r'hashes';
      yield serializers.serialize(
        object.hashes,
        specifiedType: const FullType(ModrinthFileHashes),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ModrinthVersionFile object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ModrinthVersionFileBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'url':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.url = valueDes;
          break;
        case r'filename':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.filename = valueDes;
          break;
        case r'primary':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.primary = valueDes;
          break;
        case r'size':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.size = valueDes;
          break;
        case r'hashes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(ModrinthFileHashes),
          ) as ModrinthFileHashes?;
          if (valueDes == null) continue;
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
  ModrinthVersionFile deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ModrinthVersionFileBuilder();
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

