//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'instance_config_terminal.g.dart';

/// InstanceConfigTerminal
///
/// Properties:
/// * [pty] 
/// * [initialCols] 
/// * [initialRows] 
/// * [haveColor] - 是否把 Minecraft §x 色码转 ANSI
@BuiltValue()
abstract class InstanceConfigTerminal implements Built<InstanceConfigTerminal, InstanceConfigTerminalBuilder> {
  @BuiltValueField(wireName: r'pty')
  bool? get pty;

  @BuiltValueField(wireName: r'initialCols')
  int? get initialCols;

  @BuiltValueField(wireName: r'initialRows')
  int? get initialRows;

  /// 是否把 Minecraft §x 色码转 ANSI
  @BuiltValueField(wireName: r'haveColor')
  bool? get haveColor;

  InstanceConfigTerminal._();

  factory InstanceConfigTerminal([void updates(InstanceConfigTerminalBuilder b)]) = _$InstanceConfigTerminal;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(InstanceConfigTerminalBuilder b) => b
      ..pty = true
      ..initialCols = 164
      ..initialRows = 40
      ..haveColor = true;

  @BuiltValueSerializer(custom: true)
  static Serializer<InstanceConfigTerminal> get serializer => _$InstanceConfigTerminalSerializer();
}

class _$InstanceConfigTerminalSerializer implements PrimitiveSerializer<InstanceConfigTerminal> {
  @override
  final Iterable<Type> types = const [InstanceConfigTerminal, _$InstanceConfigTerminal];

  @override
  final String wireName = r'InstanceConfigTerminal';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    InstanceConfigTerminal object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.pty != null) {
      yield r'pty';
      yield serializers.serialize(
        object.pty,
        specifiedType: const FullType(bool),
      );
    }
    if (object.initialCols != null) {
      yield r'initialCols';
      yield serializers.serialize(
        object.initialCols,
        specifiedType: const FullType(int),
      );
    }
    if (object.initialRows != null) {
      yield r'initialRows';
      yield serializers.serialize(
        object.initialRows,
        specifiedType: const FullType(int),
      );
    }
    if (object.haveColor != null) {
      yield r'haveColor';
      yield serializers.serialize(
        object.haveColor,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    InstanceConfigTerminal object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required InstanceConfigTerminalBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'pty':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.pty = valueDes;
          break;
        case r'initialCols':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.initialCols = valueDes;
          break;
        case r'initialRows':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.initialRows = valueDes;
          break;
        case r'haveColor':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.haveColor = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  InstanceConfigTerminal deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = InstanceConfigTerminalBuilder();
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

