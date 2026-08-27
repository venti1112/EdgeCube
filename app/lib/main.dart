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
  // 自动添加“本地服务器”条目并设为首选连接对象;
  // 否则由 redirect 引导到 /setup 添加服务器。
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

  // 启动后自动连接上次/自动发现的服务器(失败仅停留未连接状态,
  // 可在“设置 → 服务器”中重试,不阻塞启动)。
  ServerEntry? entry;
  for (final e in container.read(serverListProvider)) {
    if (e.id == currentServerId) {
      entry = e;
      break;
    }
  }
  if (entry != null) {
    unawaited(container.read(serverServiceProvider).connectTo(entry));
  }
}