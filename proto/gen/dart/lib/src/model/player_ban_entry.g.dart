// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'player_ban_entry.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PlayerBanEntry extends PlayerBanEntry {
  @override
  final String name;
  @override
  final String? uuid;
  @override
  final String? reason;
  @override
  final String? source_;
  @override
  final String? expires;
  @override
  final String? created;

  factory _$PlayerBanEntry([void Function(PlayerBanEntryBuilder)? updates]) =>
      (PlayerBanEntryBuilder()..update(updates))._build();

  _$PlayerBanEntry._(
      {required this.name,
      this.uuid,
      this.reason,
      this.source_,
      this.expires,
      this.created})
      : super._();
  @override
  PlayerBanEntry rebuild(void Function(PlayerBanEntryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PlayerBanEntryBuilder toBuilder() => PlayerBanEntryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlayerBanEntry &&
        name == other.name &&
        uuid == other.uuid &&
        reason == other.reason &&
        source_ == other.source_ &&
        expires == other.expires &&
        created == other.created;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, uuid.hashCode);
    _$hash = $jc(_$hash, reason.hashCode);
    _$hash = $jc(_$hash, source_.hashCode);
    _$hash = $jc(_$hash, expires.hashCode);
    _$hash = $jc(_$hash, created.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PlayerBanEntry')
          ..add('name', name)
          ..add('uuid', uuid)
          ..add('reason', reason)
          ..add('source_', source_)
          ..add('expires', expires)
          ..add('created', created))
        .toString();
  }
}

class PlayerBanEntryBuilder
    implements Builder<PlayerBanEntry, PlayerBanEntryBuilder> {
  _$PlayerBanEntry? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _uuid;
  String? get uuid => _$this._uuid;
  set uuid(String? uuid) => _$this._uuid = uuid;

  String? _reason;
  String? get reason => _$this._reason;
  set reason(String? reason) => _$this._reason = reason;

  String? _source_;
  String? get source_ => _$this._source_;
  set source_(String? source_) => _$this._source_ = source_;

  String? _expires;
  String? get expires => _$this._expires;
  set expires(String? expires) => _$this._expires = expires;

  String? _created;
  String? get created => _$this._created;
  set created(String? created) => _$this._created = created;

  PlayerBanEntryBuilder() {
    PlayerBanEntry._defaults(this);
  }

  PlayerBanEntryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _uuid = $v.uuid;
      _reason = $v.reason;
      _source_ = $v.source_;
      _expires = $v.expires;
      _created = $v.created;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlayerBanEntry other) {
    _$v = other as _$PlayerBanEntry;
  }

  @override
  void update(void Function(PlayerBanEntryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlayerBanEntry build() => _build();

  _$PlayerBanEntry _build() {
    final _$result = _$v ??
        _$PlayerBanEntry._(
          name: BuiltValueNullFieldError.checkNotNull(
              name, r'PlayerBanEntry', 'name'),
          uuid: uuid,
          reason: reason,
          source_: source_,
          expires: expires,
          created: created,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
