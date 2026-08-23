import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_storage/just_storage.dart';

import 'app.dart';
import 'settings/appearance.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await JustStorage.standard();
  final appearance = await loadAppearanceSettings(storage);
  runApp(
    ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage),
        initialAppearanceProvider.overrideWithValue(appearance),
      ],
      child: const EdgeCubeApp(),
    ),
  );
}
