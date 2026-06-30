import 'config_store.dart';

/// 用户协议同意状态的本地持久化，存于 `config/user_agreement.json`。
///
/// 记录用户是否同意过用户协议以及同意时的协议版本号。协议正文更新后递增
/// [currentVersion]，启动时会据此判断是否需要再次询问。
class UserAgreementStore {
  UserAgreementStore._();

  static const String _fileName = 'user_agreement.json';
  static const String _agreedKey = 'agreed';
  static const String _versionKey = 'version';

  /// 当前用户协议版本号。修改协议正文后递增此值以触发用户重新同意。
  static const int currentVersion = 1;

  /// 加载持久化的同意状态：
  /// - 返回 `null` 表示从未同意；
  /// - 返回 `int` 表示已同意的协议版本号（可能与 [currentVersion] 不同）。
  static Future<int?> loadAgreedVersion() async {
    final configMap = await ConfigStore.readConfig(_fileName);
    final agreed = configMap[_agreedKey] as bool? ?? false;
    if (!agreed) return null;
    return configMap[_versionKey] as int? ?? 1;
  }

  /// 标记用户已同意当前版本的用户协议。
  static Future<void> saveAgreed() async {
    final configMap = await ConfigStore.readConfig(_fileName);
    configMap[_agreedKey] = true;
    configMap[_versionKey] = currentVersion;
    await ConfigStore.writeConfig(_fileName, configMap);
  }
}
