// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'instance_overview.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$InstanceOverview extends InstanceOverview {
  @override
  final BuiltList<InstanceSummary> items;
  @override
  final int running;
  @override
  final int total;

  factory _$InstanceOverview(
          [void Function(InstanceOverviewBuilder)? updates]) =>
      (InstanceOverviewBuilder()..update(updates))._build();

  _$InstanceOverview._(
      {required this.items, required this.running, required this.total})
      : super._();
  @override
  InstanceOverview rebuild(void Function(InstanceOverviewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  InstanceOverviewBuilder toBuilder() =>
      InstanceOverviewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is InstanceOverview &&
        items == other.items &&
        running == other.running &&
        total == other.total;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, items.hashCode);
    _$hash = $jc(_$hash, running.hashCode);
    _$hash = $jc(_$hash, total.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'InstanceOverview')
          ..add('items', items)
          ..add('running', running)
          ..add('total', total))
        .toString();
  }
}

class InstanceOverviewBuilder
    implements Builder<InstanceOverview, InstanceOverviewBuilder> {
  _$InstanceOverview? _$v;

  ListBuilder<InstanceSummary>? _items;
  ListBuilder<InstanceSummary> get items =>
      _$this._items ??= ListBuilder<InstanceSummary>();
  set items(ListBuilder<InstanceSummary>? items) => _$this._items = items;

  int? _running;
  int? get running => _$this._running;
  set running(int? running) => _$this._running = running;

  int? _total;
  int? get total => _$this._total;
  set total(int? total) => _$this._total = total;

  InstanceOverviewBuilder() {
    InstanceOverview._defaults(this);
  }

  InstanceOverviewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _items = $v.items.toBuilder();
      _running = $v.running;
      _total = $v.total;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(InstanceOverview other) {
    _$v = other as _$InstanceOverview;
  }

  @override
  void update(void Function(InstanceOverviewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  InstanceOverview build() => _build();

  _$InstanceOverview _build() {
    _$InstanceOverview _$result;
    try {
      _$result = _$v ??
          _$InstanceOverview._(
            items: items.build(),
            running: BuiltValueNullFieldError.checkNotNull(
                running, r'InstanceOverview', 'running'),
            total: BuiltValueNullFieldError.checkNotNull(
                total, r'InstanceOverview', 'total'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'items';
        items.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'InstanceOverview', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
