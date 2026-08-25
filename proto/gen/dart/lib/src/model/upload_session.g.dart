// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'upload_session.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UploadSession extends UploadSession {
  @override
  final String uploadId;
  @override
  final int receivedBytes;

  factory _$UploadSession([void Function(UploadSessionBuilder)? updates]) =>
      (UploadSessionBuilder()..update(updates))._build();

  _$UploadSession._({required this.uploadId, required this.receivedBytes})
      : super._();
  @override
  UploadSession rebuild(void Function(UploadSessionBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UploadSessionBuilder toBuilder() => UploadSessionBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UploadSession &&
        uploadId == other.uploadId &&
        receivedBytes == other.receivedBytes;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, uploadId.hashCode);
    _$hash = $jc(_$hash, receivedBytes.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UploadSession')
          ..add('uploadId', uploadId)
          ..add('receivedBytes', receivedBytes))
        .toString();
  }
}

class UploadSessionBuilder
    implements Builder<UploadSession, UploadSessionBuilder> {
  _$UploadSession? _$v;

  String? _uploadId;
  String? get uploadId => _$this._uploadId;
  set uploadId(String? uploadId) => _$this._uploadId = uploadId;

  int? _receivedBytes;
  int? get receivedBytes => _$this._receivedBytes;
  set receivedBytes(int? receivedBytes) =>
      _$this._receivedBytes = receivedBytes;

  UploadSessionBuilder() {
    UploadSession._defaults(this);
  }

  UploadSessionBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _uploadId = $v.uploadId;
      _receivedBytes = $v.receivedBytes;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UploadSession other) {
    _$v = other as _$UploadSession;
  }

  @override
  void update(void Function(UploadSessionBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UploadSession build() => _build();

  _$UploadSession _build() {
    final _$result = _$v ??
        _$UploadSession._(
          uploadId: BuiltValueNullFieldError.checkNotNull(
              uploadId, r'UploadSession', 'uploadId'),
          receivedBytes: BuiltValueNullFieldError.checkNotNull(
              receivedBytes, r'UploadSession', 'receivedBytes'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
