// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'instance_status.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const InstanceStatus _$busy = const InstanceStatus._('busy');
const InstanceStatus _$stopped = const InstanceStatus._('stopped');
const InstanceStatus _$stopping = const InstanceStatus._('stopping');
const InstanceStatus _$starting = const InstanceStatus._('starting');
const InstanceStatus _$running = const InstanceStatus._('running');

InstanceStatus _$valueOf(String name) {
  switch (name) {
    case 'busy':
      return _$busy;
    case 'stopped':
      return _$stopped;
    case 'stopping':
      return _$stopping;
    case 'starting':
      return _$starting;
    case 'running':
      return _$running;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<InstanceStatus> _$values =
    BuiltSet<InstanceStatus>(const <InstanceStatus>[
  _$busy,
  _$stopped,
  _$stopping,
  _$starting,
  _$running,
]);

class _$InstanceStatusMeta {
  const _$InstanceStatusMeta();
  InstanceStatus get busy => _$busy;
  InstanceStatus get stopped => _$stopped;
  InstanceStatus get stopping => _$stopping;
  InstanceStatus get starting => _$starting;
  InstanceStatus get running => _$running;
  InstanceStatus valueOf(String name) => _$valueOf(name);
  BuiltSet<InstanceStatus> get values => _$values;
}

abstract class _$InstanceStatusMixin {
  // ignore: non_constant_identifier_names
  _$InstanceStatusMeta get InstanceStatus => const _$InstanceStatusMeta();
}

Serializer<InstanceStatus> _$instanceStatusSerializer =
    _$InstanceStatusSerializer();

class _$InstanceStatusSerializer
    implements PrimitiveSerializer<InstanceStatus> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'busy': 'busy',
    'stopped': 'stopped',
    'stopping': 'stopping',
    'starting': 'starting',
    'running': 'running',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'busy': 'busy',
    'stopped': 'stopped',
    'stopping': 'stopping',
    'starting': 'starting',
    'running': 'running',
  };

  @override
  final Iterable<Type> types = const <Type>[InstanceStatus];
  @override
  final String wireName = 'InstanceStatus';

  @override
  Object serialize(Serializers serializers, InstanceStatus object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  InstanceStatus deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      InstanceStatus.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
