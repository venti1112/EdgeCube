// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'upload_complete_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UploadCompleteRequest extends UploadCompleteRequest {
  @override
  final String uploadId;

  factory _$UploadCompleteRequest(
          [void Function(UploadCompleteRequestBuilder)? updates]) =>
      (UploadCompleteRequestBuilder()..update(updates))._build();

  _$UploadCompleteRequest._({required this.uploadId}) : super._();
  @override
  UploadCompleteRequest rebuild(
          void Function(UploadCompleteRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UploadCompleteRequestBuilder toBuilder() =>
      UploadCompleteRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UploadCompleteRequest && uploadId == other.uploadId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, uploadId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UploadCompleteRequest')
          ..add('uploadId', uploadId))
        .toString();
  }
}

class UploadCompleteRequestBuilder
    implements Builder<UploadCompleteRequest, UploadCompleteRequestBuilder> {
  _$UploadCompleteRequest? _$v;

  String? _uploadId;
  String? get uploadId => _$this._uploadId;
  set uploadId(String? uploadId) => _$this._uploadId = uploadId;

  UploadCompleteRequestBuilder() {
    UploadCompleteRequest._defaults(this);
  }

  UploadCompleteRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _uploadId = $v.uploadId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UploadCompleteRequest other) {
    _$v = other as _$UploadCompleteRequest;
  }

  @override
  void update(void Function(UploadCompleteRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UploadCompleteRequest build() => _build();

  _$UploadCompleteRequest _build() {
    final _$result = _$v ??
        _$UploadCompleteRequest._(
          uploadId: BuiltValueNullFieldError.checkNotNull(
              uploadId, r'UploadCompleteRequest', 'uploadId'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
