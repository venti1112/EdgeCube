import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import '../config/developer_options_store.dart';
import '../config/log_store.dart';
import '../i18n/locale_scope.dart';
import '../logging/log_service.dart';
import 'log_viewer_page.dart';

/// 「开发者选项」页面。
///
/// 仅在开发者模式启用后可从设置页进入。包含日志开关、日志等级、日志查看入口，
/// 以及关闭开发者模式的开关（关闭时自动将开发者选项中的设置项恢复默认值）。
class DeveloperOptionsPage extends StatefulWidget {
  const DeveloperOptionsPage({super.key});

  @override
  State<DeveloperOptionsPage> createState() => _DeveloperOptionsPageState();
}

class _DeveloperOptionsPageState extends State<DeveloperOptionsPage> {
  bool _logEnabled = false;
  Level _logLevel = Level.INFO;

  @override
  void initState() {
    super.initState();
    _loadLogSettings();
  }

  // ── 日志设置 ──────────────────────────────────────────────

  Future<void> _loadLogSettings() async {
    final enabled = await LogStore.loadEnabled();
    final level = await LogStore.loadLevel();
    if (mounted) {
      setState(() {
        _logEnabled = enabled;
        _logLevel = level;
      });
    }
  }

  Future<void> _saveLogEnabled(bool value) async {
    setState(() => _logEnabled = value);
    await LogService.instance.setEnabled(value);
  }

  String _logLevelLabel(BuildContext context, Level level) {
    return context.tr('settings.logging.level.${level.name}');
  }

  /// 弹出日志等级选择对话框。
  Future<void> _pickLogLevel() async {
    final selected = await showDialog<Level>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(ctx.tr('settings.logging.levelDialogTitle')),
        children: [
          for (final level in kSelectableLogLevels)
            ListTile(
              leading: Icon(
                level == _logLevel
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: level == _logLevel
                    ? Theme.of(ctx).colorScheme.primary
                    : null,
              ),
              title: Text(_logLevelLabel(ctx, level)),
              onTap: () => Navigator.of(ctx).pop(level),
            ),
        ],
      ),
    );
    if (selected != null && selected != _logLevel) {
      setState(() => _logLevel = selected);
      await LogService.instance.setLevel(selected);
    }
  }

  // ── 关闭开发者模式 ────────────────────────────────────────

  /// 关闭开发者模式：弹出确认对话框，确认后将开发者选项中的设置项恢复默认值，
  /// 持久化关闭状态后返回设置页。
  Future<void> _disableDevMode() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('settings.developer.disableDialogTitle')),
        content: Text(ctx.tr('settings.developer.disableDialogMessage')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.tr('common.confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // 将日志设置恢复默认（关闭 + INFO）
    await LogService.instance.setEnabled(false);
    await LogService.instance.setLevel(Level.INFO);
    // 持久化关闭开发者模式
    await DeveloperOptionsStore.saveEnabled(false);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('settings.section.developer'))),
      body: ListView(
        children: [
          _sectionHeader(theme, context.tr('settings.developer.enabled')),
          SwitchListTile(
            secondary: const Icon(Icons.developer_mode),
            title: Text(context.tr('settings.developer.enabled')),
            subtitle: Text(context.tr('settings.developer.disableHint')),
            value: true,
            onChanged: (_) => _disableDevMode(),
          ),
          const Divider(),
          _sectionHeader(theme, context.tr('settings.section.logging')),
          SwitchListTile(
            secondary: const Icon(Icons.article_outlined),
            title: Text(context.tr('settings.logging.enable')),
            subtitle: Text(context.tr('settings.logging.enableDesc')),
            value: _logEnabled,
            onChanged: _saveLogEnabled,
          ),
          ListTile(
            leading: const Icon(Icons.filter_list),
            title: Text(context.tr('settings.logging.level')),
            subtitle: Text(
              context.tr('settings.logging.levelSubtitle', {
                'value': _logLevelLabel(context, _logLevel),
              }),
            ),
            trailing: const Icon(Icons.chevron_right),
            enabled: _logEnabled,
            onTap: _pickLogLevel,
          ),
          ListTile(
            leading: const Icon(Icons.file_open_outlined),
            title: Text(context.tr('settings.logging.viewer')),
            subtitle: Text(context.tr('settings.logging.viewerSubtitle')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LogViewerPage()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
