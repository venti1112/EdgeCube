// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'server_core_update_check.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const ServerCoreUpdateCheckSource_Enum _$serverCoreUpdateCheckSourceEnum_paper =
    const ServerCoreUpdateCheckSource_Enum._('paper');
const ServerCoreUpdateCheckSource_Enum
    _$serverCoreUpdateCheckSourceEnum_unknown =
    const ServerCoreUpdateCheckSource_Enum._('unknown');

ServerCoreUpdateCheckSource_Enum _$serverCoreUpdateCheckSourceEnumValueOf(
    String name) {
  switch (name) {
    case 'paper':
      return _$serverCoreUpdateCheckSourceEnum_paper;
    case 'unknown':
      return _$serverCoreUpdateCheckSourceEnum_unknown;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<ServerCoreUpdateCheckSource_Enum>
    _$serverCoreUpdateCheckSourceEnumValues = BuiltSet<
        ServerCoreUpdateCheckSource_Enum>(const <ServerCoreUpdateCheckSource_Enum>[
  _$serverCoreUpdateCheckSourceEnum_paper,
  _$serverCoreUpdateCheckSourceEnum_unknown,
]);

Serializer<ServerCoreUpdateCheckSource_Enum>
    _$serverCoreUpdateCheckSourceEnumSerializer =
    _$ServerCoreUpdateCheckSource_EnumSerializer();

class _$ServerCoreUpdateCheckSource_EnumSerializer
    implements PrimitiveSerializer<ServerCoreUpdateCheckSource_Enum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'paper': 'paper',
    'unknown': 'unknown',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'paper': 'paper',
    'unknown': 'unknown',
  };

  @override
  final Iterable<Type> types = const <Type>[ServerCoreUpdateCheckSource_Enum];
  @override
  final String wireName = 'ServerCoreUpdateCheckSource_Enum';

  @override
  Object serialize(
          Serializers serializers, ServerCoreUpdateCheckSource_Enum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  ServerCoreUpdateCheckSource_Enum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      ServerCoreUpdateCheckSource_Enum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$ServerCoreUpdateCheck extends ServerCoreUpdateCheck {
  @override
  final bool supported;
  @override
  final ServerCoreUpdateCheckSource_Enum? source_;
  @override
  final String? currentVersion;
  @override
  final String? currentBuild;
  @override
  final String? latestVersion;
  @override
  final String? latestBuild;
  @override
  final String? downloadUrl;
  @override
  final String? sha256;
  @override
  final bool? updateAvailable;

  factory _$ServerCoreUpdateCheck(
          [void Function(ServerCoreUpdateCheckBuilder)? updates]) =>
      (ServerCoreUpdateCheckBuilder()..update(updates))._build();

  _$ServerCoreUpdateCheck._(
      {required this.supported,
      this.source_,
      this.currentVersion,
      this.currentBuild,
      this.latestVersion,
      this.latestBuild,
      this.downloadUrl,
      this.sha256,
      this.updateAvailable})
      : super._();
  @override
  ServerCoreUpdateCheck rebuild(
          void Function(ServerCoreUpdateCheckBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ServerCoreUpdateCheckBuilder toBuilder() =>
      ServerCoreUpdateCheckBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ServerCoreUpdateCheck &&
        supported == other.supported &&
        source_ == other.source_ &&
        currentVersion == other.currentVersion &&
        currentBuild == other.currentBuild &&
        latestVersion == other.latestVersion &&
        latestBuild == other.latestBuild &&
        downloadUrl == other.downloadUrl &&
        sha256 == other.sha256 &&
        updateAvailable == other.updateAvailable;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, supported.hashCode);
    _$hash = $jc(_$hash, source_.hashCode);
    _$hash = $jc(_$hash, currentVersion.hashCode);
    _$hash = $jc(_$hash, currentBuild.hashCode);
    _$hash = $jc(_$hash, latestVersion.hashCode);
    _$hash = $jc(_$hash, latestBuild.hashCode);
    _$hash = $jc(_$hash, downloadUrl.hashCode);
    _$hash = $jc(_$hash, sha256.hashCode);
    _$hash = $jc(_$hash, updateAvailable.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ServerCoreUpdateCheck')
          ..add('supported', supported)
          ..add('source_', source_)
          ..add('currentVersion', currentVersion)
          ..add('currentBuild', currentBuild)
          ..add('latestVersion', latestVersion)
          ..add('latestBuild', latestBuild)
          ..add('downloadUrl', downloadUrl)
          ..add('sha256', sha256)
          ..add('updateAvailable', updateAvailable))
        .toString();
  }
}

class ServerCoreUpdateCheckBuilder
    implements Builder<ServerCoreUpdateCheck, ServerCoreUpdateCheckBuilder> {
  _$ServerCoreUpdateCheck? _$v;

  bool? _supported;
  bool? get supported => _$this._supported;
  set supported(bool? supported) => _$this._supported = supported;

  ServerCoreUpdateCheckSource_Enum? _source_;
  ServerCoreUpdateCheckSource_Enum? get source_ => _$this._source_;
  set source_(ServerCoreUpdateCheckSource_Enum? source_) =>
      _$this._source_ = source_;

  String? _currentVersion;
  String? get currentVersion => _$this._currentVersion;
  set currentVersion(String? currentVersion) =>
      _$this._currentVersion = currentVersion;

  String? _currentBuild;
  String? get currentBuild => _$this._currentBuild;
  set currentBuild(String? currentBuild) => _$this._currentBuild = currentBuild;

  String? _latestVersion;
  String? get latestVersion => _$this._latestVersion;
  set latestVersion(String? latestVersion) =>
      _$this._latestVersion = latestVersion;

  String? _latestBuild;
  String? get latestBuild => _$this._latestBuild;
  set latestBuild(String? latestBuild) => _$this._latestBuild = latestBuild;

  String? _downloadUrl;
  String? get downloadUrl => _$this._downloadUrl;
  set downloadUrl(String? downloadUrl) => _$this._downloadUrl = downloadUrl;

  String? _sha256;
  String? get sha256 => _$this._sha256;
  set sha256(String? sha256) => _$this._sha256 = sha256;

  bool? _updateAvailable;
  bool? get updateAvailable => _$this._updateAvailable;
  set updateAvailable(bool? updateAvailable) =>
      _$this._updateAvailable = updateAvailable;

  ServerCoreUpdateCheckBuilder() {
    ServerCoreUpdateCheck._defaults(this);
  }

  ServerCoreUpdateCheckBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _supported = $v.supported;
      _source_ = $v.source_;
      _currentVersion = $v.currentVersion;
      _currentBuild = $v.currentBuild;
      _latestVersion = $v.latestVersion;
      _latestBuild = $v.latestBuild;
      _downloadUrl = $v.downloadUrl;
      _sha256 = $v.sha256;
      _updateAvailable = $v.updateAvailable;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ServerCoreUpdateCheck other) {
    _$v = other as _$ServerCoreUpdateCheck;
  }

  @override
  void update(void Function(ServerCoreUpdateCheckBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ServerCoreUpdateCheck build() => _build();

  _$ServerCoreUpdateCheck _build() {
    final _$result = _$v ??
        _$ServerCoreUpdateCheck._(
          supported: BuiltValueNullFieldError.checkNotNull(
              supported, r'ServerCoreUpdateCheck', 'supported'),
          source_: source_,
          currentVersion: currentVersion,
          currentBuild: currentBuild,
          latestVersion: latestVersion,
          latestBuild: latestBuild,
          downloadUrl: downloadUrl,
          sha256: sha256,
          updateAvailable: updateAvailable,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
