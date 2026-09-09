//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'frp_status.g.dart';

/// FrpStatus
///
/// Properties:
/// * [running] 
/// * [tunnelId] - 运行中的隧道(未运行时缺省)
/// * [startedAt] - 本次启动时间(未运行时缺省)
/// * [exitCode] - 未运行时的上次退出码(无记录时缺省)
@BuiltValue()
abstract class FrpStatus implements Built<FrpStatus, FrpStatusBuilder> {
  @BuiltValueField(wireName: r'running')
  bool get running;

  /// 运行中的隧道(未运行时缺省)
  @BuiltValueField(wireName: r'tunnelId')
  String? get tunnelId;

  /// 本次启动时间(未运行时缺省)
  @BuiltValueField(wireName: r'startedAt')
  DateTime? get startedAt;

  /// 未运行时的上次退出码(无记录时缺省)
  @BuiltValueField(wireName: r'exitCode')
  int? get exitCode;

  FrpStatus._();

  factory FrpStatus([void updates(FrpStatusBuilder b)]) = _$FrpStatus;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(FrpStatusBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<FrpStatus> get serializer => _$FrpStatusSerializer();
}

class _$FrpStatusSerializer implements PrimitiveSerializer<FrpStatus> {
  @override
  final Iterable<Type> types = const [FrpStatus, _$FrpStatus];

  @override
  final String wireName = r'FrpStatus';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    FrpStatus object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'running';
    yield serializers.serialize(
      object.running,
      specifiedType: const FullType(bool),
    );
    if (object.tunnelId != null) {
      yield r'tunnelId';
      yield serializers.serialize(
        object.tunnelId,
        specifiedType: const FullType(String),
      );
    }
    if (object.startedAt != null) {
      yield r'startedAt';
      yield serializers.serialize(
        object.startedAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.exitCode != null) {
      yield r'exitCode';
      yield serializers.serialize(
        object.exitCode,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    FrpStatus object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required FrpStatusBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'running':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.running = valueDes;
          break;
        case r'tunnelId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.tunnelId = valueDes;
          break;
        case r'startedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(DateTime),
          ) as DateTime?;
          if (valueDes == null) continue;
          result.startedAt = valueDes;
          break;
        case r'exitCode':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.exitCode = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  FrpStatus deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = FrpStatusBuilder();
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

