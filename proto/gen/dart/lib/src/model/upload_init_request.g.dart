// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'upload_init_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UploadInitRequest extends UploadInitRequest {
  @override
  final String instanceId;
  @override
  final String path;
  @override
  final String fileName;
  @override
  final int sizeBytes;
  @override
  final String? sha256;
  @override
  final bool? autoExtract;

  factory _$UploadInitRequest(
          [void Function(UploadInitRequestBuilder)? updates]) =>
      (UploadInitRequestBuilder()..update(updates))._build();

  _$UploadInitRequest._(
      {required this.instanceId,
      required this.path,
      required this.fileName,
      required this.sizeBytes,
      this.sha256,
      this.autoExtract})
      : super._();
  @override
  UploadInitRequest rebuild(void Function(UploadInitRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UploadInitRequestBuilder toBuilder() =>
      UploadInitRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UploadInitRequest &&
        instanceId == other.instanceId &&
        path == other.path &&
        fileName == other.fileName &&
        sizeBytes == other.sizeBytes &&
        sha256 == other.sha256 &&
        autoExtract == other.autoExtract;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, instanceId.hashCode);
    _$hash = $jc(_$hash, path.hashCode);
    _$hash = $jc(_$hash, fileName.hashCode);
    _$hash = $jc(_$hash, sizeBytes.hashCode);
    _$hash = $jc(_$hash, sha256.hashCode);
    _$hash = $jc(_$hash, autoExtract.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UploadInitRequest')
          ..add('instanceId', instanceId)
          ..add('path', path)
          ..add('fileName', fileName)
          ..add('sizeBytes', sizeBytes)
          ..add('sha256', sha256)
          ..add('autoExtract', autoExtract))
        .toString();
  }
}

class UploadInitRequestBuilder
    implements Builder<UploadInitRequest, UploadInitRequestBuilder> {
  _$UploadInitRequest? _$v;

  String? _instanceId;
  String? get instanceId => _$this._instanceId;
  set instanceId(String? instanceId) => _$this._instanceId = instanceId;

  String? _path;
  String? get path => _$this._path;
  set path(String? path) => _$this._path = path;

  String? _fileName;
  String? get fileName => _$this._fileName;
  set fileName(String? fileName) => _$this._fileName = fileName;

  int? _sizeBytes;
  int? get sizeBytes => _$this._sizeBytes;
  set sizeBytes(int? sizeBytes) => _$this._sizeBytes = sizeBytes;

  String? _sha256;
  String? get sha256 => _$this._sha256;
  set sha256(String? sha256) => _$this._sha256 = sha256;

  bool? _autoExtract;
  bool? get autoExtract => _$this._autoExtract;
  set autoExtract(bool? autoExtract) => _$this._autoExtract = autoExtract;

  UploadInitRequestBuilder() {
    UploadInitRequest._defaults(this);
  }

  UploadInitRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _instanceId = $v.instanceId;
      _path = $v.path;
      _fileName = $v.fileName;
      _sizeBytes = $v.sizeBytes;
      _sha256 = $v.sha256;
      _autoExtract = $v.autoExtract;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UploadInitRequest other) {
    _$v = other as _$UploadInitRequest;
  }

  @override
  void update(void Function(UploadInitRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UploadInitRequest build() => _build();

  _$UploadInitRequest _build() {
    final _$result = _$v ??
        _$UploadInitRequest._(
          instanceId: BuiltValueNullFieldError.checkNotNull(
              instanceId, r'UploadInitRequest', 'instanceId'),
          path: BuiltValueNullFieldError.checkNotNull(
              path, r'UploadInitRequest', 'path'),
          fileName: BuiltValueNullFieldError.checkNotNull(
              fileName, r'UploadInitRequest', 'fileName'),
          sizeBytes: BuiltValueNullFieldError.checkNotNull(
              sizeBytes, r'UploadInitRequest', 'sizeBytes'),
          sha256: sha256,
          autoExtract: autoExtract,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
