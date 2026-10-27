import 'dart:convert';

import 'package:edgecube_app/app.dart';
import 'package:edgecube_app/connection/settings.dart';
import 'package:edgecube_app/mods/mods_page.dart';
import 'package:edgecube_app/pages/connect_page.dart';
import 'package:edgecube_app/pages/manage_page.dart';
import 'package:edgecube_app/router.dart';
import 'package:edgecube_app/shell/home_shell.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_transport.dart';

/// 已配置好的服务器：这些用例测的是「底栏/侧栏在子页上是否还在」，
/// 不该被「首次启动连接页」挡住 —— 统一注入一份已保存的连接配置
/// （假传输，不会真去连网）。
const _savedConnection = ConnectionSettings(host: '127.0.0.1', token: 't');

/// 启动 App（复刻 main() 的预加载 + override 路径）。
///
/// [persisted] = false 模拟「从未连过」：应当停在连接页。
Future<ProviderContainer> _pumpApp(
  WidgetTester tester, {
  bool persisted = true,
}) async {
  SharedPreferences.setMockInitialValues({
    if (persisted)
      ConnectionSettings.storageKey: jsonEncode(_savedConnection.toJson()),
  });
  final prefs = await SharedPreferences.getInstance();
  final container = bootContainer(
    storage: prefs,
    persisted: loadPersistedConnection(prefs),
    transportFactory: FakeTransportFactory(
      frp: FakeFrpStore(),
      runtime: FakeRuntimeStore(),
    ).call,
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const EdgeCubeApp()),
  );
  await tester.pumpAndSettle();
  return container;
}

/// 推进若干帧把在飞的异步/路由过渡跑完。
///
/// **不用 `pumpAndSettle`**：子页里常挂着转圈的加载指示（假传输只会报错），
/// 它一帧一帧地画，永远等不到「静止」。
Future<void> pumpFrames(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// 竖屏（小屏）→ 底栏；不改尺寸时默认 800×600 横屏 → 侧栏。
void usePortrait(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('从管理页点进子页：底栏还在、高亮「管理」、返回回管理页', (tester) async {
    usePortrait(tester);
    await _pumpApp(tester);

    await tester.tap(find.text('管理'));
    await pumpFrames(tester);
    expect(find.byType(ManagePage), findsOneWidget);

    await tester.tap(find.text('模组与插件'));
    await pumpFrames(tester);

    expect(find.byType(ModsPage), findsOneWidget);
    expect(find.byType(HomeShell), findsOneWidget, reason: '子页仍在 shell 里');
    expect(find.byType(NavigationBar), findsOneWidget, reason: '子页也要保持底栏');
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
      reason: '子页仍高亮「管理」页签',
    );

    // 顶栏返回键把子页弹回管理页（子页在分支导航器里，可返回）
    await tester.tap(find.byType(BackButton));
    await pumpFrames(tester, frames: 30);
    expect(find.byType(ManagePage), findsOneWidget);
    expect(find.byType(ModsPage), findsNothing);
  });

  testWidgets('所有子路由都带底栏（竖屏）', (tester) async {
    usePortrait(tester);
    final container = await _pumpApp(tester);
    final router = container.read(routerProvider);

    for (final location in const [
      '/servers/create',
      '/manage/players',
      '/manage/config',
      '/manage/mods',
      '/manage/runtime',
      '/manage/runtime/download',
      '/manage/network',
      '/manage/network/tunnels',
      '/manage/network/tunnels/picker',
      '/manage/network/tunnels/custom',
      '/manage/network/tunnels/login/openfrp',
      '/manage/network/tunnels/provider/openfrp',
      '/manage/network/tunnels/run/demo',
      '/manage/network/tunnels/config/demo',
      '/settings/appearance',
      '/settings/connection',
      '/settings/about',
    ]) {
      router.go(location);
      await pumpFrames(tester);
      expect(
        find.byType(NavigationBar),
        findsOneWidget,
        reason: '$location 应保持底栏',
      );
    }
  });

  testWidgets('横屏下子页保持侧栏', (tester) async {
    // 默认测试窗口 800×600 即为横屏 → HomeShell 渲染 NavigationRail
    final container = await _pumpApp(tester);
    container.read(routerProvider).go('/manage/mods');
    await pumpFrames(tester);

    expect(find.byType(ModsPage), findsOneWidget);
    expect(find.byType(NavigationRail), findsOneWidget, reason: '子页也要保持侧栏');
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('首次连接设置页不带底栏（唯一例外）', (tester) async {
    usePortrait(tester);
    await _pumpApp(tester, persisted: false);

    expect(find.byType(ConnectPage), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(HomeShell), findsNothing);
  });
}
