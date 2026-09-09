// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mod_metadata.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ModMetadata extends ModMetadata {
  @override
  final String name;
  @override
  final String? version;
  @override
  final String? description;
  @override
  final String? modId;
  @override
  final String? authors;
  @override
  final String? url;
  @override
  final ModLoader loader;

  factory _$ModMetadata([void Function(ModMetadataBuilder)? updates]) =>
      (ModMetadataBuilder()..update(updates))._build();

  _$ModMetadata._(
      {required this.name,
      this.version,
      this.description,
      this.modId,
      this.authors,
      this.url,
      required this.loader})
      : super._();
  @override
  ModMetadata rebuild(void Function(ModMetadataBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ModMetadataBuilder toBuilder() => ModMetadataBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ModMetadata &&
        name == other.name &&
        version == other.version &&
        description == other.description &&
        modId == other.modId &&
        authors == other.authors &&
        url == other.url &&
        loader == other.loader;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jc(_$hash, description.hashCode);
    _$hash = $jc(_$hash, modId.hashCode);
    _$hash = $jc(_$hash, authors.hashCode);
    _$hash = $jc(_$hash, url.hashCode);
    _$hash = $jc(_$hash, loader.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ModMetadata')
          ..add('name', name)
          ..add('version', version)
          ..add('description', description)
          ..add('modId', modId)
          ..add('authors', authors)
          ..add('url', url)
          ..add('loader', loader))
        .toString();
  }
}

class ModMetadataBuilder implements Builder<ModMetadata, ModMetadataBuilder> {
  _$ModMetadata? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _version;
  String? get version => _$this._version;
  set version(String? version) => _$this._version = version;

  String? _description;
  String? get description => _$this._description;
  set description(String? description) => _$this._description = description;

  String? _modId;
  String? get modId => _$this._modId;
  set modId(String? modId) => _$this._modId = modId;

  String? _authors;
  String? get authors => _$this._authors;
  set authors(String? authors) => _$this._authors = authors;

  String? _url;
  String? get url => _$this._url;
  set url(String? url) => _$this._url = url;

  ModLoader? _loader;
  ModLoader? get loader => _$this._loader;
  set loader(ModLoader? loader) => _$this._loader = loader;

  ModMetadataBuilder() {
    ModMetadata._defaults(this);
  }

  ModMetadataBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _version = $v.version;
      _description = $v.description;
      _modId = $v.modId;
      _authors = $v.authors;
      _url = $v.url;
      _loader = $v.loader;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ModMetadata other) {
    _$v = other as _$ModMetadata;
  }

  @override
  void update(void Function(ModMetadataBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ModMetadata build() => _build();

  _$ModMetadata _build() {
    final _$result = _$v ??
        _$ModMetadata._(
          name: BuiltValueNullFieldError.checkNotNull(
              name, r'ModMetadata', 'name'),
          version: version,
          description: description,
          modId: modId,
          authors: authors,
          url: url,
          loader: BuiltValueNullFieldError.checkNotNull(
              loader, r'ModMetadata', 'loader'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
