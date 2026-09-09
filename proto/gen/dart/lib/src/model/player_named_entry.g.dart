// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'player_named_entry.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PlayerNamedEntry extends PlayerNamedEntry {
  @override
  final String name;
  @override
  final String? uuid;

  factory _$PlayerNamedEntry(
          [void Function(PlayerNamedEntryBuilder)? updates]) =>
      (PlayerNamedEntryBuilder()..update(updates))._build();

  _$PlayerNamedEntry._({required this.name, this.uuid}) : super._();
  @override
  PlayerNamedEntry rebuild(void Function(PlayerNamedEntryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PlayerNamedEntryBuilder toBuilder() =>
      PlayerNamedEntryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlayerNamedEntry &&
        name == other.name &&
        uuid == other.uuid;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, uuid.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PlayerNamedEntry')
          ..add('name', name)
          ..add('uuid', uuid))
        .toString();
  }
}

class PlayerNamedEntryBuilder
    implements Builder<PlayerNamedEntry, PlayerNamedEntryBuilder> {
  _$PlayerNamedEntry? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _uuid;
  String? get uuid => _$this._uuid;
  set uuid(String? uuid) => _$this._uuid = uuid;

  PlayerNamedEntryBuilder() {
    PlayerNamedEntry._defaults(this);
  }

  PlayerNamedEntryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _uuid = $v.uuid;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlayerNamedEntry other) {
    _$v = other as _$PlayerNamedEntry;
  }

  @override
  void update(void Function(PlayerNamedEntryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlayerNamedEntry build() => _build();

  _$PlayerNamedEntry _build() {
    final _$result = _$v ??
        _$PlayerNamedEntry._(
          name: BuiltValueNullFieldError.checkNotNull(
              name, r'PlayerNamedEntry', 'name'),
          uuid: uuid,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
