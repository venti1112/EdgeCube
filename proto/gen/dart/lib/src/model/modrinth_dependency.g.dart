// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'modrinth_dependency.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ModrinthDependency extends ModrinthDependency {
  @override
  final String? projectId;
  @override
  final String? versionId;
  @override
  final String dependencyType;

  factory _$ModrinthDependency(
          [void Function(ModrinthDependencyBuilder)? updates]) =>
      (ModrinthDependencyBuilder()..update(updates))._build();

  _$ModrinthDependency._(
      {this.projectId, this.versionId, required this.dependencyType})
      : super._();
  @override
  ModrinthDependency rebuild(
          void Function(ModrinthDependencyBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ModrinthDependencyBuilder toBuilder() =>
      ModrinthDependencyBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ModrinthDependency &&
        projectId == other.projectId &&
        versionId == other.versionId &&
        dependencyType == other.dependencyType;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, projectId.hashCode);
    _$hash = $jc(_$hash, versionId.hashCode);
    _$hash = $jc(_$hash, dependencyType.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ModrinthDependency')
          ..add('projectId', projectId)
          ..add('versionId', versionId)
          ..add('dependencyType', dependencyType))
        .toString();
  }
}

class ModrinthDependencyBuilder
    implements Builder<ModrinthDependency, ModrinthDependencyBuilder> {
  _$ModrinthDependency? _$v;

  String? _projectId;
  String? get projectId => _$this._projectId;
  set projectId(String? projectId) => _$this._projectId = projectId;

  String? _versionId;
  String? get versionId => _$this._versionId;
  set versionId(String? versionId) => _$this._versionId = versionId;

  String? _dependencyType;
  String? get dependencyType => _$this._dependencyType;
  set dependencyType(String? dependencyType) =>
      _$this._dependencyType = dependencyType;

  ModrinthDependencyBuilder() {
    ModrinthDependency._defaults(this);
  }

  ModrinthDependencyBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _projectId = $v.projectId;
      _versionId = $v.versionId;
      _dependencyType = $v.dependencyType;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ModrinthDependency other) {
    _$v = other as _$ModrinthDependency;
  }

  @override
  void update(void Function(ModrinthDependencyBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ModrinthDependency build() => _build();

  _$ModrinthDependency _build() {
    final _$result = _$v ??
        _$ModrinthDependency._(
          projectId: projectId,
          versionId: versionId,
          dependencyType: BuiltValueNullFieldError.checkNotNull(
              dependencyType, r'ModrinthDependency', 'dependencyType'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
