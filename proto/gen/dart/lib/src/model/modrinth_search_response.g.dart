// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'modrinth_search_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ModrinthSearchResponse extends ModrinthSearchResponse {
  @override
  final BuiltList<ModrinthSearchHit> hits;
  @override
  final int offset;
  @override
  final int limit;
  @override
  final int totalHits;

  factory _$ModrinthSearchResponse(
          [void Function(ModrinthSearchResponseBuilder)? updates]) =>
      (ModrinthSearchResponseBuilder()..update(updates))._build();

  _$ModrinthSearchResponse._(
      {required this.hits,
      required this.offset,
      required this.limit,
      required this.totalHits})
      : super._();
  @override
  ModrinthSearchResponse rebuild(
          void Function(ModrinthSearchResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ModrinthSearchResponseBuilder toBuilder() =>
      ModrinthSearchResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ModrinthSearchResponse &&
        hits == other.hits &&
        offset == other.offset &&
        limit == other.limit &&
        totalHits == other.totalHits;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, hits.hashCode);
    _$hash = $jc(_$hash, offset.hashCode);
    _$hash = $jc(_$hash, limit.hashCode);
    _$hash = $jc(_$hash, totalHits.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ModrinthSearchResponse')
          ..add('hits', hits)
          ..add('offset', offset)
          ..add('limit', limit)
          ..add('totalHits', totalHits))
        .toString();
  }
}

class ModrinthSearchResponseBuilder
    implements Builder<ModrinthSearchResponse, ModrinthSearchResponseBuilder> {
  _$ModrinthSearchResponse? _$v;

  ListBuilder<ModrinthSearchHit>? _hits;
  ListBuilder<ModrinthSearchHit> get hits =>
      _$this._hits ??= ListBuilder<ModrinthSearchHit>();
  set hits(ListBuilder<ModrinthSearchHit>? hits) => _$this._hits = hits;

  int? _offset;
  int? get offset => _$this._offset;
  set offset(int? offset) => _$this._offset = offset;

  int? _limit;
  int? get limit => _$this._limit;
  set limit(int? limit) => _$this._limit = limit;

  int? _totalHits;
  int? get totalHits => _$this._totalHits;
  set totalHits(int? totalHits) => _$this._totalHits = totalHits;

  ModrinthSearchResponseBuilder() {
    ModrinthSearchResponse._defaults(this);
  }

  ModrinthSearchResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _hits = $v.hits.toBuilder();
      _offset = $v.offset;
      _limit = $v.limit;
      _totalHits = $v.totalHits;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ModrinthSearchResponse other) {
    _$v = other as _$ModrinthSearchResponse;
  }

  @override
  void update(void Function(ModrinthSearchResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ModrinthSearchResponse build() => _build();

  _$ModrinthSearchResponse _build() {
    _$ModrinthSearchResponse _$result;
    try {
      _$result = _$v ??
          _$ModrinthSearchResponse._(
            hits: hits.build(),
            offset: BuiltValueNullFieldError.checkNotNull(
                offset, r'ModrinthSearchResponse', 'offset'),
            limit: BuiltValueNullFieldError.checkNotNull(
                limit, r'ModrinthSearchResponse', 'limit'),
            totalHits: BuiltValueNullFieldError.checkNotNull(
                totalHits, r'ModrinthSearchResponse', 'totalHits'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'hits';
        hits.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ModrinthSearchResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
