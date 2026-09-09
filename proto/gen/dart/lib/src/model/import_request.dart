//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'import_request.g.dart';

/// ImportRequest
///
/// Properties:
/// * [sourceInstanceId] - 归档所在实例 id(先经 /fs/upload-* 上传到该实例 cwd)
/// * [archivePath] - 导出归档在其 cwd 内的相对路径(先经 /fs/upload-* 上传)
@BuiltValue()
abstract class ImportRequest implements Built<ImportRequest, ImportRequestBuilder> {
  /// 归档所在实例 id(先经 /fs/upload-* 上传到该实例 cwd)
  @BuiltValueField(wireName: r'sourceInstanceId')
  String get sourceInstanceId;

  /// 导出归档在其 cwd 内的相对路径(先经 /fs/upload-* 上传)
  @BuiltValueField(wireName: r'archivePath')
  String get archivePath;

  ImportRequest._();

  factory ImportRequest([void updates(ImportRequestBuilder b)]) = _$ImportRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ImportRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ImportRequest> get serializer => _$ImportRequestSerializer();
}

class _$ImportRequestSerializer implements PrimitiveSerializer<ImportRequest> {
  @override
  final Iterable<Type> types = const [ImportRequest, _$ImportRequest];

  @override
  final String wireName = r'ImportRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ImportRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'sourceInstanceId';
    yield serializers.serialize(
      object.sourceInstanceId,
      specifiedType: const FullType(String),
    );
    yield r'archivePath';
    yield serializers.serialize(
      object.archivePath,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ImportRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ImportRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'sourceInstanceId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.sourceInstanceId = valueDes;
          break;
        case r'archivePath':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.archivePath = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ImportRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ImportRequestBuilder();
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

