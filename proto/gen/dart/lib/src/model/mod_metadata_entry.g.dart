// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mod_metadata_entry.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ModMetadataEntry extends ModMetadataEntry {
  @override
  final String path;
  @override
  final String name;
  @override
  final int sizeBytes;
  @override
  final String? sha1;
  @override
  final String? iconUrl;
  @override
  final ModMetadata? metadata;

  factory _$ModMetadataEntry(
          [void Function(ModMetadataEntryBuilder)? updates]) =>
      (ModMetadataEntryBuilder()..update(updates))._build();

  _$ModMetadataEntry._(
      {required this.path,
      required this.name,
      required this.sizeBytes,
      this.sha1,
      this.iconUrl,
      this.metadata})
      : super._();
  @override
  ModMetadataEntry rebuild(void Function(ModMetadataEntryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ModMetadataEntryBuilder toBuilder() =>
      ModMetadataEntryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ModMetadataEntry &&
        path == other.path &&
        name == other.name &&
        sizeBytes == other.sizeBytes &&
        sha1 == other.sha1 &&
        iconUrl == other.iconUrl &&
        metadata == other.metadata;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, path.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, sizeBytes.hashCode);
    _$hash = $jc(_$hash, sha1.hashCode);
    _$hash = $jc(_$hash, iconUrl.hashCode);
    _$hash = $jc(_$hash, metadata.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ModMetadataEntry')
          ..add('path', path)
          ..add('name', name)
          ..add('sizeBytes', sizeBytes)
          ..add('sha1', sha1)
          ..add('iconUrl', iconUrl)
          ..add('metadata', metadata))
        .toString();
  }
}

class ModMetadataEntryBuilder
    implements Builder<ModMetadataEntry, ModMetadataEntryBuilder> {
  _$ModMetadataEntry? _$v;

  String? _path;
  String? get path => _$this._path;
  set path(String? path) => _$this._path = path;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  int? _sizeBytes;
  int? get sizeBytes => _$this._sizeBytes;
  set sizeBytes(int? sizeBytes) => _$this._sizeBytes = sizeBytes;

  String? _sha1;
  String? get sha1 => _$this._sha1;
  set sha1(String? sha1) => _$this._sha1 = sha1;

  String? _iconUrl;
  String? get iconUrl => _$this._iconUrl;
  set iconUrl(String? iconUrl) => _$this._iconUrl = iconUrl;

  ModMetadataBuilder? _metadata;
  ModMetadataBuilder get metadata => _$this._metadata ??= ModMetadataBuilder();
  set metadata(ModMetadataBuilder? metadata) => _$this._metadata = metadata;

  ModMetadataEntryBuilder() {
    ModMetadataEntry._defaults(this);
  }

  ModMetadataEntryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _path = $v.path;
      _name = $v.name;
      _sizeBytes = $v.sizeBytes;
      _sha1 = $v.sha1;
      _iconUrl = $v.iconUrl;
      _metadata = $v.metadata?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ModMetadataEntry other) {
    _$v = other as _$ModMetadataEntry;
  }

  @override
  void update(void Function(ModMetadataEntryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ModMetadataEntry build() => _build();

  _$ModMetadataEntry _build() {
    _$ModMetadataEntry _$result;
    try {
      _$result = _$v ??
          _$ModMetadataEntry._(
            path: BuiltValueNullFieldError.checkNotNull(
                path, r'ModMetadataEntry', 'path'),
            name: BuiltValueNullFieldError.checkNotNull(
                name, r'ModMetadataEntry', 'name'),
            sizeBytes: BuiltValueNullFieldError.checkNotNull(
                sizeBytes, r'ModMetadataEntry', 'sizeBytes'),
            sha1: sha1,
            iconUrl: iconUrl,
            metadata: _metadata?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'metadata';
        _metadata?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ModMetadataEntry', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
