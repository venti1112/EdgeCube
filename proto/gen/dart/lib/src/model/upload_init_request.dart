//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'upload_init_request.g.dart';

/// UploadInitRequest
///
/// Properties:
/// * [instanceId] 
/// * [path] - 目标目录(相对实例 cwd)
/// * [fileName] 
/// * [sizeBytes] 
/// * [sha256] - 可选,complete 时校验
/// * [autoExtract] - 完成自动解压(服务端整合包场景)
@BuiltValue()
abstract class UploadInitRequest implements Built<UploadInitRequest, UploadInitRequestBuilder> {
  @BuiltValueField(wireName: r'instanceId')
  String get instanceId;

  /// 目标目录(相对实例 cwd)
  @BuiltValueField(wireName: r'path')
  String get path;

  @BuiltValueField(wireName: r'fileName')
  String get fileName;

  @BuiltValueField(wireName: r'sizeBytes')
  int get sizeBytes;

  /// 可选,complete 时校验
  @BuiltValueField(wireName: r'sha256')
  String? get sha256;

  /// 完成自动解压(服务端整合包场景)
  @BuiltValueField(wireName: r'autoExtract')
  bool? get autoExtract;

  UploadInitRequest._();

  factory UploadInitRequest([void updates(UploadInitRequestBuilder b)]) = _$UploadInitRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UploadInitRequestBuilder b) => b
      ..autoExtract = false;

  @BuiltValueSerializer(custom: true)
  static Serializer<UploadInitRequest> get serializer => _$UploadInitRequestSerializer();
}

class _$UploadInitRequestSerializer implements PrimitiveSerializer<UploadInitRequest> {
  @override
  final Iterable<Type> types = const [UploadInitRequest, _$UploadInitRequest];

  @override
  final String wireName = r'UploadInitRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UploadInitRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'instanceId';
    yield serializers.serialize(
      object.instanceId,
      specifiedType: const FullType(String),
    );
    yield r'path';
    yield serializers.serialize(
      object.path,
      specifiedType: const FullType(String),
    );
    yield r'fileName';
    yield serializers.serialize(
      object.fileName,
      specifiedType: const FullType(String),
    );
    yield r'sizeBytes';
    yield serializers.serialize(
      object.sizeBytes,
      specifiedType: const FullType(int),
    );
    if (object.sha256 != null) {
      yield r'sha256';
      yield serializers.serialize(
        object.sha256,
        specifiedType: const FullType(String),
      );
    }
    if (object.autoExtract != null) {
      yield r'autoExtract';
      yield serializers.serialize(
        object.autoExtract,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    UploadInitRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required UploadInitRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'instanceId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.instanceId = valueDes;
          break;
        case r'path':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.path = valueDes;
          break;
        case r'fileName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.fileName = valueDes;
          break;
        case r'sizeBytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.sizeBytes = valueDes;
          break;
        case r'sha256':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.sha256 = valueDes;
          break;
        case r'autoExtract':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.autoExtract = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UploadInitRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UploadInitRequestBuilder();
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

