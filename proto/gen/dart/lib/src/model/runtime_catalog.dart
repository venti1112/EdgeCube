//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:edgecube_api_client/src/model/runtime_type.dart';
import 'package:built_collection/built_collection.dart';
import 'package:edgecube_api_client/src/model/runtime_catalog_entry.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'runtime_catalog.g.dart';

/// RuntimeCatalog
///
/// Properties:
/// * [type] 
/// * [entries] 
@BuiltValue()
abstract class RuntimeCatalog implements Built<RuntimeCatalog, RuntimeCatalogBuilder> {
  @BuiltValueField(wireName: r'type')
  RuntimeType get type;
  // enum typeEnum {  java,  php,  frpc,  };

  @BuiltValueField(wireName: r'entries')
  BuiltList<RuntimeCatalogEntry> get entries;

  RuntimeCatalog._();

  factory RuntimeCatalog([void updates(RuntimeCatalogBuilder b)]) = _$RuntimeCatalog;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RuntimeCatalogBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RuntimeCatalog> get serializer => _$RuntimeCatalogSerializer();
}

class _$RuntimeCatalogSerializer implements PrimitiveSerializer<RuntimeCatalog> {
  @override
  final Iterable<Type> types = const [RuntimeCatalog, _$RuntimeCatalog];

  @override
  final String wireName = r'RuntimeCatalog';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RuntimeCatalog object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'type';
    yield serializers.serialize(
      object.type,
      specifiedType: const FullType(RuntimeType),
    );
    yield r'entries';
    yield serializers.serialize(
      object.entries,
      specifiedType: const FullType(BuiltList, [FullType(RuntimeCatalogEntry)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    RuntimeCatalog object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RuntimeCatalogBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(RuntimeType),
          ) as RuntimeType;
          result.type = valueDes;
          break;
        case r'entries':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(RuntimeCatalogEntry)]),
          ) as BuiltList<RuntimeCatalogEntry>;
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
  RuntimeCatalog deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RuntimeCatalogBuilder();
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

