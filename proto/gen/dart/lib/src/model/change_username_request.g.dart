// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'change_username_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ChangeUsernameRequest extends ChangeUsernameRequest {
  @override
  final String password;
  @override
  final String newUsername;

  factory _$ChangeUsernameRequest(
          [void Function(ChangeUsernameRequestBuilder)? updates]) =>
      (ChangeUsernameRequestBuilder()..update(updates))._build();

  _$ChangeUsernameRequest._({required this.password, required this.newUsername})
      : super._();
  @override
  ChangeUsernameRequest rebuild(
          void Function(ChangeUsernameRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ChangeUsernameRequestBuilder toBuilder() =>
      ChangeUsernameRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ChangeUsernameRequest &&
        password == other.password &&
        newUsername == other.newUsername;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, password.hashCode);
    _$hash = $jc(_$hash, newUsername.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ChangeUsernameRequest')
          ..add('password', password)
          ..add('newUsername', newUsername))
        .toString();
  }
}

class ChangeUsernameRequestBuilder
    implements Builder<ChangeUsernameRequest, ChangeUsernameRequestBuilder> {
  _$ChangeUsernameRequest? _$v;

  String? _password;
  String? get password => _$this._password;
  set password(String? password) => _$this._password = password;

  String? _newUsername;
  String? get newUsername => _$this._newUsername;
  set newUsername(String? newUsername) => _$this._newUsername = newUsername;

  ChangeUsernameRequestBuilder() {
    ChangeUsernameRequest._defaults(this);
  }

  ChangeUsernameRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _password = $v.password;
      _newUsername = $v.newUsername;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ChangeUsernameRequest other) {
    _$v = other as _$ChangeUsernameRequest;
  }

  @override
  void update(void Function(ChangeUsernameRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ChangeUsernameRequest build() => _build();

  _$ChangeUsernameRequest _build() {
    final _$result = _$v ??
        _$ChangeUsernameRequest._(
          password: BuiltValueNullFieldError.checkNotNull(
              password, r'ChangeUsernameRequest', 'password'),
          newUsername: BuiltValueNullFieldError.checkNotNull(
              newUsername, r'ChangeUsernameRequest', 'newUsername'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
