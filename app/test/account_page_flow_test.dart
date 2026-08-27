import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_storage/just_storage.dart';

import 'package:edgecube_app/app.dart';
import 'package:edgecube_app/router.dart';
import 'package:edgecube_app/server/server_entry.dart';
import 'package:edgecube_app/server/server_service.dart';
import 'package:edgecube_app/settings/appearance.dart';

void main() {
  testWidgets('连接后进入 设置→修改账密 页面不应抛出 No MaterialLocalizations',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('ec_test_');
    final storage = await JustStorage.standard(dir);
    addTearDown(() => dir.deleteSync(recursive: true));

    final container = ProviderContainer(
      overrides: [
        storageProvider.overrideWithValue(storage),
        initialAppearanceProvider
            .overrideWithValue(const AppearanceSettings()),
        initialServersProvider.overrideWithValue([ServerEntry.defaultLocal()]),
        initialCurrentServerIdProvider.overrideWithValue(ServerEntry.localId),
        hasLocalKeyProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const EdgeCubeApp()),
    );
    // 模拟启动连接成功:写入会话并结束连接阶段,redirect 应进入主界面
    container.read(sessionProvider.notifier).set(
          const ServerSession(
            serverId: ServerEntry.localId,
            token: 'test-token',
            deviceId: 'test-device',
          ),
        );
    container.read(startupStageProvider.notifier).finish();
    await tester.pumpAndSettle();

    final router = container.read(routerProvider);
    router.go('/settings');
    await tester.pumpAndSettle();

    router.push('/settings/account');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: '修改账密页不应抛出 No MaterialLocalizations');
    expect(find.text('修改账密'), findsOneWidget);
  });
}