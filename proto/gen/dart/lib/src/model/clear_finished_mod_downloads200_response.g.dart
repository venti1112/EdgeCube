// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'clear_finished_mod_downloads200_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ClearFinishedModDownloads200Response
    extends ClearFinishedModDownloads200Response {
  @override
  final int? cleared;

  factory _$ClearFinishedModDownloads200Response(
          [void Function(ClearFinishedModDownloads200ResponseBuilder)?
              updates]) =>
      (ClearFinishedModDownloads200ResponseBuilder()..update(updates))._build();

  _$ClearFinishedModDownloads200Response._({this.cleared}) : super._();
  @override
  ClearFinishedModDownloads200Response rebuild(
          void Function(ClearFinishedModDownloads200ResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ClearFinishedModDownloads200ResponseBuilder toBuilder() =>
      ClearFinishedModDownloads200ResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ClearFinishedModDownloads200Response &&
        cleared == other.cleared;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, cleared.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ClearFinishedModDownloads200Response')
          ..add('cleared', cleared))
        .toString();
  }
}

class ClearFinishedModDownloads200ResponseBuilder
    implements
        Builder<ClearFinishedModDownloads200Response,
            ClearFinishedModDownloads200ResponseBuilder> {
  _$ClearFinishedModDownloads200Response? _$v;

  int? _cleared;
  int? get cleared => _$this._cleared;
  set cleared(int? cleared) => _$this._cleared = cleared;

  ClearFinishedModDownloads200ResponseBuilder() {
    ClearFinishedModDownloads200Response._defaults(this);
  }

  ClearFinishedModDownloads200ResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _cleared = $v.cleared;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ClearFinishedModDownloads200Response other) {
    _$v = other as _$ClearFinishedModDownloads200Response;
  }

  @override
  void update(
      void Function(ClearFinishedModDownloads200ResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ClearFinishedModDownloads200Response build() => _build();

  _$ClearFinishedModDownloads200Response _build() {
    final _$result = _$v ??
        _$ClearFinishedModDownloads200Response._(
          cleared: cleared,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
