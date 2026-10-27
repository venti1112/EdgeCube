/// FRP 映射隧道的领域模型。
///
/// 形状与 daemon 的 `frp.*` 方法返回值一一对应（snake_case 线上格式）；
/// 有两处刻意的处理：
///
/// * **令牌不在前端**：`frp_token` 拼配置用，daemon 不下发（见 daemon 侧
///   `Account::public_json`）；
/// * **没有本地注册表读写**：隧道的增删存一律走 `frp.tunnels.*` RPC，
///   文件在 daemon 那台机器上。
library;

import '../connection/client.dart';

/// 宽松取字符串（缺失 / null → 空串）。
String _str(Object? value) => switch (value) {
  null => '',
  String() => value,
  _ => '$value',
};

/// 宽松取整数（数字、数字字符串都收）。
int? _int(Object? value) => switch (value) {
  int() => value,
  num() => value.toInt(),
  String() => int.tryParse(value.trim()),
  _ => null,
};

bool _bool(Object? value, {bool orElse = false}) => switch (value) {
  bool() => value,
  num() => value != 0,
  String() => const {
    'true',
    '1',
    'yes',
    'on',
  }.contains(value.trim().toLowerCase()),
  _ => orElse,
};

Map<String, dynamic>? _map(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : null;

/// 平台展示副标题。
const _providerSubtitles = <String, String>{
  'mslfrp': 'MSL 开服器官方映射服务',
  'openfrp': 'OpenFrp 免费内网穿透',
  'sakurafrp': '樱花内网穿透',
  'chmlfrp': 'ChmlFrp 免费内网穿透',
  'mefrp': 'ME Frp 镜缘映射',
  'custom': '手动填写或粘贴 frpc 配置，连接任意 frps 服务器',
};

/// 令牌登录页的帮助文案。
const _tokenHelp = <String, String>{
  'sakurafrp': '在 SakuraFrp 官网「用户信息」页复制访问密钥',
  'mefrp': '在 ME Frp 官网个人中心复制访问 Token',
};

/// 一个映射平台（`frp.providers` 的条项）。
///
/// 平台清单以 daemon 为唯一真源（`requires_login` / `browser_login` /
/// `token_login` 这些能力判断都在那边），这里只补展示文案。
class FrpProvider {
  const FrpProvider({
    required this.key,
    required this.name,
    required this.requiresLogin,
    required this.browserLogin,
    required this.tokenLogin,
  });

  factory FrpProvider.fromJson(Map<String, dynamic> json) => FrpProvider(
    key: _str(json['key']),
    name: _str(json['name']),
    requiresLogin: _bool(json['requires_login'], orElse: true),
    browserLogin: _bool(json['browser_login']),
    tokenLogin: _bool(json['token_login']),
  );

  /// 稳定标识：`mslfrp` / `openfrp` / `sakurafrp` / `chmlfrp` / `mefrp` / `custom`。
  final String key;

  /// 平台自己的展示名（custom 为空串）。
  final String name;

  final bool requiresLogin;

  /// 走浏览器授权登录（MSL / OpenFrp / ChmlFrp）。
  final bool browserLogin;

  /// 走粘贴访问 Token 登录（Sakura / ME Frp）。
  final bool tokenLogin;

  bool get isCustom => key == 'custom';

  String get displayName => isCustom ? '自定义 FRP' : name;

  String get subtitle => _providerSubtitles[key] ?? '';

  /// 令牌登录页下方的帮助文案。
  String get tokenHelp => _tokenHelp[key] ?? '从平台官网个人中心复制';

  @override
  bool operator ==(Object other) => other is FrpProvider && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// 平台账号（`frp.account` 里的 `account`）。
class FrpAccount {
  const FrpAccount({
    this.username = '',
    this.group = '',
    this.usedTunnels,
    this.maxTunnels,
  });

  factory FrpAccount.fromJson(Map<String, dynamic> json) => FrpAccount(
    username: _str(json['username']),
    group: _str(json['group']),
    usedTunnels: _int(json['used_tunnels']),
    maxTunnels: _int(json['max_tunnels']),
  );

  final String username;
  final String group;

  /// 已用 / 上限隧道数；平台没给就是 `null`。
  final int? usedTunnels;
  final int? maxTunnels;

  /// 账号条上的配额后缀。
  String get quotaText => (usedTunnels != null && maxTunnels != null)
      ? ' · $usedTunnels/$maxTunnels'
      : '';

  /// 账号条的整行文本：`用户名 (用户组) · 1/3`。
  String get displayText =>
      '$username${group.isNotEmpty ? ' ($group)' : ''}$quotaText';
}

/// 某平台的登录态（`frp.account` 的返回体）。
class FrpAccountStatus {
  const FrpAccountStatus({
    required this.provider,
    required this.loggedIn,
    this.account,
  });

  factory FrpAccountStatus.fromJson(Map<String, dynamic> json) {
    final account = _map(json['account']);
    return FrpAccountStatus(
      provider: _str(json['provider']),
      loggedIn: _bool(json['logged_in']),
      account: account == null ? null : FrpAccount.fromJson(account),
    );
  }

  final String provider;

  /// 本地有没有令牌。
  final bool loggedIn;

  /// 缓存里的账号；daemon 只在缓存里有非空用户名时才给。
  final FrpAccount? account;

  /// 供应商选择页靠这一点决定要不要跳过登录页：
  /// **令牌非空 且 账号名非空**，缺一就得再走一次登录。
  bool get canSkipLogin => loggedIn && (account?.username.isNotEmpty ?? false);
}

/// 浏览器授权会话的状态（daemon 侧在轮询）。
enum FrpLoginState {
  /// 从没发起过（或已被取消 / 清理）。
  idle,

  /// 等用户在浏览器里完成授权。
  waiting,

  success,
  error;

  static FrpLoginState parse(Object? raw) => switch (_str(raw)) {
    'waiting' => FrpLoginState.waiting,
    'success' => FrpLoginState.success,
    'error' => FrpLoginState.error,
    _ => FrpLoginState.idle,
  };
}

/// 一次浏览器授权会话（`frp.login.start` / `frp.login.status`）。
class FrpLoginSession {
  const FrpLoginSession({
    required this.provider,
    required this.sessionId,
    required this.state,
    this.message = '',
    this.url = '',
    this.userCode = '',
    this.account,
  });

  factory FrpLoginSession.fromJson(Map<String, dynamic> json) {
    final account = _map(json['account']);
    return FrpLoginSession(
      provider: _str(json['provider']),
      sessionId: _str(json['session_id']),
      state: FrpLoginState.parse(json['state']),
      message: _str(json['message']),
      url: _str(json['url']),
      userCode: _str(json['user_code']),
      account: account == null ? null : FrpAccount.fromJson(account),
    );
  }

  final String provider;
  final String sessionId;
  final FrpLoginState state;

  /// 出错时的提示语；其余状态为空。
  final String message;

  /// 授权页地址（设备码流程里可能自带短码）。
  final String url;

  /// 设备码（仅 ChmlFrp 有）。
  final String userCode;

  /// 成功时的账号。
  final FrpAccount? account;

  bool get isWaiting => state == FrpLoginState.waiting;
  bool get isSuccess => state == FrpLoginState.success;
}

/// 平台节点（`frp.remote.nodes`）。
class FrpNode {
  const FrpNode({
    required this.id,
    required this.name,
    this.hostname = '',
    this.serverPort = 7000,
    this.minPort,
    this.maxPort,
    this.description = '',
    this.online = true,
    this.vip = false,
    this.udpSupport = true,
  });

  factory FrpNode.fromJson(Map<String, dynamic> json) => FrpNode(
    id: _str(json['id']),
    name: _str(json['name']),
    hostname: _str(json['hostname']),
    serverPort: _int(json['server_port']) ?? 7000,
    minPort: _int(json['min_port']),
    maxPort: _int(json['max_port']),
    description: _str(json['description']),
    online: _bool(json['online'], orElse: true),
    vip: _bool(json['vip']),
    udpSupport: _bool(json['udp_support'], orElse: true),
  );

  final String id;
  final String name;

  /// frps 连接地址；部分平台不下发。
  final String hostname;
  final int serverPort;

  /// 允许的远程端口范围；`null` = 未知。
  final int? minPort;
  final int? maxPort;
  final String description;
  final bool online;
  final bool vip;
  final bool udpSupport;

  /// 下拉里的展示名（`名字 [VIP]（离线）`）。
  String get label => '$name${vip ? ' [VIP]' : ''}${online ? '' : '（离线）'}';
}

/// 平台上已存在的隧道（`frp.remote.tunnels`）。
class FrpRemoteTunnel {
  const FrpRemoteTunnel({
    required this.id,
    required this.name,
    this.nodeId = '',
    this.nodeName = '',
    this.type = 'tcp',
    this.localIp = '127.0.0.1',
    this.localPort = 25565,
    this.remotePort,
    this.remoteAddress = '',
    this.online = false,
  });

  factory FrpRemoteTunnel.fromJson(Map<String, dynamic> json) =>
      FrpRemoteTunnel(
        id: _str(json['id']),
        name: _str(json['name']),
        nodeId: _str(json['node_id']),
        nodeName: _str(json['node_name']),
        type: _str(json['type']),
        localIp: _str(json['local_ip']),
        localPort: _int(json['local_port']) ?? 0,
        remotePort: _int(json['remote_port']),
        remoteAddress: _str(json['remote_address']),
        online: _bool(json['online']),
      );

  final String id;
  final String name;
  final String nodeId;
  final String nodeName;
  final String type;
  final String localIp;
  final int localPort;
  final int? remotePort;

  /// 完整公网地址；平台没给就由节点名 + 端口拼。
  final String remoteAddress;
  final bool online;

  /// 展示用公网地址。
  String get displayAddress {
    if (remoteAddress.isNotEmpty) return remoteAddress;
    if (remotePort != null) return '$nodeName:$remotePort';
    return nodeName;
  }
}

/// 本地已保存的隧道（`frp.tunnels.list`）。
class FrpSavedTunnel {
  const FrpSavedTunnel({
    required this.localId,
    required this.provider,
    required this.name,
    this.remoteTunnelId = '',
    this.nodeId = '',
    this.nodeName = '',
    this.type = 'tcp',
    this.localIp = '127.0.0.1',
    this.localPort = 25565,
    this.remotePort,
    this.remoteAddress = '',
    this.configExists = false,
  });

  factory FrpSavedTunnel.fromJson(Map<String, dynamic> json) => FrpSavedTunnel(
    localId: _str(json['local_id']),
    provider: _str(json['provider']),
    name: _str(json['name']),
    remoteTunnelId: _str(json['remote_tunnel_id']),
    nodeId: _str(json['node_id']),
    nodeName: _str(json['node_name']),
    type: _str(json['type']),
    localIp: _str(json['local_ip']),
    localPort: _int(json['local_port']) ?? 0,
    remotePort: _int(json['remote_port']),
    remoteAddress: _str(json['remote_address']),
    configExists: _bool(json['config_exists']),
  );

  final String localId;

  /// 平台 key（`custom` 表示自定义）。
  final String provider;
  final String name;
  final String remoteTunnelId;
  final String nodeId;
  final String nodeName;
  final String type;
  final String localIp;
  final int localPort;
  final int? remotePort;
  final String remoteAddress;

  /// `config/frp/toml/<localId>.toml` 在不在盘上。
  final bool configExists;

  bool get isCustom => provider == 'custom';

  /// 展示用公网地址。
  String get displayAddress {
    if (remoteAddress.isNotEmpty) return remoteAddress;
    if (remotePort != null && nodeName.isNotEmpty) {
      return '$nodeName:$remotePort';
    }
    return nodeName;
  }
}

/// 一份生成好的 frpc 配置（`frp.tunnels.config`）。
class FrpTunnelConfig {
  const FrpTunnelConfig({
    required this.config,
    required this.path,
    required this.generated,
  });

  factory FrpTunnelConfig.fromJson(Map<String, dynamic> json) =>
      FrpTunnelConfig(
        config: _str(json['config']),
        path: _str(json['path']),
        generated: _bool(json['generated']),
      );

  final String config;

  /// 落盘路径（`config/frp/toml/<localId>.toml`）。
  final String path;

  /// 这次是现生成的，还是读的已有文件。
  final bool generated;
}

/// `frp.tunnels.save` 的结果。
class FrpTunnelSaveResult {
  const FrpTunnelSaveResult({required this.tunnel, this.configError = ''});

  factory FrpTunnelSaveResult.fromJson(Map<String, dynamic> json) {
    final tunnel = _map(json['tunnel']);
    return FrpTunnelSaveResult(
      tunnel: tunnel == null
          ? const FrpSavedTunnel(localId: '', provider: '', name: '')
          : FrpSavedTunnel.fromJson(tunnel),
      configError: _str(json['config_error']),
    );
  }

  final FrpSavedTunnel tunnel;

  /// 保存成功但配置没生成出来时的原因（自定义隧道会在保存时顺手生成）。
  final String configError;
}

/// `frp.tunnels.save` 的入参（与 daemon 的 `TunnelInput` 同形）。
///
/// 「前端只发用户填的字段」：简易表单发结构化字段，由 daemon 拼 TOML
/// （`_buildEasyToml` 的实现只有一份，在 daemon 里）。
class FrpTunnelInput {
  const FrpTunnelInput._(this.json);

  final Map<String, dynamic> json;

  /// 平台侧隧道 → 存进本地列表（点「使用」）。
  factory FrpTunnelInput.remote({
    required String provider,
    required String name,
    required String remoteTunnelId,
    required String nodeId,
    required String nodeName,
    required String type,
    required String localIp,
    required int localPort,
    int? remotePort,
    required String remoteAddress,
  }) => FrpTunnelInput._({
    'provider': provider,
    'name': name,
    'remote_tunnel_id': remoteTunnelId,
    'node_id': nodeId,
    'node_name': nodeName,
    'type': type,
    'local_ip': localIp,
    'local_port': localPort,
    'remote_port': remotePort,
    'remote_address': remoteAddress,
  });

  /// 自定义 FRP：简易表单（端口留空发 `null`，由 daemon 统一报
  /// 「请完整填写隧道名称与端口」）。
  factory FrpTunnelInput.customForm({
    required String name,
    required String serverAddr,
    int? serverPort,
    String user = '',
    String authToken = '',
    String type = 'tcp',
    String localIp = '127.0.0.1',
    int? localPort,
    int? remotePort,
    bool tlsEnable = true,
  }) => FrpTunnelInput._({
    'provider': 'custom',
    'name': name,
    'custom_form': {
      'server_addr': serverAddr,
      'server_port': serverPort,
      'user': user,
      'auth_token': authToken,
      'kind': type,
      'local_ip': localIp,
      'local_port': localPort,
      'remote_port': remotePort,
      'tls_enable': tlsEnable,
    },
  });

  /// 自定义 FRP：整段粘贴 frpc 配置。
  factory FrpTunnelInput.customRaw({
    required String name,
    required String toml,
  }) => FrpTunnelInput._({
    'provider': 'custom',
    'name': name,
    'custom_toml': toml,
  });
}

/// 把 frp 的异常翻成给用户看的一句话。
///
/// daemon 的错误码分两类：
///
/// * 平台业务 / 协议错误（`frp_api_error` / `frp_protocol_error`）——
///   message 就是平台那句话，直接用；
/// * 网络层失败（`frp_network_error`）—— 套「网络请求失败：{error}」；
/// * 令牌失效（`frp_unauthorized` / `frp_not_logged_in`）—— 由页面走
///   「清令牌 + 回登录页」那条路，这里只在别处兜底时用。
String describeFrpError(Object error) {
  if (error is DaemonException) {
    return switch (error.code) {
      'frp_network_error' => '网络请求失败：${error.message}',
      'frp_not_logged_in' => '登录已失效，请重新登录',
      'frp_tunnel_not_found' => '本地没有这条隧道（可能已被删除）',
      'frp_node_not_found' => '节点不存在或已下线，请重新选择',
      _ => error.message,
    };
  }
  return '$error';
}

/// 令牌失效（要清凭据、回登录页）的那些错误码。
bool isFrpTokenInvalid(Object error) =>
    error is DaemonException &&
    (error.code == 'frp_unauthorized' || error.code == 'frp_not_logged_in');

// ══════════════════════════════════════════════════════════════════════════
// FRP 实例的运行（一条隧道配置 = 一个可独立运行的实例）
// ══════════════════════════════════════════════════════════════════════════

/// 一个 FRP 实例（一条隧道）的运行态。与 daemon 的 `frp.run.*` 一一对应。
///
/// **没有记录 = 没在跑**：daemon 只在「起过 / 起不来」时才留记录，所以
/// 列表页把查不到的隧道当成「未运行」画（[state] 用 `'stopped'` 补）。
class FrpRun {
  const FrpRun({
    required this.localId,
    required this.tunnelName,
    required this.state,
    this.runtimeId = '',
    this.configPath = '',
    this.pid,
    this.startedAtMs,
    this.exitCode,
    this.message,
    this.log = const [],
  });

  factory FrpRun.fromJson(Map<String, dynamic> json) => FrpRun(
    localId: _str(json['local_id']),
    tunnelName: _str(json['tunnel_name']),
    state: _str(json['state']),
    runtimeId: _str(json['runtime_id']),
    configPath: _str(json['config_path']),
    pid: _int(json['pid']),
    startedAtMs: _int(json['started_at_ms']),
    exitCode: _int(json['exit_code']),
    message: switch (json['message']) {
      final String text when text.isNotEmpty => text,
      _ => null,
    },
    log: [
      for (final line in (json['log'] as List? ?? const []))
        if (line is String) line,
    ],
  );

  /// 哪条隧道 —— 也就是这个 FRP 实例的 id（`config/frp/toml/<localId>.toml`）。
  final String localId;

  /// 隧道显示名（`frp.tunnels.list` 里那个；查不到时 daemon 回退成 id）。
  final String tunnelName;

  /// `running` / `exited` / `failed`。
  final String state;

  /// 跑的是哪个 frpc 运行环境。
  final String runtimeId;

  /// frpc 读的那份配置的绝对路径。
  final String configPath;

  final int? pid;
  final int? startedAtMs;

  /// 退出码（`exited` 时有意义）。
  final int? exitCode;

  /// 起不来 / 退出的原因（给人看的一句话）。
  final String? message;

  /// 最近若干行 frpc 输出（只有 `frp.run.get` 带）。
  final List<String> log;

  bool get isRunning => state == 'running';

  /// 一句话状态 —— 卡片与运行页上那枚小标签。
  String get label => switch (state) {
    'running' => '运行中',
    'exited' =>
      exitCode == null
          ? '已退出'
          : (exitCode == 0 ? '已退出' : '异常退出（退出码 $exitCode）'),
    'failed' => '起不来',
    _ => '未运行',
  };

  /// 状态是不是「有问题」（界面用 error 色画）。
  bool get hasProblem =>
      state == 'failed' || (exitCode != null && exitCode != 0);
}

/// 一个能用来跑隧道的 frpc 运行环境（「网络映射」页那个下拉的一项）。
class FrpcRuntime {
  const FrpcRuntime({required this.id, required this.name});

  factory FrpcRuntime.fromJson(Map<String, dynamic> json) =>
      FrpcRuntime(id: _str(json['id']), name: _str(json['name']));

  /// 运行环境的 id（`frp-frpc-0.71.0-linux-x64`）。
  final String id;

  /// 显示名（`frp 0.71.0` —— daemon 拼好的，前端不自己拼版本号）。
  final String name;
}

/// `frp.runtimes` 的返回：能用的清单 + 当前生效的那个。
class FrpcRuntimeList {
  const FrpcRuntimeList({this.runtimes = const [], this.selected});

  factory FrpcRuntimeList.fromJson(Map<String, dynamic> json) =>
      FrpcRuntimeList(
        runtimes: [
          for (final item in (json['runtimes'] as List? ?? const []))
            if (item is Map) FrpcRuntime.fromJson(item.cast<String, dynamic>()),
        ],
        selected: switch (json['selected']) {
          final String id when id.isNotEmpty => id,
          _ => null,
        },
      );

  static const FrpcRuntimeList empty = FrpcRuntimeList();

  final List<FrpcRuntime> runtimes;

  /// 实际会用的那个（设置里选过就用它；没选过 / 选的那个不在了就是第一项）。
  /// `null` = 一个 frpc 都没装，跑不了隧道。
  final String? selected;
}
