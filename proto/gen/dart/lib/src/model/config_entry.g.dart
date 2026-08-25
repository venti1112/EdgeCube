// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'config_entry.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ConfigEntry extends ConfigEntry {
  @override
  final String key;
  @override
  final BuiltMap<String, JsonObject?> value;

  factory _$ConfigEntry([void Function(ConfigEntryBuilder)? updates]) =>
      (ConfigEntryBuilder()..update(updates))._build();

  _$ConfigEntry._({required this.key, required this.value}) : super._();
  @override
  ConfigEntry rebuild(void Function(ConfigEntryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ConfigEntryBuilder toBuilder() => ConfigEntryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ConfigEntry && key == other.key && value == other.value;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, key.hashCode);
    _$hash = $jc(_$hash, value.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ConfigEntry')
          ..add('key', key)
          ..add('value', value))
        .toString();
  }
}

class ConfigEntryBuilder implements Builder<ConfigEntry, ConfigEntryBuilder> {
  _$ConfigEntry? _$v;

  String? _key;
  String? get key => _$this._key;
  set key(String? key) => _$this._key = key;

  MapBuilder<String, JsonObject?>? _value;
  MapBuilder<String, JsonObject?> get value =>
      _$this._value ??= MapBuilder<String, JsonObject?>();
  set value(MapBuilder<String, JsonObject?>? value) => _$this._value = value;

  ConfigEntryBuilder() {
    ConfigEntry._defaults(this);
  }

  ConfigEntryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _key = $v.key;
      _value = $v.value.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ConfigEntry other) {
    _$v = other as _$ConfigEntry;
  }

  @override
  void update(void Function(ConfigEntryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ConfigEntry build() => _build();

  _$ConfigEntry _build() {
    _$ConfigEntry _$result;
    try {
      _$result = _$v ??
          _$ConfigEntry._(
            key: BuiltValueNullFieldError.checkNotNull(
                key, r'ConfigEntry', 'key'),
            value: value.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'value';
        value.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ConfigEntry', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
