// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'runtime_catalog_entry.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RuntimeCatalogEntry extends RuntimeCatalogEntry {
  @override
  final String version;
  @override
  final String? url;
  @override
  final String? sha256;
  @override
  final int? sizeBytes;

  factory _$RuntimeCatalogEntry(
          [void Function(RuntimeCatalogEntryBuilder)? updates]) =>
      (RuntimeCatalogEntryBuilder()..update(updates))._build();

  _$RuntimeCatalogEntry._(
      {required this.version, this.url, this.sha256, this.sizeBytes})
      : super._();
  @override
  RuntimeCatalogEntry rebuild(
          void Function(RuntimeCatalogEntryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RuntimeCatalogEntryBuilder toBuilder() =>
      RuntimeCatalogEntryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RuntimeCatalogEntry &&
        version == other.version &&
        url == other.url &&
        sha256 == other.sha256 &&
        sizeBytes == other.sizeBytes;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jc(_$hash, url.hashCode);
    _$hash = $jc(_$hash, sha256.hashCode);
    _$hash = $jc(_$hash, sizeBytes.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RuntimeCatalogEntry')
          ..add('version', version)
          ..add('url', url)
          ..add('sha256', sha256)
          ..add('sizeBytes', sizeBytes))
        .toString();
  }
}

class RuntimeCatalogEntryBuilder
    implements Builder<RuntimeCatalogEntry, RuntimeCatalogEntryBuilder> {
  _$RuntimeCatalogEntry? _$v;

  String? _version;
  String? get version => _$this._version;
  set version(String? version) => _$this._version = version;

  String? _url;
  String? get url => _$this._url;
  set url(String? url) => _$this._url = url;

  String? _sha256;
  String? get sha256 => _$this._sha256;
  set sha256(String? sha256) => _$this._sha256 = sha256;

  int? _sizeBytes;
  int? get sizeBytes => _$this._sizeBytes;
  set sizeBytes(int? sizeBytes) => _$this._sizeBytes = sizeBytes;

  RuntimeCatalogEntryBuilder() {
    RuntimeCatalogEntry._defaults(this);
  }

  RuntimeCatalogEntryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _version = $v.version;
      _url = $v.url;
      _sha256 = $v.sha256;
      _sizeBytes = $v.sizeBytes;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RuntimeCatalogEntry other) {
    _$v = other as _$RuntimeCatalogEntry;
  }

  @override
  void update(void Function(RuntimeCatalogEntryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RuntimeCatalogEntry build() => _build();

  _$RuntimeCatalogEntry _build() {
    final _$result = _$v ??
        _$RuntimeCatalogEntry._(
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'RuntimeCatalogEntry', 'version'),
          url: url,
          sha256: sha256,
          sizeBytes: sizeBytes,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
