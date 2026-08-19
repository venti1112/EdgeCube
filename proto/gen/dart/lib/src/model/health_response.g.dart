// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'health_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const HealthResponseStatusEnum _$healthResponseStatusEnum_ok =
    const HealthResponseStatusEnum._('ok');
const HealthResponseStatusEnum _$healthResponseStatusEnum_degraded =
    const HealthResponseStatusEnum._('degraded');

HealthResponseStatusEnum _$healthResponseStatusEnumValueOf(String name) {
  switch (name) {
    case 'ok':
      return _$healthResponseStatusEnum_ok;
    case 'degraded':
      return _$healthResponseStatusEnum_degraded;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<HealthResponseStatusEnum> _$healthResponseStatusEnumValues =
    BuiltSet<HealthResponseStatusEnum>(const <HealthResponseStatusEnum>[
  _$healthResponseStatusEnum_ok,
  _$healthResponseStatusEnum_degraded,
]);

const HealthResponseDaemonEnum _$healthResponseDaemonEnum_rust =
    const HealthResponseDaemonEnum._('rust');
const HealthResponseDaemonEnum _$healthResponseDaemonEnum_kotlin =
    const HealthResponseDaemonEnum._('kotlin');

HealthResponseDaemonEnum _$healthResponseDaemonEnumValueOf(String name) {
  switch (name) {
    case 'rust':
      return _$healthResponseDaemonEnum_rust;
    case 'kotlin':
      return _$healthResponseDaemonEnum_kotlin;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<HealthResponseDaemonEnum> _$healthResponseDaemonEnumValues =
    BuiltSet<HealthResponseDaemonEnum>(const <HealthResponseDaemonEnum>[
  _$healthResponseDaemonEnum_rust,
  _$healthResponseDaemonEnum_kotlin,
]);

Serializer<HealthResponseStatusEnum> _$healthResponseStatusEnumSerializer =
    _$HealthResponseStatusEnumSerializer();
Serializer<HealthResponseDaemonEnum> _$healthResponseDaemonEnumSerializer =
    _$HealthResponseDaemonEnumSerializer();

class _$HealthResponseStatusEnumSerializer
    implements PrimitiveSerializer<HealthResponseStatusEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'ok': 'ok',
    'degraded': 'degraded',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'ok': 'ok',
    'degraded': 'degraded',
  };

  @override
  final Iterable<Type> types = const <Type>[HealthResponseStatusEnum];
  @override
  final String wireName = 'HealthResponseStatusEnum';

  @override
  Object serialize(Serializers serializers, HealthResponseStatusEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  HealthResponseStatusEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      HealthResponseStatusEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$HealthResponseDaemonEnumSerializer
    implements PrimitiveSerializer<HealthResponseDaemonEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'rust': 'rust',
    'kotlin': 'kotlin',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'rust': 'rust',
    'kotlin': 'kotlin',
  };

  @override
  final Iterable<Type> types = const <Type>[HealthResponseDaemonEnum];
  @override
  final String wireName = 'HealthResponseDaemonEnum';

  @override
  Object serialize(Serializers serializers, HealthResponseDaemonEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  HealthResponseDaemonEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      HealthResponseDaemonEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$HealthResponse extends HealthResponse {
  @override
  final HealthResponseStatusEnum status;
  @override
  final String version;
  @override
  final HealthResponseDaemonEnum daemon;
  @override
  final String platform;
  @override
  final int uptimeSeconds;
  @override
  final HealthResponseInstances? instances;

  factory _$HealthResponse([void Function(HealthResponseBuilder)? updates]) =>
      (HealthResponseBuilder()..update(updates))._build();

  _$HealthResponse._(
      {required this.status,
      required this.version,
      required this.daemon,
      required this.platform,
      required this.uptimeSeconds,
      this.instances})
      : super._();
  @override
  HealthResponse rebuild(void Function(HealthResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  HealthResponseBuilder toBuilder() => HealthResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is HealthResponse &&
        status == other.status &&
        version == other.version &&
        daemon == other.daemon &&
        platform == other.platform &&
        uptimeSeconds == other.uptimeSeconds &&
        instances == other.instances;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jc(_$hash, daemon.hashCode);
    _$hash = $jc(_$hash, platform.hashCode);
    _$hash = $jc(_$hash, uptimeSeconds.hashCode);
    _$hash = $jc(_$hash, instances.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'HealthResponse')
          ..add('status', status)
          ..add('version', version)
          ..add('daemon', daemon)
          ..add('platform', platform)
          ..add('uptimeSeconds', uptimeSeconds)
          ..add('instances', instances))
        .toString();
  }
}

class HealthResponseBuilder
    implements Builder<HealthResponse, HealthResponseBuilder> {
  _$HealthResponse? _$v;

  HealthResponseStatusEnum? _status;
  HealthResponseStatusEnum? get status => _$this._status;
  set status(HealthResponseStatusEnum? status) => _$this._status = status;

  String? _version;
  String? get version => _$this._version;
  set version(String? version) => _$this._version = version;

  HealthResponseDaemonEnum? _daemon;
  HealthResponseDaemonEnum? get daemon => _$this._daemon;
  set daemon(HealthResponseDaemonEnum? daemon) => _$this._daemon = daemon;

  String? _platform;
  String? get platform => _$this._platform;
  set platform(String? platform) => _$this._platform = platform;

  int? _uptimeSeconds;
  int? get uptimeSeconds => _$this._uptimeSeconds;
  set uptimeSeconds(int? uptimeSeconds) =>
      _$this._uptimeSeconds = uptimeSeconds;

  HealthResponseInstancesBuilder? _instances;
  HealthResponseInstancesBuilder get instances =>
      _$this._instances ??= HealthResponseInstancesBuilder();
  set instances(HealthResponseInstancesBuilder? instances) =>
      _$this._instances = instances;

  HealthResponseBuilder() {
    HealthResponse._defaults(this);
  }

  HealthResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _status = $v.status;
      _version = $v.version;
      _daemon = $v.daemon;
      _platform = $v.platform;
      _uptimeSeconds = $v.uptimeSeconds;
      _instances = $v.instances?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(HealthResponse other) {
    _$v = other as _$HealthResponse;
  }

  @override
  void update(void Function(HealthResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  HealthResponse build() => _build();

  _$HealthResponse _build() {
    _$HealthResponse _$result;
    try {
      _$result = _$v ??
          _$HealthResponse._(
            status: BuiltValueNullFieldError.checkNotNull(
                status, r'HealthResponse', 'status'),
            version: BuiltValueNullFieldError.checkNotNull(
                version, r'HealthResponse', 'version'),
            daemon: BuiltValueNullFieldError.checkNotNull(
                daemon, r'HealthResponse', 'daemon'),
            platform: BuiltValueNullFieldError.checkNotNull(
                platform, r'HealthResponse', 'platform'),
            uptimeSeconds: BuiltValueNullFieldError.checkNotNull(
                uptimeSeconds, r'HealthResponse', 'uptimeSeconds'),
            instances: _instances?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'instances';
        _instances?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'HealthResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
