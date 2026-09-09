// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'modrinth_version_files_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ModrinthVersionFilesRequest extends ModrinthVersionFilesRequest {
  @override
  final BuiltList<String> hashes;

  factory _$ModrinthVersionFilesRequest(
          [void Function(ModrinthVersionFilesRequestBuilder)? updates]) =>
      (ModrinthVersionFilesRequestBuilder()..update(updates))._build();

  _$ModrinthVersionFilesRequest._({required this.hashes}) : super._();
  @override
  ModrinthVersionFilesRequest rebuild(
          void Function(ModrinthVersionFilesRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ModrinthVersionFilesRequestBuilder toBuilder() =>
      ModrinthVersionFilesRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ModrinthVersionFilesRequest && hashes == other.hashes;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, hashes.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ModrinthVersionFilesRequest')
          ..add('hashes', hashes))
        .toString();
  }
}

class ModrinthVersionFilesRequestBuilder
    implements
        Builder<ModrinthVersionFilesRequest,
            ModrinthVersionFilesRequestBuilder> {
  _$ModrinthVersionFilesRequest? _$v;

  ListBuilder<String>? _hashes;
  ListBuilder<String> get hashes => _$this._hashes ??= ListBuilder<String>();
  set hashes(ListBuilder<String>? hashes) => _$this._hashes = hashes;

  ModrinthVersionFilesRequestBuilder() {
    ModrinthVersionFilesRequest._defaults(this);
  }

  ModrinthVersionFilesRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _hashes = $v.hashes.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ModrinthVersionFilesRequest other) {
    _$v = other as _$ModrinthVersionFilesRequest;
  }

  @override
  void update(void Function(ModrinthVersionFilesRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ModrinthVersionFilesRequest build() => _build();

  _$ModrinthVersionFilesRequest _build() {
    _$ModrinthVersionFilesRequest _$result;
    try {
      _$result = _$v ??
          _$ModrinthVersionFilesRequest._(
            hashes: hashes.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'hashes';
        hashes.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ModrinthVersionFilesRequest', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
