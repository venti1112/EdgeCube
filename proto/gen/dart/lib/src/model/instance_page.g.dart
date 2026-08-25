// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'instance_page.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$InstancePage extends InstancePage {
  @override
  final BuiltList<InstanceSummary> items;
  @override
  final int total;
  @override
  final int page;
  @override
  final int pageSize;

  factory _$InstancePage([void Function(InstancePageBuilder)? updates]) =>
      (InstancePageBuilder()..update(updates))._build();

  _$InstancePage._(
      {required this.items,
      required this.total,
      required this.page,
      required this.pageSize})
      : super._();
  @override
  InstancePage rebuild(void Function(InstancePageBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  InstancePageBuilder toBuilder() => InstancePageBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is InstancePage &&
        items == other.items &&
        total == other.total &&
        page == other.page &&
        pageSize == other.pageSize;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, items.hashCode);
    _$hash = $jc(_$hash, total.hashCode);
    _$hash = $jc(_$hash, page.hashCode);
    _$hash = $jc(_$hash, pageSize.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'InstancePage')
          ..add('items', items)
          ..add('total', total)
          ..add('page', page)
          ..add('pageSize', pageSize))
        .toString();
  }
}

class InstancePageBuilder
    implements Builder<InstancePage, InstancePageBuilder> {
  _$InstancePage? _$v;

  ListBuilder<InstanceSummary>? _items;
  ListBuilder<InstanceSummary> get items =>
      _$this._items ??= ListBuilder<InstanceSummary>();
  set items(ListBuilder<InstanceSummary>? items) => _$this._items = items;

  int? _total;
  int? get total => _$this._total;
  set total(int? total) => _$this._total = total;

  int? _page;
  int? get page => _$this._page;
  set page(int? page) => _$this._page = page;

  int? _pageSize;
  int? get pageSize => _$this._pageSize;
  set pageSize(int? pageSize) => _$this._pageSize = pageSize;

  InstancePageBuilder() {
    InstancePage._defaults(this);
  }

  InstancePageBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _items = $v.items.toBuilder();
      _total = $v.total;
      _page = $v.page;
      _pageSize = $v.pageSize;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(InstancePage other) {
    _$v = other as _$InstancePage;
  }

  @override
  void update(void Function(InstancePageBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  InstancePage build() => _build();

  _$InstancePage _build() {
    _$InstancePage _$result;
    try {
      _$result = _$v ??
          _$InstancePage._(
            items: items.build(),
            total: BuiltValueNullFieldError.checkNotNull(
                total, r'InstancePage', 'total'),
            page: BuiltValueNullFieldError.checkNotNull(
                page, r'InstancePage', 'page'),
            pageSize: BuiltValueNullFieldError.checkNotNull(
                pageSize, r'InstancePage', 'pageSize'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'items';
        items.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'InstancePage', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
