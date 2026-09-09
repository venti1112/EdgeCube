//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:edgecube_api_client/src/model/mod_metadata.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'mod_metadata_entry.g.dart';

/// ModMetadataEntry
///
/// Properties:
/// * [path] - 相对实例 cwd 的路径
/// * [name] 
/// * [sizeBytes] 
/// * [sha1] - 文件 SHA1(小写 hex),供更新检查(Modrinth version_files)与图标查询
/// * [iconUrl] - 图标 URL(后端经 Modrinth 查询,尽力而为;失败/不可得为 null)
/// * [metadata] - 未识别/未解析时为 null
@BuiltValue()
abstract class ModMetadataEntry implements Built<ModMetadataEntry, ModMetadataEntryBuilder> {
  /// 相对实例 cwd 的路径
  @BuiltValueField(wireName: r'path')
  String get path;

  @BuiltValueField(wireName: r'name')
  String get name;

  @BuiltValueField(wireName: r'sizeBytes')
  int get sizeBytes;

  /// 文件 SHA1(小写 hex),供更新检查(Modrinth version_files)与图标查询
  @BuiltValueField(wireName: r'sha1')
  String? get sha1;

  /// 图标 URL(后端经 Modrinth 查询,尽力而为;失败/不可得为 null)
  @BuiltValueField(wireName: r'iconUrl')
  String? get iconUrl;

  /// 未识别/未解析时为 null
  @BuiltValueField(wireName: r'metadata')
  ModMetadata? get metadata;

  ModMetadataEntry._();

  factory ModMetadataEntry([void updates(ModMetadataEntryBuilder b)]) = _$ModMetadataEntry;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ModMetadataEntryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ModMetadataEntry> get serializer => _$ModMetadataEntrySerializer();
}

class _$ModMetadataEntrySerializer implements PrimitiveSerializer<ModMetadataEntry> {
  @override
  final Iterable<Type> types = const [ModMetadataEntry, _$ModMetadataEntry];

  @override
  final String wireName = r'ModMetadataEntry';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ModMetadataEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'path';
    yield serializers.serialize(
      object.path,
      specifiedType: const FullType(String),
    );
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    yield r'sizeBytes';
    yield serializers.serialize(
      object.sizeBytes,
      specifiedType: const FullType(int),
    );
    if (object.sha1 != null) {
      yield r'sha1';
      yield serializers.serialize(
        object.sha1,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.iconUrl != null) {
      yield r'iconUrl';
      yield serializers.serialize(
        object.iconUrl,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'metadata';
    yield object.metadata == null ? null : serializers.serialize(
      object.metadata,
      specifiedType: const FullType.nullable(ModMetadata),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ModMetadataEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ModMetadataEntryBuilder result,
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
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'sizeBytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.sizeBytes = valueDes;
          break;
        case r'sha1':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.sha1 = valueDes;
          break;
        case r'iconUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.iconUrl = valueDes;
          break;
        case r'metadata':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(ModMetadata),
          ) as ModMetadata?;
          if (valueDes == null) continue;
          result.metadata.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ModMetadataEntry deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ModMetadataEntryBuilder();
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

