// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'modrinth_search_hit.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ModrinthSearchHit extends ModrinthSearchHit {
  @override
  final String slug;
  @override
  final String projectId;
  @override
  final String title;
  @override
  final String? description;
  @override
  final BuiltList<String>? categories;
  @override
  final BuiltList<String>? versions;
  @override
  final String projectType;
  @override
  final String? iconUrl;
  @override
  final String? author;
  @override
  final int? downloads;
  @override
  final int? follows;
  @override
  final String? latestVersion;

  factory _$ModrinthSearchHit(
          [void Function(ModrinthSearchHitBuilder)? updates]) =>
      (ModrinthSearchHitBuilder()..update(updates))._build();

  _$ModrinthSearchHit._(
      {required this.slug,
      required this.projectId,
      required this.title,
      this.description,
      this.categories,
      this.versions,
      required this.projectType,
      this.iconUrl,
      this.author,
      this.downloads,
      this.follows,
      this.latestVersion})
      : super._();
  @override
  ModrinthSearchHit rebuild(void Function(ModrinthSearchHitBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ModrinthSearchHitBuilder toBuilder() =>
      ModrinthSearchHitBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ModrinthSearchHit &&
        slug == other.slug &&
        projectId == other.projectId &&
        title == other.title &&
        description == other.description &&
        categories == other.categories &&
        versions == other.versions &&
        projectType == other.projectType &&
        iconUrl == other.iconUrl &&
        author == other.author &&
        downloads == other.downloads &&
        follows == other.follows &&
        latestVersion == other.latestVersion;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, slug.hashCode);
    _$hash = $jc(_$hash, projectId.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, description.hashCode);
    _$hash = $jc(_$hash, categories.hashCode);
    _$hash = $jc(_$hash, versions.hashCode);
    _$hash = $jc(_$hash, projectType.hashCode);
    _$hash = $jc(_$hash, iconUrl.hashCode);
    _$hash = $jc(_$hash, author.hashCode);
    _$hash = $jc(_$hash, downloads.hashCode);
    _$hash = $jc(_$hash, follows.hashCode);
    _$hash = $jc(_$hash, latestVersion.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ModrinthSearchHit')
          ..add('slug', slug)
          ..add('projectId', projectId)
          ..add('title', title)
          ..add('description', description)
          ..add('categories', categories)
          ..add('versions', versions)
          ..add('projectType', projectType)
          ..add('iconUrl', iconUrl)
          ..add('author', author)
          ..add('downloads', downloads)
          ..add('follows', follows)
          ..add('latestVersion', latestVersion))
        .toString();
  }
}

class ModrinthSearchHitBuilder
    implements Builder<ModrinthSearchHit, ModrinthSearchHitBuilder> {
  _$ModrinthSearchHit? _$v;

  String? _slug;
  String? get slug => _$this._slug;
  set slug(String? slug) => _$this._slug = slug;

  String? _projectId;
  String? get projectId => _$this._projectId;
  set projectId(String? projectId) => _$this._projectId = projectId;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  String? _description;
  String? get description => _$this._description;
  set description(String? description) => _$this._description = description;

  ListBuilder<String>? _categories;
  ListBuilder<String> get categories =>
      _$this._categories ??= ListBuilder<String>();
  set categories(ListBuilder<String>? categories) =>
      _$this._categories = categories;

  ListBuilder<String>? _versions;
  ListBuilder<String> get versions =>
      _$this._versions ??= ListBuilder<String>();
  set versions(ListBuilder<String>? versions) => _$this._versions = versions;

  String? _projectType;
  String? get projectType => _$this._projectType;
  set projectType(String? projectType) => _$this._projectType = projectType;

  String? _iconUrl;
  String? get iconUrl => _$this._iconUrl;
  set iconUrl(String? iconUrl) => _$this._iconUrl = iconUrl;

  String? _author;
  String? get author => _$this._author;
  set author(String? author) => _$this._author = author;

  int? _downloads;
  int? get downloads => _$this._downloads;
  set downloads(int? downloads) => _$this._downloads = downloads;

  int? _follows;
  int? get follows => _$this._follows;
  set follows(int? follows) => _$this._follows = follows;

  String? _latestVersion;
  String? get latestVersion => _$this._latestVersion;
  set latestVersion(String? latestVersion) =>
      _$this._latestVersion = latestVersion;

  ModrinthSearchHitBuilder() {
    ModrinthSearchHit._defaults(this);
  }

  ModrinthSearchHitBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _slug = $v.slug;
      _projectId = $v.projectId;
      _title = $v.title;
      _description = $v.description;
      _categories = $v.categories?.toBuilder();
      _versions = $v.versions?.toBuilder();
      _projectType = $v.projectType;
      _iconUrl = $v.iconUrl;
      _author = $v.author;
      _downloads = $v.downloads;
      _follows = $v.follows;
      _latestVersion = $v.latestVersion;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ModrinthSearchHit other) {
    _$v = other as _$ModrinthSearchHit;
  }

  @override
  void update(void Function(ModrinthSearchHitBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ModrinthSearchHit build() => _build();

  _$ModrinthSearchHit _build() {
    _$ModrinthSearchHit _$result;
    try {
      _$result = _$v ??
          _$ModrinthSearchHit._(
            slug: BuiltValueNullFieldError.checkNotNull(
                slug, r'ModrinthSearchHit', 'slug'),
            projectId: BuiltValueNullFieldError.checkNotNull(
                projectId, r'ModrinthSearchHit', 'projectId'),
            title: BuiltValueNullFieldError.checkNotNull(
                title, r'ModrinthSearchHit', 'title'),
            description: description,
            categories: _categories?.build(),
            versions: _versions?.build(),
            projectType: BuiltValueNullFieldError.checkNotNull(
                projectType, r'ModrinthSearchHit', 'projectType'),
            iconUrl: iconUrl,
            author: author,
            downloads: downloads,
            follows: follows,
            latestVersion: latestVersion,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'categories';
        _categories?.build();
        _$failedField = 'versions';
        _versions?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ModrinthSearchHit', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
