//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:edgecube_api_client/src/model/modrinth_version_file.dart';
import 'package:edgecube_api_client/src/model/modrinth_dependency.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'modrinth_version.g.dart';

/// ModrinthVersion
///
/// Properties:
/// * [id] 
/// * [projectId] 
/// * [name] 
/// * [versionNumber] 
/// * [gameVersions] 
/// * [loaders] 
/// * [files] 
/// * [dependencies] 
@BuiltValue()
abstract class ModrinthVersion implements Built<ModrinthVersion, ModrinthVersionBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'projectId')
  String get projectId;

  @BuiltValueField(wireName: r'name')
  String? get name;

  @BuiltValueField(wireName: r'versionNumber')
  String get versionNumber;

  @BuiltValueField(wireName: r'gameVersions')
  BuiltList<String>? get gameVersions;

  @BuiltValueField(wireName: r'loaders')
  BuiltList<String>? get loaders;

  @BuiltValueField(wireName: r'files')
  BuiltList<ModrinthVersionFile>? get files;

  @BuiltValueField(wireName: r'dependencies')
  BuiltList<ModrinthDependency>? get dependencies;

  ModrinthVersion._();

  factory ModrinthVersion([void updates(ModrinthVersionBuilder b)]) = _$ModrinthVersion;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ModrinthVersionBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ModrinthVersion> get serializer => _$ModrinthVersionSerializer();
}

class _$ModrinthVersionSerializer implements PrimitiveSerializer<ModrinthVersion> {
  @override
  final Iterable<Type> types = const [ModrinthVersion, _$ModrinthVersion];

  @override
  final String wireName = r'ModrinthVersion';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ModrinthVersion object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'projectId';
    yield serializers.serialize(
      object.projectId,
      specifiedType: const FullType(String),
    );
    if (object.name != null) {
      yield r'name';
      yield serializers.serialize(
        object.name,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'versionNumber';
    yield serializers.serialize(
      object.versionNumber,
      specifiedType: const FullType(String),
    );
    if (object.gameVersions != null) {
      yield r'gameVersions';
      yield serializers.serialize(
        object.gameVersions,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
    if (object.loaders != null) {
      yield r'loaders';
      yield serializers.serialize(
        object.loaders,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
    if (object.files != null) {
      yield r'files';
      yield serializers.serialize(
        object.files,
        specifiedType: const FullType(BuiltList, [FullType(ModrinthVersionFile)]),
      );
    }
    if (object.dependencies != null) {
      yield r'dependencies';
      yield serializers.serialize(
        object.dependencies,
        specifiedType: const FullType(BuiltList, [FullType(ModrinthDependency)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ModrinthVersion object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ModrinthVersionBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'projectId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.projectId = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.name = valueDes;
          break;
        case r'versionNumber':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.versionNumber = valueDes;
          break;
        case r'gameVersions':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(String)]),
          ) as BuiltList<String>?;
          if (valueDes == null) continue;
          result.gameVersions.replace(valueDes);
          break;
        case r'loaders':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(String)]),
          ) as BuiltList<String>?;
          if (valueDes == null) continue;
          result.loaders.replace(valueDes);
          break;
        case r'files':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(ModrinthVersionFile)]),
          ) as BuiltList<ModrinthVersionFile>?;
          if (valueDes == null) continue;
          result.files.replace(valueDes);
          break;
        case r'dependencies':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(ModrinthDependency)]),
          ) as BuiltList<ModrinthDependency>?;
          if (valueDes == null) continue;
          result.dependencies.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ModrinthVersion deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ModrinthVersionBuilder();
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

