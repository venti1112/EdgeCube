import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../connection/client.dart';
import '../connection/state.dart';

/// 主机终端（`/shell`）的管理接口。
///
/// 只有**控制面**在这里：终端数据走 `/shell` 那条 PTY 流（见 `TerminalPane`），
/// 不经过 WS 的 request/response。
class ShellApi {
  const ShellApi(this._client);

  final DaemonClient _client;

  /// 杀掉当前 shell 并立即重开（卡死时的逃生口）。
  ///
  /// daemon 侧是同步完成的 —— 返回时新 shell 已经起来了，前端接上就能用。
  Future<void> restart() => _client.call('shell.restart');
}

/// 主机终端接口；未连接时为 `null`。
final shellApiProvider = Provider<ShellApi?>((ref) {
  final client = ref.watch(daemonClientProvider);
  return client == null ? null : ShellApi(client);
});
