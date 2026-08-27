import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_storage/just_storage.dart';
import 'package:material_ui/material_ui.dart';

import 'package:edgecube_app/server/server_entry.dart';
import 'package:edgecube_app/server/server_service.dart';
import 'package:edgecube_app/settings/appearance.dart';
import 'package:edgecube_app/settings/change_credentials_page.dart';

void main() {
  testWidgets('material_ui MaterialApp 包裹 ChangeCredentialsPage 不应抛 Localizations 异常',
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
    container.read(sessionProvider.notifier).set(
          const ServerSession(
            serverId: ServerEntry.localId,
            token: 'test-token',
            deviceId: 'test-device',
          ),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ChangeCredentialsPage()),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull,
        reason: '标准 MaterialApp 包裹应正常');
  });
}