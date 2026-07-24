import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'frp_provider.dart';

/// FRP 供应商登录 token 的加密存储（Android Keystore）。
///
/// 与 config/ 下的明文 JSON 分离：注册表只存非机密元数据，token 一律走
/// 本存储。key 形如 `frp_token_openfrp`。
class FrpTokenStore {
  FrpTokenStore._();

  static const _storage = FlutterSecureStorage();

  static String _key(FrpProvider provider) => 'frp_token_${provider.key}';

  static Future<String?> readToken(FrpProvider provider) =>
      _storage.read(key: _key(provider));

  static Future<void> saveToken(FrpProvider provider, String token) =>
      _storage.write(key: _key(provider), value: token);

  static Future<void> deleteToken(FrpProvider provider) =>
      _storage.delete(key: _key(provider));
}
