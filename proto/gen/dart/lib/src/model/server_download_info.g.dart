// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'server_download_info.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ServerDownloadInfo extends ServerDownloadInfo {
  @override
  final String url;
  @override
  final String fileName;
  @override
  final String? checksum;
  @override
  final int? sizeBytes;

  factory _$ServerDownloadInfo(
          [void Function(ServerDownloadInfoBuilder)? updates]) =>
      (ServerDownloadInfoBuilder()..update(updates))._build();

  _$ServerDownloadInfo._(
      {required this.url,
      required this.fileName,
      this.checksum,
      this.sizeBytes})
      : super._();
  @override
  ServerDownloadInfo rebuild(
          void Function(ServerDownloadInfoBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ServerDownloadInfoBuilder toBuilder() =>
      ServerDownloadInfoBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ServerDownloadInfo &&
        url == other.url &&
        fileName == other.fileName &&
        checksum == other.checksum &&
        sizeBytes == other.sizeBytes;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, url.hashCode);
    _$hash = $jc(_$hash, fileName.hashCode);
    _$hash = $jc(_$hash, checksum.hashCode);
    _$hash = $jc(_$hash, sizeBytes.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ServerDownloadInfo')
          ..add('url', url)
          ..add('fileName', fileName)
          ..add('checksum', checksum)
          ..add('sizeBytes', sizeBytes))
        .toString();
  }
}

class ServerDownloadInfoBuilder
    implements Builder<ServerDownloadInfo, ServerDownloadInfoBuilder> {
  _$ServerDownloadInfo? _$v;

  String? _url;
  String? get url => _$this._url;
  set url(String? url) => _$this._url = url;

  String? _fileName;
  String? get fileName => _$this._fileName;
  set fileName(String? fileName) => _$this._fileName = fileName;

  String? _checksum;
  String? get checksum => _$this._checksum;
  set checksum(String? checksum) => _$this._checksum = checksum;

  int? _sizeBytes;
  int? get sizeBytes => _$this._sizeBytes;
  set sizeBytes(int? sizeBytes) => _$this._sizeBytes = sizeBytes;

  ServerDownloadInfoBuilder() {
    ServerDownloadInfo._defaults(this);
  }

  ServerDownloadInfoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _url = $v.url;
      _fileName = $v.fileName;
      _checksum = $v.checksum;
      _sizeBytes = $v.sizeBytes;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ServerDownloadInfo other) {
    _$v = other as _$ServerDownloadInfo;
  }

  @override
  void update(void Function(ServerDownloadInfoBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ServerDownloadInfo build() => _build();

  _$ServerDownloadInfo _build() {
    final _$result = _$v ??
        _$ServerDownloadInfo._(
          url: BuiltValueNullFieldError.checkNotNull(
              url, r'ServerDownloadInfo', 'url'),
          fileName: BuiltValueNullFieldError.checkNotNull(
              fileName, r'ServerDownloadInfo', 'fileName'),
          checksum: checksum,
          sizeBytes: sizeBytes,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
