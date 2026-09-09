// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'modrinth_version.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ModrinthVersion extends ModrinthVersion {
  @override
  final String id;
  @override
  final String projectId;
  @override
  final String? name;
  @override
  final String versionNumber;
  @override
  final BuiltList<String>? gameVersions;
  @override
  final BuiltList<String>? loaders;
  @override
  final BuiltList<ModrinthVersionFile>? files;
  @override
  final BuiltList<ModrinthDependency>? dependencies;

  factory _$ModrinthVersion([void Function(ModrinthVersionBuilder)? updates]) =>
      (ModrinthVersionBuilder()..update(updates))._build();

  _$ModrinthVersion._(
      {required this.id,
      required this.projectId,
      this.name,
      required this.versionNumber,
      this.gameVersions,
      this.loaders,
      this.files,
      this.dependencies})
      : super._();
  @override
  ModrinthVersion rebuild(void Function(ModrinthVersionBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ModrinthVersionBuilder toBuilder() => ModrinthVersionBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ModrinthVersion &&
        id == other.id &&
        projectId == other.projectId &&
        name == other.name &&
        versionNumber == other.versionNumber &&
        gameVersions == other.gameVersions &&
        loaders == other.loaders &&
        files == other.files &&
        dependencies == other.dependencies;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, projectId.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, versionNumber.hashCode);
    _$hash = $jc(_$hash, gameVersions.hashCode);
    _$hash = $jc(_$hash, loaders.hashCode);
    _$hash = $jc(_$hash, files.hashCode);
    _$hash = $jc(_$hash, dependencies.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ModrinthVersion')
          ..add('id', id)
          ..add('projectId', projectId)
          ..add('name', name)
          ..add('versionNumber', versionNumber)
          ..add('gameVersions', gameVersions)
          ..add('loaders', loaders)
          ..add('files', files)
          ..add('dependencies', dependencies))
        .toString();
  }
}

class ModrinthVersionBuilder
    implements Builder<ModrinthVersion, ModrinthVersionBuilder> {
  _$ModrinthVersion? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _projectId;
  String? get projectId => _$this._projectId;
  set projectId(String? projectId) => _$this._projectId = projectId;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _versionNumber;
  String? get versionNumber => _$this._versionNumber;
  set versionNumber(String? versionNumber) =>
      _$this._versionNumber = versionNumber;

  ListBuilder<String>? _gameVersions;
  ListBuilder<String> get gameVersions =>
      _$this._gameVersions ??= ListBuilder<String>();
  set gameVersions(ListBuilder<String>? gameVersions) =>
      _$this._gameVersions = gameVersions;

  ListBuilder<String>? _loaders;
  ListBuilder<String> get loaders => _$this._loaders ??= ListBuilder<String>();
  set loaders(ListBuilder<String>? loaders) => _$this._loaders = loaders;

  ListBuilder<ModrinthVersionFile>? _files;
  ListBuilder<ModrinthVersionFile> get files =>
      _$this._files ??= ListBuilder<ModrinthVersionFile>();
  set files(ListBuilder<ModrinthVersionFile>? files) => _$this._files = files;

  ListBuilder<ModrinthDependency>? _dependencies;
  ListBuilder<ModrinthDependency> get dependencies =>
      _$this._dependencies ??= ListBuilder<ModrinthDependency>();
  set dependencies(ListBuilder<ModrinthDependency>? dependencies) =>
      _$this._dependencies = dependencies;

  ModrinthVersionBuilder() {
    ModrinthVersion._defaults(this);
  }

  ModrinthVersionBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _projectId = $v.projectId;
      _name = $v.name;
      _versionNumber = $v.versionNumber;
      _gameVersions = $v.gameVersions?.toBuilder();
      _loaders = $v.loaders?.toBuilder();
      _files = $v.files?.toBuilder();
      _dependencies = $v.dependencies?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ModrinthVersion other) {
    _$v = other as _$ModrinthVersion;
  }

  @override
  void update(void Function(ModrinthVersionBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ModrinthVersion build() => _build();

  _$ModrinthVersion _build() {
    _$ModrinthVersion _$result;
    try {
      _$result = _$v ??
          _$ModrinthVersion._(
            id: BuiltValueNullFieldError.checkNotNull(
                id, r'ModrinthVersion', 'id'),
            projectId: BuiltValueNullFieldError.checkNotNull(
                projectId, r'ModrinthVersion', 'projectId'),
            name: name,
            versionNumber: BuiltValueNullFieldError.checkNotNull(
                versionNumber, r'ModrinthVersion', 'versionNumber'),
            gameVersions: _gameVersions?.build(),
            loaders: _loaders?.build(),
            files: _files?.build(),
            dependencies: _dependencies?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'gameVersions';
        _gameVersions?.build();
        _$failedField = 'loaders';
        _loaders?.build();
        _$failedField = 'files';
        _files?.build();
        _$failedField = 'dependencies';
        _dependencies?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ModrinthVersion', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
