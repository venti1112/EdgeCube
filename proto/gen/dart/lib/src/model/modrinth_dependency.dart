//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'modrinth_dependency.g.dart';

/// ModrinthDependency
///
/// Properties:
/// * [projectId] 
/// * [versionId] 
/// * [dependencyType] 
@BuiltValue()
abstract class ModrinthDependency implements Built<ModrinthDependency, ModrinthDependencyBuilder> {
  @BuiltValueField(wireName: r'projectId')
  String? get projectId;

  @BuiltValueField(wireName: r'versionId')
  String? get versionId;

  @BuiltValueField(wireName: r'dependencyType')
  String get dependencyType;

  ModrinthDependency._();

  factory ModrinthDependency([void updates(ModrinthDependencyBuilder b)]) = _$ModrinthDependency;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ModrinthDependencyBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ModrinthDependency> get serializer => _$ModrinthDependencySerializer();
}

class _$ModrinthDependencySerializer implements PrimitiveSerializer<ModrinthDependency> {
  @override
  final Iterable<Type> types = const [ModrinthDependency, _$ModrinthDependency];

  @override
  final String wireName = r'ModrinthDependency';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ModrinthDependency object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.projectId != null) {
      yield r'projectId';
      yield serializers.serialize(
        object.projectId,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.versionId != null) {
      yield r'versionId';
      yield serializers.serialize(
        object.versionId,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'dependencyType';
    yield serializers.serialize(
      object.dependencyType,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ModrinthDependency object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ModrinthDependencyBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'projectId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.projectId = valueDes;
          break;
        case r'versionId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.versionId = valueDes;
          break;
        case r'dependencyType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.dependencyType = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ModrinthDependency deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ModrinthDependencyBuilder();
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

