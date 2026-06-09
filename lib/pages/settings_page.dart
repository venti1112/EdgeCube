import 'package:flutter/material.dart';

import '../theme/theme_scope.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeScope = ThemeScope.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: RadioGroup<ThemeMode>(
        groupValue: themeScope.themeMode,
        onChanged: (mode) {
          if (mode != null) themeScope.setThemeMode(mode);
        },
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                '外观',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const RadioListTile<ThemeMode>(
              title: Text('跟随系统'),
              secondary: Icon(Icons.brightness_auto),
              value: ThemeMode.system,
            ),
            const RadioListTile<ThemeMode>(
              title: Text('深色模式'),
              secondary: Icon(Icons.dark_mode),
              value: ThemeMode.dark,
            ),
            const RadioListTile<ThemeMode>(
              title: Text('浅色模式'),
              secondary: Icon(Icons.light_mode),
              value: ThemeMode.light,
            ),
          ],
        ),
      ),
    );
  }
}
