//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'log_line.g.dart';

/// LogLine
///
/// Properties:
/// * [seq] - 单调递增行序号
/// * [ts] 
/// * [text] - 去 ANSI 的纯文本行
@BuiltValue()
abstract class LogLine implements Built<LogLine, LogLineBuilder> {
  /// 单调递增行序号
  @BuiltValueField(wireName: r'seq')
  int get seq;

  @BuiltValueField(wireName: r'ts')
  DateTime? get ts;

  /// 去 ANSI 的纯文本行
  @BuiltValueField(wireName: r'text')
  String get text;

  LogLine._();

  factory LogLine([void updates(LogLineBuilder b)]) = _$LogLine;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LogLineBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<LogLine> get serializer => _$LogLineSerializer();
}

class _$LogLineSerializer implements PrimitiveSerializer<LogLine> {
  @override
  final Iterable<Type> types = const [LogLine, _$LogLine];

  @override
  final String wireName = r'LogLine';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    LogLine object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'seq';
    yield serializers.serialize(
      object.seq,
      specifiedType: const FullType(int),
    );
    if (object.ts != null) {
      yield r'ts';
      yield serializers.serialize(
        object.ts,
        specifiedType: const FullType(DateTime),
      );
    }
    yield r'text';
    yield serializers.serialize(
      object.text,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    LogLine object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required LogLineBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'seq':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.seq = valueDes;
          break;
        case r'ts':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(DateTime),
          ) as DateTime?;
          if (valueDes == null) continue;
          result.ts = valueDes;
          break;
        case r'text':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.text = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  LogLine deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LogLineBuilder();
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

