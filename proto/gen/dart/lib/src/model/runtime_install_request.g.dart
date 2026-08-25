// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'runtime_install_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RuntimeInstallRequest extends RuntimeInstallRequest {
  @override
  final RuntimeType type;
  @override
  final String? version;
  @override
  final String? arch;
  @override
  final String? url;

  factory _$RuntimeInstallRequest(
          [void Function(RuntimeInstallRequestBuilder)? updates]) =>
      (RuntimeInstallRequestBuilder()..update(updates))._build();

  _$RuntimeInstallRequest._(
      {required this.type, this.version, this.arch, this.url})
      : super._();
  @override
  RuntimeInstallRequest rebuild(
          void Function(RuntimeInstallRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RuntimeInstallRequestBuilder toBuilder() =>
      RuntimeInstallRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RuntimeInstallRequest &&
        type == other.type &&
        version == other.version &&
        arch == other.arch &&
        url == other.url;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, type.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jc(_$hash, arch.hashCode);
    _$hash = $jc(_$hash, url.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RuntimeInstallRequest')
          ..add('type', type)
          ..add('version', version)
          ..add('arch', arch)
          ..add('url', url))
        .toString();
  }
}

class RuntimeInstallRequestBuilder
    implements Builder<RuntimeInstallRequest, RuntimeInstallRequestBuilder> {
  _$RuntimeInstallRequest? _$v;

  RuntimeType? _type;
  RuntimeType? get type => _$this._type;
  set type(RuntimeType? type) => _$this._type = type;

  String? _version;
  String? get version => _$this._version;
  set version(String? version) => _$this._version = version;

  String? _arch;
  String? get arch => _$this._arch;
  set arch(String? arch) => _$this._arch = arch;

  String? _url;
  String? get url => _$this._url;
  set url(String? url) => _$this._url = url;

  RuntimeInstallRequestBuilder() {
    RuntimeInstallRequest._defaults(this);
  }

  RuntimeInstallRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _type = $v.type;
      _version = $v.version;
      _arch = $v.arch;
      _url = $v.url;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RuntimeInstallRequest other) {
    _$v = other as _$RuntimeInstallRequest;
  }

  @override
  void update(void Function(RuntimeInstallRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RuntimeInstallRequest build() => _build();

  _$RuntimeInstallRequest _build() {
    final _$result = _$v ??
        _$RuntimeInstallRequest._(
          type: BuiltValueNullFieldError.checkNotNull(
              type, r'RuntimeInstallRequest', 'type'),
          version: version,
          arch: arch,
          url: url,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
