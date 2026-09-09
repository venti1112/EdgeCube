// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'modrinth_project.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ModrinthProject extends ModrinthProject {
  @override
  final String id;
  @override
  final String slug;
  @override
  final String title;
  @override
  final String? description;
  @override
  final String? iconUrl;
  @override
  final String projectType;

  factory _$ModrinthProject([void Function(ModrinthProjectBuilder)? updates]) =>
      (ModrinthProjectBuilder()..update(updates))._build();

  _$ModrinthProject._(
      {required this.id,
      required this.slug,
      required this.title,
      this.description,
      this.iconUrl,
      required this.projectType})
      : super._();
  @override
  ModrinthProject rebuild(void Function(ModrinthProjectBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ModrinthProjectBuilder toBuilder() => ModrinthProjectBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ModrinthProject &&
        id == other.id &&
        slug == other.slug &&
        title == other.title &&
        description == other.description &&
        iconUrl == other.iconUrl &&
        projectType == other.projectType;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, slug.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, description.hashCode);
    _$hash = $jc(_$hash, iconUrl.hashCode);
    _$hash = $jc(_$hash, projectType.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ModrinthProject')
          ..add('id', id)
          ..add('slug', slug)
          ..add('title', title)
          ..add('description', description)
          ..add('iconUrl', iconUrl)
          ..add('projectType', projectType))
        .toString();
  }
}

class ModrinthProjectBuilder
    implements Builder<ModrinthProject, ModrinthProjectBuilder> {
  _$ModrinthProject? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _slug;
  String? get slug => _$this._slug;
  set slug(String? slug) => _$this._slug = slug;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  String? _description;
  String? get description => _$this._description;
  set description(String? description) => _$this._description = description;

  String? _iconUrl;
  String? get iconUrl => _$this._iconUrl;
  set iconUrl(String? iconUrl) => _$this._iconUrl = iconUrl;

  String? _projectType;
  String? get projectType => _$this._projectType;
  set projectType(String? projectType) => _$this._projectType = projectType;

  ModrinthProjectBuilder() {
    ModrinthProject._defaults(this);
  }

  ModrinthProjectBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _slug = $v.slug;
      _title = $v.title;
      _description = $v.description;
      _iconUrl = $v.iconUrl;
      _projectType = $v.projectType;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ModrinthProject other) {
    _$v = other as _$ModrinthProject;
  }

  @override
  void update(void Function(ModrinthProjectBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ModrinthProject build() => _build();

  _$ModrinthProject _build() {
    final _$result = _$v ??
        _$ModrinthProject._(
          id: BuiltValueNullFieldError.checkNotNull(
              id, r'ModrinthProject', 'id'),
          slug: BuiltValueNullFieldError.checkNotNull(
              slug, r'ModrinthProject', 'slug'),
          title: BuiltValueNullFieldError.checkNotNull(
              title, r'ModrinthProject', 'title'),
          description: description,
          iconUrl: iconUrl,
          projectType: BuiltValueNullFieldError.checkNotNull(
              projectType, r'ModrinthProject', 'projectType'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
