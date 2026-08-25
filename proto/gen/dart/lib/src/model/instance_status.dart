//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'instance_status.g.dart';

class InstanceStatus extends EnumClass {

  /// 五态状态机(对齐 MCSManager)
  @BuiltValueEnumConst(wireName: r'busy')
  static const InstanceStatus busy = _$busy;
  /// 五态状态机(对齐 MCSManager)
  @BuiltValueEnumConst(wireName: r'stopped')
  static const InstanceStatus stopped = _$stopped;
  /// 五态状态机(对齐 MCSManager)
  @BuiltValueEnumConst(wireName: r'stopping')
  static const InstanceStatus stopping = _$stopping;
  /// 五态状态机(对齐 MCSManager)
  @BuiltValueEnumConst(wireName: r'starting')
  static const InstanceStatus starting = _$starting;
  /// 五态状态机(对齐 MCSManager)
  @BuiltValueEnumConst(wireName: r'running')
  static const InstanceStatus running = _$running;

  static Serializer<InstanceStatus> get serializer => _$instanceStatusSerializer;

  const InstanceStatus._(String name): super(name);

  static BuiltSet<InstanceStatus> get values => _$values;
  static InstanceStatus valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class InstanceStatusMixin = Object with _$InstanceStatusMixin;

