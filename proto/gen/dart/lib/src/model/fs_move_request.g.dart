// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fs_move_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$FsMoveRequest extends FsMoveRequest {
  @override
  final String instanceId;
  @override
  final String from;
  @override
  final String to;

  factory _$FsMoveRequest([void Function(FsMoveRequestBuilder)? updates]) =>
      (FsMoveRequestBuilder()..update(updates))._build();

  _$FsMoveRequest._(
      {required this.instanceId, required this.from, required this.to})
      : super._();
  @override
  FsMoveRequest rebuild(void Function(FsMoveRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  FsMoveRequestBuilder toBuilder() => FsMoveRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is FsMoveRequest &&
        instanceId == other.instanceId &&
        from == other.from &&
        to == other.to;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, instanceId.hashCode);
    _$hash = $jc(_$hash, from.hashCode);
    _$hash = $jc(_$hash, to.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'FsMoveRequest')
          ..add('instanceId', instanceId)
          ..add('from', from)
          ..add('to', to))
        .toString();
  }
}

class FsMoveRequestBuilder
    implements Builder<FsMoveRequest, FsMoveRequestBuilder> {
  _$FsMoveRequest? _$v;

  String? _instanceId;
  String? get instanceId => _$this._instanceId;
  set instanceId(String? instanceId) => _$this._instanceId = instanceId;

  String? _from;
  String? get from => _$this._from;
  set from(String? from) => _$this._from = from;

  String? _to;
  String? get to => _$this._to;
  set to(String? to) => _$this._to = to;

  FsMoveRequestBuilder() {
    FsMoveRequest._defaults(this);
  }

  FsMoveRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _instanceId = $v.instanceId;
      _from = $v.from;
      _to = $v.to;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(FsMoveRequest other) {
    _$v = other as _$FsMoveRequest;
  }

  @override
  void update(void Function(FsMoveRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  FsMoveRequest build() => _build();

  _$FsMoveRequest _build() {
    final _$result = _$v ??
        _$FsMoveRequest._(
          instanceId: BuiltValueNullFieldError.checkNotNull(
              instanceId, r'FsMoveRequest', 'instanceId'),
          from: BuiltValueNullFieldError.checkNotNull(
              from, r'FsMoveRequest', 'from'),
          to: BuiltValueNullFieldError.checkNotNull(to, r'FsMoveRequest', 'to'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
