//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:edgecube_api_client/src/model/modrinth_search_hit.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'modrinth_search_response.g.dart';

/// ModrinthSearchResponse
///
/// Properties:
/// * [hits] 
/// * [offset] 
/// * [limit] 
/// * [totalHits] 
@BuiltValue()
abstract class ModrinthSearchResponse implements Built<ModrinthSearchResponse, ModrinthSearchResponseBuilder> {
  @BuiltValueField(wireName: r'hits')
  BuiltList<ModrinthSearchHit> get hits;

  @BuiltValueField(wireName: r'offset')
  int get offset;

  @BuiltValueField(wireName: r'limit')
  int get limit;

  @BuiltValueField(wireName: r'totalHits')
  int get totalHits;

  ModrinthSearchResponse._();

  factory ModrinthSearchResponse([void updates(ModrinthSearchResponseBuilder b)]) = _$ModrinthSearchResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ModrinthSearchResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ModrinthSearchResponse> get serializer => _$ModrinthSearchResponseSerializer();
}

class _$ModrinthSearchResponseSerializer implements PrimitiveSerializer<ModrinthSearchResponse> {
  @override
  final Iterable<Type> types = const [ModrinthSearchResponse, _$ModrinthSearchResponse];

  @override
  final String wireName = r'ModrinthSearchResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ModrinthSearchResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'hits';
    yield serializers.serialize(
      object.hits,
      specifiedType: const FullType(BuiltList, [FullType(ModrinthSearchHit)]),
    );
    yield r'offset';
    yield serializers.serialize(
      object.offset,
      specifiedType: const FullType(int),
    );
    yield r'limit';
    yield serializers.serialize(
      object.limit,
      specifiedType: const FullType(int),
    );
    yield r'totalHits';
    yield serializers.serialize(
      object.totalHits,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ModrinthSearchResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ModrinthSearchResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'hits':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(ModrinthSearchHit)]),
          ) as BuiltList<ModrinthSearchHit>;
          result.hits.replace(valueDes);
          break;
        case r'offset':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.offset = valueDes;
          break;
        case r'limit':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.limit = valueDes;
          break;
        case r'totalHits':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.totalHits = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ModrinthSearchResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ModrinthSearchResponseBuilder();
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

