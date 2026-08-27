// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_login_challenge.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$LocalLoginChallenge extends LocalLoginChallenge {
  @override
  final String challenge;
  @override
  final DateTime expiresAt;

  factory _$LocalLoginChallenge(
          [void Function(LocalLoginChallengeBuilder)? updates]) =>
      (LocalLoginChallengeBuilder()..update(updates))._build();

  _$LocalLoginChallenge._({required this.challenge, required this.expiresAt})
      : super._();
  @override
  LocalLoginChallenge rebuild(
          void Function(LocalLoginChallengeBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  LocalLoginChallengeBuilder toBuilder() =>
      LocalLoginChallengeBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is LocalLoginChallenge &&
        challenge == other.challenge &&
        expiresAt == other.expiresAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, challenge.hashCode);
    _$hash = $jc(_$hash, expiresAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'LocalLoginChallenge')
          ..add('challenge', challenge)
          ..add('expiresAt', expiresAt))
        .toString();
  }
}

class LocalLoginChallengeBuilder
    implements Builder<LocalLoginChallenge, LocalLoginChallengeBuilder> {
  _$LocalLoginChallenge? _$v;

  String? _challenge;
  String? get challenge => _$this._challenge;
  set challenge(String? challenge) => _$this._challenge = challenge;

  DateTime? _expiresAt;
  DateTime? get expiresAt => _$this._expiresAt;
  set expiresAt(DateTime? expiresAt) => _$this._expiresAt = expiresAt;

  LocalLoginChallengeBuilder() {
    LocalLoginChallenge._defaults(this);
  }

  LocalLoginChallengeBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _challenge = $v.challenge;
      _expiresAt = $v.expiresAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(LocalLoginChallenge other) {
    _$v = other as _$LocalLoginChallenge;
  }

  @override
  void update(void Function(LocalLoginChallengeBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  LocalLoginChallenge build() => _build();

  _$LocalLoginChallenge _build() {
    final _$result = _$v ??
        _$LocalLoginChallenge._(
          challenge: BuiltValueNullFieldError.checkNotNull(
              challenge, r'LocalLoginChallenge', 'challenge'),
          expiresAt: BuiltValueNullFieldError.checkNotNull(
              expiresAt, r'LocalLoginChallenge', 'expiresAt'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
