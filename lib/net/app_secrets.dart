/// 编译期注入的应用密钥。
///
/// 通过 `--dart-define=KEY=VALUE` 在构建时注入，`String.fromEnvironment`
/// 在编译期读取常量值（不会出现在源码中）。例如：
///
/// ```
/// flutter build apk --dart-define=CURSEFORGE_API_KEY=<your-key>
/// ```
///
/// 未注入时相应 `has*` 为 false，调用方据此隐藏对应平台。
class AppSecrets {
  AppSecrets._();

  /// CurseForge API Key。CurseForge 官方 API 取下载链接必须携带
  /// `X-API-KEY` 请求头。为空表示未注入——此时 CurseForge 平台不可用。
  static const String curseForgeApiKey = String.fromEnvironment(
    'CURSEFORGE_API_KEY',
  );

  /// 是否已注入 CurseForge API Key。
  static bool get hasCurseForgeKey => curseForgeApiKey.isNotEmpty;
}
