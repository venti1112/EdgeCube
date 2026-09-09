// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'modrinth_version_file.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ModrinthVersionFile extends ModrinthVersionFile {
  @override
  final String url;
  @override
  final String filename;
  @override
  final bool primary;
  @override
  final int? size;
  @override
  final ModrinthFileHashes? hashes;

  factory _$ModrinthVersionFile(
          [void Function(ModrinthVersionFileBuilder)? updates]) =>
      (ModrinthVersionFileBuilder()..update(updates))._build();

  _$ModrinthVersionFile._(
      {required this.url,
      required this.filename,
      required this.primary,
      this.size,
      this.hashes})
      : super._();
  @override
  ModrinthVersionFile rebuild(
          void Function(ModrinthVersionFileBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ModrinthVersionFileBuilder toBuilder() =>
      ModrinthVersionFileBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ModrinthVersionFile &&
        url == other.url &&
        filename == other.filename &&
        primary == other.primary &&
        size == other.size &&
        hashes == other.hashes;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, url.hashCode);
    _$hash = $jc(_$hash, filename.hashCode);
    _$hash = $jc(_$hash, primary.hashCode);
    _$hash = $jc(_$hash, size.hashCode);
    _$hash = $jc(_$hash, hashes.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ModrinthVersionFile')
          ..add('url', url)
          ..add('filename', filename)
          ..add('primary', primary)
          ..add('size', size)
          ..add('hashes', hashes))
        .toString();
  }
}

class ModrinthVersionFileBuilder
    implements Builder<ModrinthVersionFile, ModrinthVersionFileBuilder> {
  _$ModrinthVersionFile? _$v;

  String? _url;
  String? get url => _$this._url;
  set url(String? url) => _$this._url = url;

  String? _filename;
  String? get filename => _$this._filename;
  set filename(String? filename) => _$this._filename = filename;

  bool? _primary;
  bool? get primary => _$this._primary;
  set primary(bool? primary) => _$this._primary = primary;

  int? _size;
  int? get size => _$this._size;
  set size(int? size) => _$this._size = size;

  ModrinthFileHashesBuilder? _hashes;
  ModrinthFileHashesBuilder get hashes =>
      _$this._hashes ??= ModrinthFileHashesBuilder();
  set hashes(ModrinthFileHashesBuilder? hashes) => _$this._hashes = hashes;

  ModrinthVersionFileBuilder() {
    ModrinthVersionFile._defaults(this);
  }

  ModrinthVersionFileBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _url = $v.url;
      _filename = $v.filename;
      _primary = $v.primary;
      _size = $v.size;
      _hashes = $v.hashes?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ModrinthVersionFile other) {
    _$v = other as _$ModrinthVersionFile;
  }

  @override
  void update(void Function(ModrinthVersionFileBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ModrinthVersionFile build() => _build();

  _$ModrinthVersionFile _build() {
    _$ModrinthVersionFile _$result;
    try {
      _$result = _$v ??
          _$ModrinthVersionFile._(
            url: BuiltValueNullFieldError.checkNotNull(
                url, r'ModrinthVersionFile', 'url'),
            filename: BuiltValueNullFieldError.checkNotNull(
                filename, r'ModrinthVersionFile', 'filename'),
            primary: BuiltValueNullFieldError.checkNotNull(
                primary, r'ModrinthVersionFile', 'primary'),
            size: size,
            hashes: _hashes?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'hashes';
        _hashes?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ModrinthVersionFile', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
