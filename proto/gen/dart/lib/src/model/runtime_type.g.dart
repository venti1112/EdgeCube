// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'runtime_type.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const RuntimeType _$java = const RuntimeType._('java');
const RuntimeType _$php = const RuntimeType._('php');
const RuntimeType _$frpc = const RuntimeType._('frpc');

RuntimeType _$valueOf(String name) {
  switch (name) {
    case 'java':
      return _$java;
    case 'php':
      return _$php;
    case 'frpc':
      return _$frpc;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<RuntimeType> _$values =
    BuiltSet<RuntimeType>(const <RuntimeType>[
  _$java,
  _$php,
  _$frpc,
]);

class _$RuntimeTypeMeta {
  const _$RuntimeTypeMeta();
  RuntimeType get java => _$java;
  RuntimeType get php => _$php;
  RuntimeType get frpc => _$frpc;
  RuntimeType valueOf(String name) => _$valueOf(name);
  BuiltSet<RuntimeType> get values => _$values;
}

abstract class _$RuntimeTypeMixin {
  // ignore: non_constant_identifier_names
  _$RuntimeTypeMeta get RuntimeType => const _$RuntimeTypeMeta();
}

Serializer<RuntimeType> _$runtimeTypeSerializer = _$RuntimeTypeSerializer();

class _$RuntimeTypeSerializer implements PrimitiveSerializer<RuntimeType> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'java': 'java',
    'php': 'php',
    'frpc': 'frpc',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'java': 'java',
    'php': 'php',
    'frpc': 'frpc',
  };

  @override
  final Iterable<Type> types = const <Type>[RuntimeType];
  @override
  final String wireName = 'RuntimeType';

  @override
  Object serialize(Serializers serializers, RuntimeType object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  RuntimeType deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      RuntimeType.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
