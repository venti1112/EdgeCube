//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:edgecube_api_client/src/model/mod_metadata_entry.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'mod_metadata_list_response.g.dart';

/// ModMetadataListResponse
///
/// Properties:
/// * [path] 
/// * [items] 
@BuiltValue()
abstract class ModMetadataListResponse implements Built<ModMetadataListResponse, ModMetadataListResponseBuilder> {
  @BuiltValueField(wireName: r'path')
  String get path;

  @BuiltValueField(wireName: r'items')
  BuiltList<ModMetadataEntry> get items;

  ModMetadataListResponse._();

  factory ModMetadataListResponse([void updates(ModMetadataListResponseBuilder b)]) = _$ModMetadataListResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ModMetadataListResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ModMetadataListResponse> get serializer => _$ModMetadataListResponseSerializer();
}

class _$ModMetadataListResponseSerializer implements PrimitiveSerializer<ModMetadataListResponse> {
  @override
  final Iterable<Type> types = const [ModMetadataListResponse, _$ModMetadataListResponse];

  @override
  final String wireName = r'ModMetadataListResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ModMetadataListResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'path';
    yield serializers.serialize(
      object.path,
      specifiedType: const FullType(String),
    );
    yield r'items';
    yield serializers.serialize(
      object.items,
      specifiedType: const FullType(BuiltList, [FullType(ModMetadataEntry)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ModMetadataListResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ModMetadataListResponseBuilder result,
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
        case r'items':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(ModMetadataEntry)]),
          ) as BuiltList<ModMetadataEntry>;
          result.items.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ModMetadataListResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ModMetadataListResponseBuilder();
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

