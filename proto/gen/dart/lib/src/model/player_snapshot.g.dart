// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'player_snapshot.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PlayerSnapshot extends PlayerSnapshot {
  @override
  final InstanceStatus instanceStatus;
  @override
  final BuiltList<String> online;
  @override
  final BuiltList<PlayerNamedEntry> whitelist;
  @override
  final BuiltList<PlayerNamedEntry> ops;
  @override
  final BuiltList<PlayerBanEntry> bans;
  @override
  final BuiltList<PlayerIpBanEntry> banIps;

  factory _$PlayerSnapshot([void Function(PlayerSnapshotBuilder)? updates]) =>
      (PlayerSnapshotBuilder()..update(updates))._build();

  _$PlayerSnapshot._(
      {required this.instanceStatus,
      required this.online,
      required this.whitelist,
      required this.ops,
      required this.bans,
      required this.banIps})
      : super._();
  @override
  PlayerSnapshot rebuild(void Function(PlayerSnapshotBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PlayerSnapshotBuilder toBuilder() => PlayerSnapshotBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlayerSnapshot &&
        instanceStatus == other.instanceStatus &&
        online == other.online &&
        whitelist == other.whitelist &&
        ops == other.ops &&
        bans == other.bans &&
        banIps == other.banIps;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, instanceStatus.hashCode);
    _$hash = $jc(_$hash, online.hashCode);
    _$hash = $jc(_$hash, whitelist.hashCode);
    _$hash = $jc(_$hash, ops.hashCode);
    _$hash = $jc(_$hash, bans.hashCode);
    _$hash = $jc(_$hash, banIps.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PlayerSnapshot')
          ..add('instanceStatus', instanceStatus)
          ..add('online', online)
          ..add('whitelist', whitelist)
          ..add('ops', ops)
          ..add('bans', bans)
          ..add('banIps', banIps))
        .toString();
  }
}

class PlayerSnapshotBuilder
    implements Builder<PlayerSnapshot, PlayerSnapshotBuilder> {
  _$PlayerSnapshot? _$v;

  InstanceStatus? _instanceStatus;
  InstanceStatus? get instanceStatus => _$this._instanceStatus;
  set instanceStatus(InstanceStatus? instanceStatus) =>
      _$this._instanceStatus = instanceStatus;

  ListBuilder<String>? _online;
  ListBuilder<String> get online => _$this._online ??= ListBuilder<String>();
  set online(ListBuilder<String>? online) => _$this._online = online;

  ListBuilder<PlayerNamedEntry>? _whitelist;
  ListBuilder<PlayerNamedEntry> get whitelist =>
      _$this._whitelist ??= ListBuilder<PlayerNamedEntry>();
  set whitelist(ListBuilder<PlayerNamedEntry>? whitelist) =>
      _$this._whitelist = whitelist;

  ListBuilder<PlayerNamedEntry>? _ops;
  ListBuilder<PlayerNamedEntry> get ops =>
      _$this._ops ??= ListBuilder<PlayerNamedEntry>();
  set ops(ListBuilder<PlayerNamedEntry>? ops) => _$this._ops = ops;

  ListBuilder<PlayerBanEntry>? _bans;
  ListBuilder<PlayerBanEntry> get bans =>
      _$this._bans ??= ListBuilder<PlayerBanEntry>();
  set bans(ListBuilder<PlayerBanEntry>? bans) => _$this._bans = bans;

  ListBuilder<PlayerIpBanEntry>? _banIps;
  ListBuilder<PlayerIpBanEntry> get banIps =>
      _$this._banIps ??= ListBuilder<PlayerIpBanEntry>();
  set banIps(ListBuilder<PlayerIpBanEntry>? banIps) => _$this._banIps = banIps;

  PlayerSnapshotBuilder() {
    PlayerSnapshot._defaults(this);
  }

  PlayerSnapshotBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _instanceStatus = $v.instanceStatus;
      _online = $v.online.toBuilder();
      _whitelist = $v.whitelist.toBuilder();
      _ops = $v.ops.toBuilder();
      _bans = $v.bans.toBuilder();
      _banIps = $v.banIps.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlayerSnapshot other) {
    _$v = other as _$PlayerSnapshot;
  }

  @override
  void update(void Function(PlayerSnapshotBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlayerSnapshot build() => _build();

  _$PlayerSnapshot _build() {
    _$PlayerSnapshot _$result;
    try {
      _$result = _$v ??
          _$PlayerSnapshot._(
            instanceStatus: BuiltValueNullFieldError.checkNotNull(
                instanceStatus, r'PlayerSnapshot', 'instanceStatus'),
            online: online.build(),
            whitelist: whitelist.build(),
            ops: ops.build(),
            bans: bans.build(),
            banIps: banIps.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'online';
        online.build();
        _$failedField = 'whitelist';
        whitelist.build();
        _$failedField = 'ops';
        ops.build();
        _$failedField = 'bans';
        bans.build();
        _$failedField = 'banIps';
        banIps.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'PlayerSnapshot', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
