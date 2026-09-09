// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rename_device_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RenameDeviceRequest extends RenameDeviceRequest {
  @override
  final String name;

  factory _$RenameDeviceRequest(
          [void Function(RenameDeviceRequestBuilder)? updates]) =>
      (RenameDeviceRequestBuilder()..update(updates))._build();

  _$RenameDeviceRequest._({required this.name}) : super._();
  @override
  RenameDeviceRequest rebuild(
          void Function(RenameDeviceRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RenameDeviceRequestBuilder toBuilder() =>
      RenameDeviceRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RenameDeviceRequest && name == other.name;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RenameDeviceRequest')
          ..add('name', name))
        .toString();
  }
}

class RenameDeviceRequestBuilder
    implements Builder<RenameDeviceRequest, RenameDeviceRequestBuilder> {
  _$RenameDeviceRequest? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  RenameDeviceRequestBuilder() {
    RenameDeviceRequest._defaults(this);
  }

  RenameDeviceRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RenameDeviceRequest other) {
    _$v = other as _$RenameDeviceRequest;
  }

  @override
  void update(void Function(RenameDeviceRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RenameDeviceRequest build() => _build();

  _$RenameDeviceRequest _build() {
    final _$result = _$v ??
        _$RenameDeviceRequest._(
          name: BuiltValueNullFieldError.checkNotNull(
              name, r'RenameDeviceRequest', 'name'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
