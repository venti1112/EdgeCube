//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'export_request.g.dart';

/// ExportRequest
///
/// Properties:
/// * [format] 
/// * [includeLogs] 
@BuiltValue()
abstract class ExportRequest implements Built<ExportRequest, ExportRequestBuilder> {
  @BuiltValueField(wireName: r'format')
  ExportRequestFormatEnum? get format;
  // enum formatEnum {  zip,  tar.gz,  };

  @BuiltValueField(wireName: r'includeLogs')
  bool? get includeLogs;

  ExportRequest._();

  factory ExportRequest([void updates(ExportRequestBuilder b)]) = _$ExportRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ExportRequestBuilder b) => b
      ..format = ExportRequestFormatEnum.valueOf('zip')
      ..includeLogs = false;

  @BuiltValueSerializer(custom: true)
  static Serializer<ExportRequest> get serializer => _$ExportRequestSerializer();
}

class _$ExportRequestSerializer implements PrimitiveSerializer<ExportRequest> {
  @override
  final Iterable<Type> types = const [ExportRequest, _$ExportRequest];

  @override
  final String wireName = r'ExportRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ExportRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.format != null) {
      yield r'format';
      yield serializers.serialize(
        object.format,
        specifiedType: const FullType(ExportRequestFormatEnum),
      );
    }
    if (object.includeLogs != null) {
      yield r'includeLogs';
      yield serializers.serialize(
        object.includeLogs,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ExportRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ExportRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'format':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(ExportRequestFormatEnum),
          ) as ExportRequestFormatEnum?;
          if (valueDes == null) continue;
          result.format = valueDes;
          break;
        case r'includeLogs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.includeLogs = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ExportRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ExportRequestBuilder();
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

class ExportRequestFormatEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'zip')
  static const ExportRequestFormatEnum zip = _$exportRequestFormatEnum_zip;
  @BuiltValueEnumConst(wireName: r'tar.gz')
  static const ExportRequestFormatEnum tarPeriodGz = _$exportRequestFormatEnum_tarPeriodGz;

  static Serializer<ExportRequestFormatEnum> get serializer => _$exportRequestFormatEnumSerializer;

  const ExportRequestFormatEnum._(String name): super(name);

  static BuiltSet<ExportRequestFormatEnum> get values => _$exportRequestFormatEnumValues;
  static ExportRequestFormatEnum valueOf(String name) => _$exportRequestFormatEnumValueOf(name);
}

