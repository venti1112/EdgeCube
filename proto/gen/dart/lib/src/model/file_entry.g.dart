// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'file_entry.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$FileEntry extends FileEntry {
  @override
  final String name;
  @override
  final String path;
  @override
  final bool isDirectory;
  @override
  final int sizeBytes;
  @override
  final DateTime modifiedAt;
  @override
  final bool? executable;

  factory _$FileEntry([void Function(FileEntryBuilder)? updates]) =>
      (FileEntryBuilder()..update(updates))._build();

  _$FileEntry._(
      {required this.name,
      required this.path,
      required this.isDirectory,
      required this.sizeBytes,
      required this.modifiedAt,
      this.executable})
      : super._();
  @override
  FileEntry rebuild(void Function(FileEntryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  FileEntryBuilder toBuilder() => FileEntryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is FileEntry &&
        name == other.name &&
        path == other.path &&
        isDirectory == other.isDirectory &&
        sizeBytes == other.sizeBytes &&
        modifiedAt == other.modifiedAt &&
        executable == other.executable;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, path.hashCode);
    _$hash = $jc(_$hash, isDirectory.hashCode);
    _$hash = $jc(_$hash, sizeBytes.hashCode);
    _$hash = $jc(_$hash, modifiedAt.hashCode);
    _$hash = $jc(_$hash, executable.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'FileEntry')
          ..add('name', name)
          ..add('path', path)
          ..add('isDirectory', isDirectory)
          ..add('sizeBytes', sizeBytes)
          ..add('modifiedAt', modifiedAt)
          ..add('executable', executable))
        .toString();
  }
}

class FileEntryBuilder implements Builder<FileEntry, FileEntryBuilder> {
  _$FileEntry? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _path;
  String? get path => _$this._path;
  set path(String? path) => _$this._path = path;

  bool? _isDirectory;
  bool? get isDirectory => _$this._isDirectory;
  set isDirectory(bool? isDirectory) => _$this._isDirectory = isDirectory;

  int? _sizeBytes;
  int? get sizeBytes => _$this._sizeBytes;
  set sizeBytes(int? sizeBytes) => _$this._sizeBytes = sizeBytes;

  DateTime? _modifiedAt;
  DateTime? get modifiedAt => _$this._modifiedAt;
  set modifiedAt(DateTime? modifiedAt) => _$this._modifiedAt = modifiedAt;

  bool? _executable;
  bool? get executable => _$this._executable;
  set executable(bool? executable) => _$this._executable = executable;

  FileEntryBuilder() {
    FileEntry._defaults(this);
  }

  FileEntryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _path = $v.path;
      _isDirectory = $v.isDirectory;
      _sizeBytes = $v.sizeBytes;
      _modifiedAt = $v.modifiedAt;
      _executable = $v.executable;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(FileEntry other) {
    _$v = other as _$FileEntry;
  }

  @override
  void update(void Function(FileEntryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  FileEntry build() => _build();

  _$FileEntry _build() {
    final _$result = _$v ??
        _$FileEntry._(
          name:
              BuiltValueNullFieldError.checkNotNull(name, r'FileEntry', 'name'),
          path:
              BuiltValueNullFieldError.checkNotNull(path, r'FileEntry', 'path'),
          isDirectory: BuiltValueNullFieldError.checkNotNull(
              isDirectory, r'FileEntry', 'isDirectory'),
          sizeBytes: BuiltValueNullFieldError.checkNotNull(
              sizeBytes, r'FileEntry', 'sizeBytes'),
          modifiedAt: BuiltValueNullFieldError.checkNotNull(
              modifiedAt, r'FileEntry', 'modifiedAt'),
          executable: executable,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
