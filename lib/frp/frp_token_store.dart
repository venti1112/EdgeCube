import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'frp_provider.dart';

/// FRP 供应商登录 token 的加密存储（Android Keystore）。
///
/// 与 config/ 下的明文 JSON 分离：注册表只存非机密元数据，token 一律走
/// 本存储。key 形如 `frp_token_openfrp`。同时缓存账号信息（account JSON），
/// 使得已登录用户再次进入时可直接跳转操作页，无需等待网络验证。
class FrpTokenStore {
  FrpTokenStore._();

  static const _storage = FlutterSecureStorage();

  static String _key(FrpProvider provider) => 'frp_token_${provider.key}';
  static String _accountKey(FrpProvider provider) =>
      'frp_account_${provider.key}';

  static Future<String?> readToken(FrpProvider provider) =>
      _storage.read(key: _key(provider));

  static Future<void> saveToken(FrpProvider provider, String token) =>
      _storage.write(key: _key(provider), value: token);

  static Future<void> deleteToken(FrpProvider provider) async {
    await _storage.delete(key: _key(provider));
    await _storage.delete(key: _accountKey(provider));
  }

  /// 读取缓存的账号信息 JSON；无则返回 null。
  static Future<String?> readAccount(FrpProvider provider) =>
      _storage.read(key: _accountKey(provider));

  /// 缓存账号信息 JSON。
  static Future<void> saveAccount(
    FrpProvider provider,
    Map<String, dynamic> json,
  ) =>
      _storage.write(key: _accountKey(provider), value: jsonEncode(json));
}
