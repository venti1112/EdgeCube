/// FRP 映射隧道供应商。
///
/// 从 MSL 开服器移植：每家供应商有独立的 API、认证方式与配置获取策略。
/// EdgeCube 统一用上游原版 frpc（运行时包）+ 标准配置文件运行所有供应商的
/// 隧道（MSL 中 OpenFrp/Sakura/MEFrp 走各家魔改客户端的命令行参数启动，
/// 这里改为由 API 数据拼装标准配置，见 FrpConfigBuilder）。
enum FrpProvider {
  mslFrp('mslfrp', 'MSL Frp'),
  openFrp('openfrp', 'OpenFrp'),
  sakuraFrp('sakurafrp', 'Sakura Frp'),
  chmlFrp('chmlfrp', 'ChmlFrp'),
  meFrp('mefrp', 'ME Frp'),
  custom('custom', '');

  const FrpProvider(this.key, this.displayName);

  /// 持久化用的稳定标识。
  final String key;

  /// 展示名（custom 用 i18n 文案，此处留空）。
  final String displayName;

  static FrpProvider fromKey(String? key) => values.firstWhere(
        (p) => p.key == key,
        orElse: () => FrpProvider.custom,
      );

  /// 该供应商是否需要账号登录（custom 不需要）。
  bool get requiresLogin => this != FrpProvider.custom;

  /// 是否支持浏览器授权登录（OAuth）。MSL 已下线密码登录，改走浏览器授权；
  /// OpenFrp 已下线 Authorization 粘贴登录，改走远程安全登录（curve25519）；
  /// ChmlFrp 改走 QZhua 账号 OAuth 设备码授权。
  /// SakuraFrp / ME Frp 保留令牌粘贴登录。
  bool get supportsBrowserLogin =>
      this == FrpProvider.mslFrp ||
      this == FrpProvider.openFrp ||
      this == FrpProvider.chmlFrp;

  /// 标准 frpc 兼容性存疑的供应商（闭源魔改 frps，可能要求私有握手）。
  /// UI 在这些供应商的入口展示「实验性」提示，运行失败时引导查看日志。
  bool get experimental =>
      this == FrpProvider.sakuraFrp || this == FrpProvider.meFrp;
}
