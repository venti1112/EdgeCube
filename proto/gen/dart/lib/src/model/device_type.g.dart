// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_type.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const DeviceType _$desktop = const DeviceType._('desktop');
const DeviceType _$mobile = const DeviceType._('mobile');
const DeviceType _$web = const DeviceType._('web');

DeviceType _$valueOf(String name) {
  switch (name) {
    case 'desktop':
      return _$desktop;
    case 'mobile':
      return _$mobile;
    case 'web':
      return _$web;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<DeviceType> _$values = BuiltSet<DeviceType>(const <DeviceType>[
  _$desktop,
  _$mobile,
  _$web,
]);

class _$DeviceTypeMeta {
  const _$DeviceTypeMeta();
  DeviceType get desktop => _$desktop;
  DeviceType get mobile => _$mobile;
  DeviceType get web => _$web;
  DeviceType valueOf(String name) => _$valueOf(name);
  BuiltSet<DeviceType> get values => _$values;
}

abstract class _$DeviceTypeMixin {
  // ignore: non_constant_identifier_names
  _$DeviceTypeMeta get DeviceType => const _$DeviceTypeMeta();
}

Serializer<DeviceType> _$deviceTypeSerializer = _$DeviceTypeSerializer();

class _$DeviceTypeSerializer implements PrimitiveSerializer<DeviceType> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'desktop': 'desktop',
    'mobile': 'mobile',
    'web': 'web',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'desktop': 'desktop',
    'mobile': 'mobile',
    'web': 'web',
  };

  @override
  final Iterable<Type> types = const <Type>[DeviceType];
  @override
  final String wireName = 'DeviceType';

  @override
  Object serialize(Serializers serializers, DeviceType object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  DeviceType deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      DeviceType.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
