// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mod_metadata_list_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ModMetadataListResponse extends ModMetadataListResponse {
  @override
  final String path;
  @override
  final BuiltList<ModMetadataEntry> items;

  factory _$ModMetadataListResponse(
          [void Function(ModMetadataListResponseBuilder)? updates]) =>
      (ModMetadataListResponseBuilder()..update(updates))._build();

  _$ModMetadataListResponse._({required this.path, required this.items})
      : super._();
  @override
  ModMetadataListResponse rebuild(
          void Function(ModMetadataListResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ModMetadataListResponseBuilder toBuilder() =>
      ModMetadataListResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ModMetadataListResponse &&
        path == other.path &&
        items == other.items;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, path.hashCode);
    _$hash = $jc(_$hash, items.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ModMetadataListResponse')
          ..add('path', path)
          ..add('items', items))
        .toString();
  }
}

class ModMetadataListResponseBuilder
    implements
        Builder<ModMetadataListResponse, ModMetadataListResponseBuilder> {
  _$ModMetadataListResponse? _$v;

  String? _path;
  String? get path => _$this._path;
  set path(String? path) => _$this._path = path;

  ListBuilder<ModMetadataEntry>? _items;
  ListBuilder<ModMetadataEntry> get items =>
      _$this._items ??= ListBuilder<ModMetadataEntry>();
  set items(ListBuilder<ModMetadataEntry>? items) => _$this._items = items;

  ModMetadataListResponseBuilder() {
    ModMetadataListResponse._defaults(this);
  }

  ModMetadataListResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _path = $v.path;
      _items = $v.items.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ModMetadataListResponse other) {
    _$v = other as _$ModMetadataListResponse;
  }

  @override
  void update(void Function(ModMetadataListResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ModMetadataListResponse build() => _build();

  _$ModMetadataListResponse _build() {
    _$ModMetadataListResponse _$result;
    try {
      _$result = _$v ??
          _$ModMetadataListResponse._(
            path: BuiltValueNullFieldError.checkNotNull(
                path, r'ModMetadataListResponse', 'path'),
            items: items.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'items';
        items.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ModMetadataListResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
