// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'server_core_update_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ServerCoreUpdateRequest extends ServerCoreUpdateRequest {
  @override
  final String downloadUrl;
  @override
  final String? sha256;
  @override
  final String? fileName;

  factory _$ServerCoreUpdateRequest(
          [void Function(ServerCoreUpdateRequestBuilder)? updates]) =>
      (ServerCoreUpdateRequestBuilder()..update(updates))._build();

  _$ServerCoreUpdateRequest._(
      {required this.downloadUrl, this.sha256, this.fileName})
      : super._();
  @override
  ServerCoreUpdateRequest rebuild(
          void Function(ServerCoreUpdateRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ServerCoreUpdateRequestBuilder toBuilder() =>
      ServerCoreUpdateRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ServerCoreUpdateRequest &&
        downloadUrl == other.downloadUrl &&
        sha256 == other.sha256 &&
        fileName == other.fileName;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, downloadUrl.hashCode);
    _$hash = $jc(_$hash, sha256.hashCode);
    _$hash = $jc(_$hash, fileName.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ServerCoreUpdateRequest')
          ..add('downloadUrl', downloadUrl)
          ..add('sha256', sha256)
          ..add('fileName', fileName))
        .toString();
  }
}

class ServerCoreUpdateRequestBuilder
    implements
        Builder<ServerCoreUpdateRequest, ServerCoreUpdateRequestBuilder> {
  _$ServerCoreUpdateRequest? _$v;

  String? _downloadUrl;
  String? get downloadUrl => _$this._downloadUrl;
  set downloadUrl(String? downloadUrl) => _$this._downloadUrl = downloadUrl;

  String? _sha256;
  String? get sha256 => _$this._sha256;
  set sha256(String? sha256) => _$this._sha256 = sha256;

  String? _fileName;
  String? get fileName => _$this._fileName;
  set fileName(String? fileName) => _$this._fileName = fileName;

  ServerCoreUpdateRequestBuilder() {
    ServerCoreUpdateRequest._defaults(this);
  }

  ServerCoreUpdateRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _downloadUrl = $v.downloadUrl;
      _sha256 = $v.sha256;
      _fileName = $v.fileName;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ServerCoreUpdateRequest other) {
    _$v = other as _$ServerCoreUpdateRequest;
  }

  @override
  void update(void Function(ServerCoreUpdateRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ServerCoreUpdateRequest build() => _build();

  _$ServerCoreUpdateRequest _build() {
    final _$result = _$v ??
        _$ServerCoreUpdateRequest._(
          downloadUrl: BuiltValueNullFieldError.checkNotNull(
              downloadUrl, r'ServerCoreUpdateRequest', 'downloadUrl'),
          sha256: sha256,
          fileName: fileName,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
