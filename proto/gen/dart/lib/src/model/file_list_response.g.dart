// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'file_list_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$FileListResponse extends FileListResponse {
  @override
  final String path;
  @override
  final BuiltList<FileEntry> entries;

  factory _$FileListResponse(
          [void Function(FileListResponseBuilder)? updates]) =>
      (FileListResponseBuilder()..update(updates))._build();

  _$FileListResponse._({required this.path, required this.entries}) : super._();
  @override
  FileListResponse rebuild(void Function(FileListResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  FileListResponseBuilder toBuilder() =>
      FileListResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is FileListResponse &&
        path == other.path &&
        entries == other.entries;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, path.hashCode);
    _$hash = $jc(_$hash, entries.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'FileListResponse')
          ..add('path', path)
          ..add('entries', entries))
        .toString();
  }
}

class FileListResponseBuilder
    implements Builder<FileListResponse, FileListResponseBuilder> {
  _$FileListResponse? _$v;

  String? _path;
  String? get path => _$this._path;
  set path(String? path) => _$this._path = path;

  ListBuilder<FileEntry>? _entries;
  ListBuilder<FileEntry> get entries =>
      _$this._entries ??= ListBuilder<FileEntry>();
  set entries(ListBuilder<FileEntry>? entries) => _$this._entries = entries;

  FileListResponseBuilder() {
    FileListResponse._defaults(this);
  }

  FileListResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _path = $v.path;
      _entries = $v.entries.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(FileListResponse other) {
    _$v = other as _$FileListResponse;
  }

  @override
  void update(void Function(FileListResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  FileListResponse build() => _build();

  _$FileListResponse _build() {
    _$FileListResponse _$result;
    try {
      _$result = _$v ??
          _$FileListResponse._(
            path: BuiltValueNullFieldError.checkNotNull(
                path, r'FileListResponse', 'path'),
            entries: entries.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'entries';
        entries.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'FileListResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
