//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'modrinth_file_hashes.g.dart';

/// ModrinthFileHashes
///
/// Properties:
/// * [sha1] 
/// * [sha512] 
@BuiltValue()
abstract class ModrinthFileHashes implements Built<ModrinthFileHashes, ModrinthFileHashesBuilder> {
  @BuiltValueField(wireName: r'sha1')
  String? get sha1;

  @BuiltValueField(wireName: r'sha512')
  String? get sha512;

  ModrinthFileHashes._();

  factory ModrinthFileHashes([void updates(ModrinthFileHashesBuilder b)]) = _$ModrinthFileHashes;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ModrinthFileHashesBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ModrinthFileHashes> get serializer => _$ModrinthFileHashesSerializer();
}

class _$ModrinthFileHashesSerializer implements PrimitiveSerializer<ModrinthFileHashes> {
  @override
  final Iterable<Type> types = const [ModrinthFileHashes, _$ModrinthFileHashes];

  @override
  final String wireName = r'ModrinthFileHashes';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ModrinthFileHashes object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.sha1 != null) {
      yield r'sha1';
      yield serializers.serialize(
        object.sha1,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.sha512 != null) {
      yield r'sha512';
      yield serializers.serialize(
        object.sha512,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ModrinthFileHashes object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ModrinthFileHashesBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'sha1':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.sha1 = valueDes;
          break;
        case r'sha512':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.sha512 = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ModrinthFileHashes deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ModrinthFileHashesBuilder();
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

