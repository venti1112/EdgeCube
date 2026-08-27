import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_storage/just_storage.dart';

import 'app.dart';
import 'server/local_key.dart';
import 'server/server_entry.dart';
import 'server/server_service.dart';
import 'settings/appearance.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await JustStorage.standard();
  final appearance = await loadAppearanceSettings(storage);
  final servers = await loadServers(storage);
  var currentServerId = await loadLastServerId(storage);
  final hasKey = await hasLocalKey();

  // 启动引导:配置为空时,若本机存在 daemon 的 local.key,
  // 自动添加“本地服务器”条目并设为首选连接对象。
  if (servers.isEmpty && hasKey) {
    final local = ServerEntry.defaultLocal();
    await storage.write(
      ServerListNotifier.storageKey,
      jsonEncode([local]),
    );
    currentServerId = local.id;
    await storage.write(CurrentServerIdNotifier.storageKey, local.id);
  }

  final container = ProviderContainer(
    overrides: [
      storageProvider.overrideWithValue(storage),
      initialAppearanceProvider.overrideWithValue(appearance),
      initialServersProvider.overrideWithValue(
        servers.isEmpty && hasKey ? [ServerEntry.defaultLocal()] : servers,
      ),
      initialCurrentServerIdProvider.overrideWithValue(currentServerId),
      hasLocalKeyProvider.overrideWithValue(hasKey),
    ],
  );
  runApp(
    UncontrolledProviderScope(container: container, child: const EdgeCubeApp()),
  );

  // 启动连接:优先连接上次最后连接的服务器,否则连接列表第一台。
  // 连接页会一直显示到连接流程结束(成功/失败),之后由 redirect 跳转。
  ServerEntry? target;
  final list = container.read(serverListProvider);
  if (currentServerId != null) {
    for (final e in list) {
      if (e.id == currentServerId) {
        target = e;
        break;
      }
    }
  }
  target ??= list.isNotEmpty ? list.first : null;
  if (target != null) {
    unawaited(_startupConnect(container, target));
  } else {
    container.read(startupStageProvider.notifier).finish();
  }
}

/// 启动连接任务:结束时无论成败都将启动阶段置为 finished,
/// redirect 依据连接结果进入主界面或服务器管理页。
Future<void> _startupConnect(
  ProviderContainer container,
  ServerEntry entry,
) async {
  try {
    await container.read(serverServiceProvider).connectTo(entry);
  } on ServerException catch (e) {
    debugPrint('[EdgeCube] 启动连接失败: ${e.message}');
  } catch (e) {
    debugPrint('[EdgeCube] 启动连接异常: $e');
  } finally {
    container.read(startupStageProvider.notifier).finish();
  }
}