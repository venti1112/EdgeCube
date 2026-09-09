// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'proxy_type.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const ProxyType _$tcp = const ProxyType._('tcp');
const ProxyType _$udp = const ProxyType._('udp');
const ProxyType _$http = const ProxyType._('http');
const ProxyType _$https = const ProxyType._('https');

ProxyType _$valueOf(String name) {
  switch (name) {
    case 'tcp':
      return _$tcp;
    case 'udp':
      return _$udp;
    case 'http':
      return _$http;
    case 'https':
      return _$https;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<ProxyType> _$values = BuiltSet<ProxyType>(const <ProxyType>[
  _$tcp,
  _$udp,
  _$http,
  _$https,
]);

class _$ProxyTypeMeta {
  const _$ProxyTypeMeta();
  ProxyType get tcp => _$tcp;
  ProxyType get udp => _$udp;
  ProxyType get http => _$http;
  ProxyType get https => _$https;
  ProxyType valueOf(String name) => _$valueOf(name);
  BuiltSet<ProxyType> get values => _$values;
}

abstract class _$ProxyTypeMixin {
  // ignore: non_constant_identifier_names
  _$ProxyTypeMeta get ProxyType => const _$ProxyTypeMeta();
}

Serializer<ProxyType> _$proxyTypeSerializer = _$ProxyTypeSerializer();

class _$ProxyTypeSerializer implements PrimitiveSerializer<ProxyType> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'tcp': 'tcp',
    'udp': 'udp',
    'http': 'http',
    'https': 'https',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'tcp': 'tcp',
    'udp': 'udp',
    'http': 'http',
    'https': 'https',
  };

  @override
  final Iterable<Type> types = const <Type>[ProxyType];
  @override
  final String wireName = 'ProxyType';

  @override
  Object serialize(Serializers serializers, ProxyType object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  ProxyType deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      ProxyType.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
