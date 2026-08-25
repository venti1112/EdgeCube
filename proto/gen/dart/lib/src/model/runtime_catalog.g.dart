// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'runtime_catalog.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RuntimeCatalog extends RuntimeCatalog {
  @override
  final RuntimeType type;
  @override
  final BuiltList<RuntimeCatalogEntry> entries;

  factory _$RuntimeCatalog([void Function(RuntimeCatalogBuilder)? updates]) =>
      (RuntimeCatalogBuilder()..update(updates))._build();

  _$RuntimeCatalog._({required this.type, required this.entries}) : super._();
  @override
  RuntimeCatalog rebuild(void Function(RuntimeCatalogBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RuntimeCatalogBuilder toBuilder() => RuntimeCatalogBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RuntimeCatalog &&
        type == other.type &&
        entries == other.entries;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, type.hashCode);
    _$hash = $jc(_$hash, entries.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RuntimeCatalog')
          ..add('type', type)
          ..add('entries', entries))
        .toString();
  }
}

class RuntimeCatalogBuilder
    implements Builder<RuntimeCatalog, RuntimeCatalogBuilder> {
  _$RuntimeCatalog? _$v;

  RuntimeType? _type;
  RuntimeType? get type => _$this._type;
  set type(RuntimeType? type) => _$this._type = type;

  ListBuilder<RuntimeCatalogEntry>? _entries;
  ListBuilder<RuntimeCatalogEntry> get entries =>
      _$this._entries ??= ListBuilder<RuntimeCatalogEntry>();
  set entries(ListBuilder<RuntimeCatalogEntry>? entries) =>
      _$this._entries = entries;

  RuntimeCatalogBuilder() {
    RuntimeCatalog._defaults(this);
  }

  RuntimeCatalogBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _type = $v.type;
      _entries = $v.entries.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RuntimeCatalog other) {
    _$v = other as _$RuntimeCatalog;
  }

  @override
  void update(void Function(RuntimeCatalogBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RuntimeCatalog build() => _build();

  _$RuntimeCatalog _build() {
    _$RuntimeCatalog _$result;
    try {
      _$result = _$v ??
          _$RuntimeCatalog._(
            type: BuiltValueNullFieldError.checkNotNull(
                type, r'RuntimeCatalog', 'type'),
            entries: entries.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'entries';
        entries.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'RuntimeCatalog', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
