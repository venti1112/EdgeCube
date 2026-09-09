// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'poggit_plugin.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PoggitPlugin extends PoggitPlugin {
  @override
  final String name;
  @override
  final String? version;
  @override
  final BuiltList<String>? api;
  @override
  final BuiltList<String>? tag;
  @override
  final int? lastUpdate;
  @override
  final int? dl;
  @override
  final String? icon;
  @override
  final String? artifactUrl;

  factory _$PoggitPlugin([void Function(PoggitPluginBuilder)? updates]) =>
      (PoggitPluginBuilder()..update(updates))._build();

  _$PoggitPlugin._(
      {required this.name,
      this.version,
      this.api,
      this.tag,
      this.lastUpdate,
      this.dl,
      this.icon,
      this.artifactUrl})
      : super._();
  @override
  PoggitPlugin rebuild(void Function(PoggitPluginBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PoggitPluginBuilder toBuilder() => PoggitPluginBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PoggitPlugin &&
        name == other.name &&
        version == other.version &&
        api == other.api &&
        tag == other.tag &&
        lastUpdate == other.lastUpdate &&
        dl == other.dl &&
        icon == other.icon &&
        artifactUrl == other.artifactUrl;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jc(_$hash, api.hashCode);
    _$hash = $jc(_$hash, tag.hashCode);
    _$hash = $jc(_$hash, lastUpdate.hashCode);
    _$hash = $jc(_$hash, dl.hashCode);
    _$hash = $jc(_$hash, icon.hashCode);
    _$hash = $jc(_$hash, artifactUrl.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PoggitPlugin')
          ..add('name', name)
          ..add('version', version)
          ..add('api', api)
          ..add('tag', tag)
          ..add('lastUpdate', lastUpdate)
          ..add('dl', dl)
          ..add('icon', icon)
          ..add('artifactUrl', artifactUrl))
        .toString();
  }
}

class PoggitPluginBuilder
    implements Builder<PoggitPlugin, PoggitPluginBuilder> {
  _$PoggitPlugin? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _version;
  String? get version => _$this._version;
  set version(String? version) => _$this._version = version;

  ListBuilder<String>? _api;
  ListBuilder<String> get api => _$this._api ??= ListBuilder<String>();
  set api(ListBuilder<String>? api) => _$this._api = api;

  ListBuilder<String>? _tag;
  ListBuilder<String> get tag => _$this._tag ??= ListBuilder<String>();
  set tag(ListBuilder<String>? tag) => _$this._tag = tag;

  int? _lastUpdate;
  int? get lastUpdate => _$this._lastUpdate;
  set lastUpdate(int? lastUpdate) => _$this._lastUpdate = lastUpdate;

  int? _dl;
  int? get dl => _$this._dl;
  set dl(int? dl) => _$this._dl = dl;

  String? _icon;
  String? get icon => _$this._icon;
  set icon(String? icon) => _$this._icon = icon;

  String? _artifactUrl;
  String? get artifactUrl => _$this._artifactUrl;
  set artifactUrl(String? artifactUrl) => _$this._artifactUrl = artifactUrl;

  PoggitPluginBuilder() {
    PoggitPlugin._defaults(this);
  }

  PoggitPluginBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _version = $v.version;
      _api = $v.api?.toBuilder();
      _tag = $v.tag?.toBuilder();
      _lastUpdate = $v.lastUpdate;
      _dl = $v.dl;
      _icon = $v.icon;
      _artifactUrl = $v.artifactUrl;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PoggitPlugin other) {
    _$v = other as _$PoggitPlugin;
  }

  @override
  void update(void Function(PoggitPluginBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PoggitPlugin build() => _build();

  _$PoggitPlugin _build() {
    _$PoggitPlugin _$result;
    try {
      _$result = _$v ??
          _$PoggitPlugin._(
            name: BuiltValueNullFieldError.checkNotNull(
                name, r'PoggitPlugin', 'name'),
            version: version,
            api: _api?.build(),
            tag: _tag?.build(),
            lastUpdate: lastUpdate,
            dl: dl,
            icon: icon,
            artifactUrl: artifactUrl,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'api';
        _api?.build();
        _$failedField = 'tag';
        _tag?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'PoggitPlugin', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
