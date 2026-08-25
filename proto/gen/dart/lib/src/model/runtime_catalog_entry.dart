//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'runtime_catalog_entry.g.dart';

/// RuntimeCatalogEntry
///
/// Properties:
/// * [version] 
/// * [url] - 官方源下载地址
/// * [sha256] 
/// * [sizeBytes] 
@BuiltValue()
abstract class RuntimeCatalogEntry implements Built<RuntimeCatalogEntry, RuntimeCatalogEntryBuilder> {
  @BuiltValueField(wireName: r'version')
  String get version;

  /// 官方源下载地址
  @BuiltValueField(wireName: r'url')
  String? get url;

  @BuiltValueField(wireName: r'sha256')
  String? get sha256;

  @BuiltValueField(wireName: r'sizeBytes')
  int? get sizeBytes;

  RuntimeCatalogEntry._();

  factory RuntimeCatalogEntry([void updates(RuntimeCatalogEntryBuilder b)]) = _$RuntimeCatalogEntry;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RuntimeCatalogEntryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RuntimeCatalogEntry> get serializer => _$RuntimeCatalogEntrySerializer();
}

class _$RuntimeCatalogEntrySerializer implements PrimitiveSerializer<RuntimeCatalogEntry> {
  @override
  final Iterable<Type> types = const [RuntimeCatalogEntry, _$RuntimeCatalogEntry];

  @override
  final String wireName = r'RuntimeCatalogEntry';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RuntimeCatalogEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'version';
    yield serializers.serialize(
      object.version,
      specifiedType: const FullType(String),
    );
    if (object.url != null) {
      yield r'url';
      yield serializers.serialize(
        object.url,
        specifiedType: const FullType(String),
      );
    }
    if (object.sha256 != null) {
      yield r'sha256';
      yield serializers.serialize(
        object.sha256,
        specifiedType: const FullType(String),
      );
    }
    if (object.sizeBytes != null) {
      yield r'sizeBytes';
      yield serializers.serialize(
        object.sizeBytes,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    RuntimeCatalogEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RuntimeCatalogEntryBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'version':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.version = valueDes;
          break;
        case r'url':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.url = valueDes;
          break;
        case r'sha256':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.sha256 = valueDes;
          break;
        case r'sizeBytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.sizeBytes = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RuntimeCatalogEntry deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RuntimeCatalogEntryBuilder();
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

