// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'player_ip_ban_entry.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PlayerIpBanEntry extends PlayerIpBanEntry {
  @override
  final String ip;
  @override
  final String? reason;
  @override
  final String? source_;
  @override
  final String? expires;
  @override
  final String? created;

  factory _$PlayerIpBanEntry(
          [void Function(PlayerIpBanEntryBuilder)? updates]) =>
      (PlayerIpBanEntryBuilder()..update(updates))._build();

  _$PlayerIpBanEntry._(
      {required this.ip, this.reason, this.source_, this.expires, this.created})
      : super._();
  @override
  PlayerIpBanEntry rebuild(void Function(PlayerIpBanEntryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PlayerIpBanEntryBuilder toBuilder() =>
      PlayerIpBanEntryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlayerIpBanEntry &&
        ip == other.ip &&
        reason == other.reason &&
        source_ == other.source_ &&
        expires == other.expires &&
        created == other.created;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, ip.hashCode);
    _$hash = $jc(_$hash, reason.hashCode);
    _$hash = $jc(_$hash, source_.hashCode);
    _$hash = $jc(_$hash, expires.hashCode);
    _$hash = $jc(_$hash, created.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PlayerIpBanEntry')
          ..add('ip', ip)
          ..add('reason', reason)
          ..add('source_', source_)
          ..add('expires', expires)
          ..add('created', created))
        .toString();
  }
}

class PlayerIpBanEntryBuilder
    implements Builder<PlayerIpBanEntry, PlayerIpBanEntryBuilder> {
  _$PlayerIpBanEntry? _$v;

  String? _ip;
  String? get ip => _$this._ip;
  set ip(String? ip) => _$this._ip = ip;

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

  PlayerIpBanEntryBuilder() {
    PlayerIpBanEntry._defaults(this);
  }

  PlayerIpBanEntryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _ip = $v.ip;
      _reason = $v.reason;
      _source_ = $v.source_;
      _expires = $v.expires;
      _created = $v.created;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlayerIpBanEntry other) {
    _$v = other as _$PlayerIpBanEntry;
  }

  @override
  void update(void Function(PlayerIpBanEntryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlayerIpBanEntry build() => _build();

  _$PlayerIpBanEntry _build() {
    final _$result = _$v ??
        _$PlayerIpBanEntry._(
          ip: BuiltValueNullFieldError.checkNotNull(
              ip, r'PlayerIpBanEntry', 'ip'),
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
