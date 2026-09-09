//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'proxy_type.g.dart';

class ProxyType extends EnumClass {

  /// 代理协议类型
  @BuiltValueEnumConst(wireName: r'tcp')
  static const ProxyType tcp = _$tcp;
  /// 代理协议类型
  @BuiltValueEnumConst(wireName: r'udp')
  static const ProxyType udp = _$udp;
  /// 代理协议类型
  @BuiltValueEnumConst(wireName: r'http')
  static const ProxyType http = _$http;
  /// 代理协议类型
  @BuiltValueEnumConst(wireName: r'https')
  static const ProxyType https = _$https;

  static Serializer<ProxyType> get serializer => _$proxyTypeSerializer;

  const ProxyType._(String name): super(name);

  static BuiltSet<ProxyType> get values => _$values;
  static ProxyType valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class ProxyTypeMixin = Object with _$ProxyTypeMixin;

