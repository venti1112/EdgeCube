//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:edgecube_api_client/src/model/log_line.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'log_response.g.dart';

/// LogResponse
///
/// Properties:
/// * [lines] 
/// * [nextSeq] - 下一条起始序号
@BuiltValue()
abstract class LogResponse implements Built<LogResponse, LogResponseBuilder> {
  @BuiltValueField(wireName: r'lines')
  BuiltList<LogLine> get lines;

  /// 下一条起始序号
  @BuiltValueField(wireName: r'nextSeq')
  int get nextSeq;

  LogResponse._();

  factory LogResponse([void updates(LogResponseBuilder b)]) = _$LogResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LogResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<LogResponse> get serializer => _$LogResponseSerializer();
}

class _$LogResponseSerializer implements PrimitiveSerializer<LogResponse> {
  @override
  final Iterable<Type> types = const [LogResponse, _$LogResponse];

  @override
  final String wireName = r'LogResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    LogResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'lines';
    yield serializers.serialize(
      object.lines,
      specifiedType: const FullType(BuiltList, [FullType(LogLine)]),
    );
    yield r'nextSeq';
    yield serializers.serialize(
      object.nextSeq,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    LogResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required LogResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'lines':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(LogLine)]),
          ) as BuiltList<LogLine>;
          result.lines.replace(valueDes);
          break;
        case r'nextSeq':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.nextSeq = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  LogResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LogResponseBuilder();
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

