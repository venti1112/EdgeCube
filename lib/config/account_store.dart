import '../account/account_models.dart';
import 'config_store.dart';

/// 当前登录会话的本地持久化。
///
/// 会话（用户资料 + session_token + refresh_token + 设备信息）整体存于
/// `config/account.json`。设计上仅保存「一个」当前会话：登录 / 刷新时覆盖写入，
/// 登出或刷新失效时清空。令牌属敏感信息，但沿用应用既有的文件式配置存储
/// （与 FTP 密码、frpc 配置一致），不额外引入安全存储依赖。
class AccountStore {
  AccountStore._();

  static const String _fileName = 'account.json';

  /// 读取已保存的会话；无有效会话（文件缺失 / 损坏 / 无令牌）时返回 null。
  static Future<AuthSession?> load() async {
    final map = await ConfigStore.readConfig(_fileName);
    if (map.isEmpty) return null;
    final token = map['refresh_token'];
    // 至少需要 refresh_token 才能续期；否则视为无有效会话。
    if (token is! String || token.isEmpty) return null;
    try {
      return AuthSession.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  /// 保存 / 覆盖当前会话。
  static Future<void> save(AuthSession session) async {
    await ConfigStore.writeConfig(_fileName, session.toJson());
  }

  /// 清空当前会话（登出 / 会话失效时调用）。
  static Future<void> clear() async {
    await ConfigStore.writeConfig(_fileName, {});
  }
}
