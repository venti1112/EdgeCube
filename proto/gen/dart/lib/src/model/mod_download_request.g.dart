// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mod_download_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ModDownloadRequest extends ModDownloadRequest {
  @override
  final String url;
  @override
  final String destPath;
  @override
  final String? fileName;
  @override
  final String? displayName;
  @override
  final String? replacePath;

  factory _$ModDownloadRequest(
          [void Function(ModDownloadRequestBuilder)? updates]) =>
      (ModDownloadRequestBuilder()..update(updates))._build();

  _$ModDownloadRequest._(
      {required this.url,
      required this.destPath,
      this.fileName,
      this.displayName,
      this.replacePath})
      : super._();
  @override
  ModDownloadRequest rebuild(
          void Function(ModDownloadRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ModDownloadRequestBuilder toBuilder() =>
      ModDownloadRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ModDownloadRequest &&
        url == other.url &&
        destPath == other.destPath &&
        fileName == other.fileName &&
        displayName == other.displayName &&
        replacePath == other.replacePath;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, url.hashCode);
    _$hash = $jc(_$hash, destPath.hashCode);
    _$hash = $jc(_$hash, fileName.hashCode);
    _$hash = $jc(_$hash, displayName.hashCode);
    _$hash = $jc(_$hash, replacePath.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ModDownloadRequest')
          ..add('url', url)
          ..add('destPath', destPath)
          ..add('fileName', fileName)
          ..add('displayName', displayName)
          ..add('replacePath', replacePath))
        .toString();
  }
}

class ModDownloadRequestBuilder
    implements Builder<ModDownloadRequest, ModDownloadRequestBuilder> {
  _$ModDownloadRequest? _$v;

  String? _url;
  String? get url => _$this._url;
  set url(String? url) => _$this._url = url;

  String? _destPath;
  String? get destPath => _$this._destPath;
  set destPath(String? destPath) => _$this._destPath = destPath;

  String? _fileName;
  String? get fileName => _$this._fileName;
  set fileName(String? fileName) => _$this._fileName = fileName;

  String? _displayName;
  String? get displayName => _$this._displayName;
  set displayName(String? displayName) => _$this._displayName = displayName;

  String? _replacePath;
  String? get replacePath => _$this._replacePath;
  set replacePath(String? replacePath) => _$this._replacePath = replacePath;

  ModDownloadRequestBuilder() {
    ModDownloadRequest._defaults(this);
  }

  ModDownloadRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _url = $v.url;
      _destPath = $v.destPath;
      _fileName = $v.fileName;
      _displayName = $v.displayName;
      _replacePath = $v.replacePath;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ModDownloadRequest other) {
    _$v = other as _$ModDownloadRequest;
  }

  @override
  void update(void Function(ModDownloadRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ModDownloadRequest build() => _build();

  _$ModDownloadRequest _build() {
    final _$result = _$v ??
        _$ModDownloadRequest._(
          url: BuiltValueNullFieldError.checkNotNull(
              url, r'ModDownloadRequest', 'url'),
          destPath: BuiltValueNullFieldError.checkNotNull(
              destPath, r'ModDownloadRequest', 'destPath'),
          fileName: fileName,
          displayName: displayName,
          replacePath: replacePath,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
