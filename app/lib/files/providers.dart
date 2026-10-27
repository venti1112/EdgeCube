import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../connection/settings.dart';
import '../connection/state.dart';
import 'api.dart';
import 'transfer.dart';

/// 文件管理 API。未连接时为 `null` —— 调用方要先看连接状态。
final fileApiProvider = Provider<FileApi?>((ref) {
  final client = ref.watch(daemonClientProvider);
  return client == null ? null : FileApi(client);
});

/// 上传 / 下载（HTTP）。没配服务器时为 `null`。
///
/// 这里盯的是**编辑中**的地址，和主连接一致：用户改了地址但还没连上时，
/// 传输自然也该用新地址。
final fileTransferProvider = Provider<FileTransfer?>((ref) {
  final settings = ref.watch(connectionSettingsProvider);
  if (!settings.isConfigured) return null;
  final transfer = HttpFileTransfer(settings);
  ref.onDispose(transfer.close);
  return transfer;
});

/// 「回到文件页」的信号。
///
/// 一条自增信号：谁想触发就 `bump()`，
/// `FileBrowser` 听着它去比对当前目录。
///
/// 值本身没有意义（就是个自增计数）—— 存在只为了让订阅者收到「变了」这件事，
/// 所以别去 `watch` 它当状态用。
final filesRefreshProvider = NotifierProvider<FilesRefreshNotifier, int>(
  FilesRefreshNotifier.new,
);

class FilesRefreshNotifier extends Notifier<int> {
  @override
  int build() => 0;

  /// 请求「静默比对一次当前目录」。
  void bump() => state = state + 1;
}
