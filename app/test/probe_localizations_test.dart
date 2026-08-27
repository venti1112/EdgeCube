import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_storage/just_storage.dart';

import 'package:edgecube_app/pages/servers_page.dart';
import 'package:edgecube_app/router.dart';
import 'package:edgecube_app/server/server_entry.dart';
import 'package:edgecube_app/server/server_service.dart';
import 'package:edgecube_app/settings/appearance.dart';
import 'package:edgecube_app/settings/change_credentials_page.dart';
import 'package:edgecube_app/settings/main.dart';
import 'package:go_router/go_router.dart';

void main() {
  Future<ProviderContainer> makeContainer() async {
    final dir = Directory.systemTemp.createTempSync('ec_test_');
    final storage = await JustStorage.standard(dir);
    addTearDown(() => dir.deleteSync(recursive: true));
    final container = ProviderContainer(
      overrides: [
        storageProvider.overrideWithValue(storage),
        initialAppearanceProvider.overrideWithValue(const AppearanceSettings()),
        initialServersProvider.overrideWithValue([ServerEntry.defaultLocal()]),
        initialCurrentServerIdProvider.overrideWithValue(ServerEntry.localId),
        hasLocalKeyProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);
    container.read(sessionProvider.notifier).set(
          const ServerSession(
            serverId: ServerEntry.localId,
            token: 'test-token',
            deviceId: 'test-device',
          ),
        );
    container.read(startupStageProvider.notifier).finish();
    return container;
  }

  testWidgets('标准 flutter MaterialApp.router + go_router 同结构',
      (tester) async {
    final container = await makeContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          title: 'EdgeCube',
          routerConfig: container.read(routerProvider),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final router = container.read(routerProvider);
    debugPrint('=== go /settings ===');
    router.go('/settings');
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final e = tester.takeException();
      final first = e == null ? 'null' : e.toString().split('\n').first;
      debugPrint('frame $i exception -> $first');
      if (e is FlutterError && i <= 1) {
        final s = e.toString();
        final relevant = s.contains('relevan')
            ? s.substring(s.indexOf('The relevant error-causing widget'))
            : '<none>';
        debugPrint('DUMP0 relevant >>> ${relevant.split('\n').take(3).join(' | ')}');
      }
    }
    debugPrint('=== push /settings/account ===');
    router.push('/settings/account');
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final e = tester.takeException();
      debugPrint('frame $i exception -> ${e?.toString().split('\n').first}');
    }

    final ctx = tester.element(find.text('修改账密'));
    final loc = Localizations.of<MaterialLocalizations>(ctx, MaterialLocalizations);
    final lw = ctx.findAncestorWidgetOfExactType<Localizations>();
    debugPrint('PROBE MaterialLocalizations -> $loc');
    debugPrint('PROBE Localizations.delegates -> ${lw?.delegates}');
    if (lw != null) {
      Locale? loc2;
      try {
        loc2 = Localizations.localeOf(ctx);
      } catch (e) {
        loc2 = null;
      }
      debugPrint('PROBE localeOf -> $loc2');
      debugPrint('PROBE widgetLocale -> ${lw.locale}');
    }

    final err = tester.takeException();
    debugPrint('PROBE standard MaterialApp.router exception -> $err');
    expect(find.text('修改账密'), findsOneWidget);
  });

  testWidgets('平铺 GoRoute:go 与 push 不应抛 Localizations 异常', (tester) async {
    final container = await makeContainer();
    final flatRouter = GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(path: '/servers', builder: (c, s) => const ServersPage()),
        GoRoute(path: '/settings', builder: (c, s) => const SettingsPage()),
        GoRoute(
          path: '/settings/account',
          builder: (c, s) => const ChangeCredentialsPage(),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(title: 'EdgeCube', routerConfig: flatRouter),
      ),
    );
    await tester.pumpAndSettle();
    debugPrint('FLAT initial -> ${tester.takeException()}');

    flatRouter.go('/settings/account');
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      debugPrint('FLAT go frame $i -> ${tester.takeException()}');
    }
    final ctx = tester.element(find.text('修改账密'));
    debugPrint(
        'FLAT probe MaterialLocalizations -> ${Localizations.of<MaterialLocalizations>(ctx, MaterialLocalizations)}');
    expect(tester.takeException(), isNull);
  });
}