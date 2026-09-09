//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'device_type.g.dart';

class DeviceType extends EnumClass {

  /// 设备类别:desktop 桌面应用(Windows/Linux/macOS),mobile 手机(Android/iOS),web 浏览器
  @BuiltValueEnumConst(wireName: r'desktop')
  static const DeviceType desktop = _$desktop;
  /// 设备类别:desktop 桌面应用(Windows/Linux/macOS),mobile 手机(Android/iOS),web 浏览器
  @BuiltValueEnumConst(wireName: r'mobile')
  static const DeviceType mobile = _$mobile;
  /// 设备类别:desktop 桌面应用(Windows/Linux/macOS),mobile 手机(Android/iOS),web 浏览器
  @BuiltValueEnumConst(wireName: r'web')
  static const DeviceType web = _$web;

  static Serializer<DeviceType> get serializer => _$deviceTypeSerializer;

  const DeviceType._(String name): super(name);

  static BuiltSet<DeviceType> get values => _$values;
  static DeviceType valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class DeviceTypeMixin = Object with _$DeviceTypeMixin;

