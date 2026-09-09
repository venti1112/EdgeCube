// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'import_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ImportRequest extends ImportRequest {
  @override
  final String sourceInstanceId;
  @override
  final String archivePath;

  factory _$ImportRequest([void Function(ImportRequestBuilder)? updates]) =>
      (ImportRequestBuilder()..update(updates))._build();

  _$ImportRequest._({required this.sourceInstanceId, required this.archivePath})
      : super._();
  @override
  ImportRequest rebuild(void Function(ImportRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ImportRequestBuilder toBuilder() => ImportRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ImportRequest &&
        sourceInstanceId == other.sourceInstanceId &&
        archivePath == other.archivePath;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, sourceInstanceId.hashCode);
    _$hash = $jc(_$hash, archivePath.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ImportRequest')
          ..add('sourceInstanceId', sourceInstanceId)
          ..add('archivePath', archivePath))
        .toString();
  }
}

class ImportRequestBuilder
    implements Builder<ImportRequest, ImportRequestBuilder> {
  _$ImportRequest? _$v;

  String? _sourceInstanceId;
  String? get sourceInstanceId => _$this._sourceInstanceId;
  set sourceInstanceId(String? sourceInstanceId) =>
      _$this._sourceInstanceId = sourceInstanceId;

  String? _archivePath;
  String? get archivePath => _$this._archivePath;
  set archivePath(String? archivePath) => _$this._archivePath = archivePath;

  ImportRequestBuilder() {
    ImportRequest._defaults(this);
  }

  ImportRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _sourceInstanceId = $v.sourceInstanceId;
      _archivePath = $v.archivePath;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ImportRequest other) {
    _$v = other as _$ImportRequest;
  }

  @override
  void update(void Function(ImportRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ImportRequest build() => _build();

  _$ImportRequest _build() {
    final _$result = _$v ??
        _$ImportRequest._(
          sourceInstanceId: BuiltValueNullFieldError.checkNotNull(
              sourceInstanceId, r'ImportRequest', 'sourceInstanceId'),
          archivePath: BuiltValueNullFieldError.checkNotNull(
              archivePath, r'ImportRequest', 'archivePath'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
