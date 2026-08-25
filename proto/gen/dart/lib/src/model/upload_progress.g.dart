// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'upload_progress.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UploadProgress extends UploadProgress {
  @override
  final String uploadId;
  @override
  final int receivedBytes;
  @override
  final int totalBytes;

  factory _$UploadProgress([void Function(UploadProgressBuilder)? updates]) =>
      (UploadProgressBuilder()..update(updates))._build();

  _$UploadProgress._(
      {required this.uploadId,
      required this.receivedBytes,
      required this.totalBytes})
      : super._();
  @override
  UploadProgress rebuild(void Function(UploadProgressBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UploadProgressBuilder toBuilder() => UploadProgressBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UploadProgress &&
        uploadId == other.uploadId &&
        receivedBytes == other.receivedBytes &&
        totalBytes == other.totalBytes;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, uploadId.hashCode);
    _$hash = $jc(_$hash, receivedBytes.hashCode);
    _$hash = $jc(_$hash, totalBytes.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UploadProgress')
          ..add('uploadId', uploadId)
          ..add('receivedBytes', receivedBytes)
          ..add('totalBytes', totalBytes))
        .toString();
  }
}

class UploadProgressBuilder
    implements Builder<UploadProgress, UploadProgressBuilder> {
  _$UploadProgress? _$v;

  String? _uploadId;
  String? get uploadId => _$this._uploadId;
  set uploadId(String? uploadId) => _$this._uploadId = uploadId;

  int? _receivedBytes;
  int? get receivedBytes => _$this._receivedBytes;
  set receivedBytes(int? receivedBytes) =>
      _$this._receivedBytes = receivedBytes;

  int? _totalBytes;
  int? get totalBytes => _$this._totalBytes;
  set totalBytes(int? totalBytes) => _$this._totalBytes = totalBytes;

  UploadProgressBuilder() {
    UploadProgress._defaults(this);
  }

  UploadProgressBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _uploadId = $v.uploadId;
      _receivedBytes = $v.receivedBytes;
      _totalBytes = $v.totalBytes;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UploadProgress other) {
    _$v = other as _$UploadProgress;
  }

  @override
  void update(void Function(UploadProgressBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UploadProgress build() => _build();

  _$UploadProgress _build() {
    final _$result = _$v ??
        _$UploadProgress._(
          uploadId: BuiltValueNullFieldError.checkNotNull(
              uploadId, r'UploadProgress', 'uploadId'),
          receivedBytes: BuiltValueNullFieldError.checkNotNull(
              receivedBytes, r'UploadProgress', 'receivedBytes'),
          totalBytes: BuiltValueNullFieldError.checkNotNull(
              totalBytes, r'UploadProgress', 'totalBytes'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
