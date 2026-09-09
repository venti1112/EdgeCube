// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'task_list.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$TaskList extends TaskList {
  @override
  final BuiltList<Task> items;
  @override
  final int total;

  factory _$TaskList([void Function(TaskListBuilder)? updates]) =>
      (TaskListBuilder()..update(updates))._build();

  _$TaskList._({required this.items, required this.total}) : super._();
  @override
  TaskList rebuild(void Function(TaskListBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  TaskListBuilder toBuilder() => TaskListBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is TaskList && items == other.items && total == other.total;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, items.hashCode);
    _$hash = $jc(_$hash, total.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'TaskList')
          ..add('items', items)
          ..add('total', total))
        .toString();
  }
}

class TaskListBuilder implements Builder<TaskList, TaskListBuilder> {
  _$TaskList? _$v;

  ListBuilder<Task>? _items;
  ListBuilder<Task> get items => _$this._items ??= ListBuilder<Task>();
  set items(ListBuilder<Task>? items) => _$this._items = items;

  int? _total;
  int? get total => _$this._total;
  set total(int? total) => _$this._total = total;

  TaskListBuilder() {
    TaskList._defaults(this);
  }

  TaskListBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _items = $v.items.toBuilder();
      _total = $v.total;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(TaskList other) {
    _$v = other as _$TaskList;
  }

  @override
  void update(void Function(TaskListBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  TaskList build() => _build();

  _$TaskList _build() {
    _$TaskList _$result;
    try {
      _$result = _$v ??
          _$TaskList._(
            items: items.build(),
            total: BuiltValueNullFieldError.checkNotNull(
                total, r'TaskList', 'total'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'items';
        items.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'TaskList', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
