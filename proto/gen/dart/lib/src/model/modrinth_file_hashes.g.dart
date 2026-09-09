// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'modrinth_file_hashes.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ModrinthFileHashes extends ModrinthFileHashes {
  @override
  final String? sha1;
  @override
  final String? sha512;

  factory _$ModrinthFileHashes(
          [void Function(ModrinthFileHashesBuilder)? updates]) =>
      (ModrinthFileHashesBuilder()..update(updates))._build();

  _$ModrinthFileHashes._({this.sha1, this.sha512}) : super._();
  @override
  ModrinthFileHashes rebuild(
          void Function(ModrinthFileHashesBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ModrinthFileHashesBuilder toBuilder() =>
      ModrinthFileHashesBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ModrinthFileHashes &&
        sha1 == other.sha1 &&
        sha512 == other.sha512;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, sha1.hashCode);
    _$hash = $jc(_$hash, sha512.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ModrinthFileHashes')
          ..add('sha1', sha1)
          ..add('sha512', sha512))
        .toString();
  }
}

class ModrinthFileHashesBuilder
    implements Builder<ModrinthFileHashes, ModrinthFileHashesBuilder> {
  _$ModrinthFileHashes? _$v;

  String? _sha1;
  String? get sha1 => _$this._sha1;
  set sha1(String? sha1) => _$this._sha1 = sha1;

  String? _sha512;
  String? get sha512 => _$this._sha512;
  set sha512(String? sha512) => _$this._sha512 = sha512;

  ModrinthFileHashesBuilder() {
    ModrinthFileHashes._defaults(this);
  }

  ModrinthFileHashesBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _sha1 = $v.sha1;
      _sha512 = $v.sha512;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ModrinthFileHashes other) {
    _$v = other as _$ModrinthFileHashes;
  }

  @override
  void update(void Function(ModrinthFileHashesBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ModrinthFileHashes build() => _build();

  _$ModrinthFileHashes _build() {
    final _$result = _$v ??
        _$ModrinthFileHashes._(
          sha1: sha1,
          sha512: sha512,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
