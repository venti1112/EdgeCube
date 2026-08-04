import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:logging/logging.dart';

import '../config/developer_options_store.dart';
import '../config/log_store.dart';
import '../i18n/locale_scope.dart';
import '../logging/log_service.dart';
import '../widgets/ec_preference.dart';
import '../widgets/miuix_dialog.dart';
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
    final selected = await showMiuixSingleChoice<Level>(
      context: context,
      title: context.tr('settings.logging.levelDialogTitle'),
      options: kSelectableLogLevels,
      selected: _logLevel,
      labelOf: _logLevelLabel,
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
    final confirmed = await showMiuixConfirm(
      context,
      title: context.tr('settings.developer.disableDialogTitle'),
      message: context.tr('settings.developer.disableDialogMessage'),
    );
    if (!confirmed || !mounted) return;

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
    return EcSettingsPage(
      title: context.tr('settings.section.developer'),
      children: [
        MiuixSmallTitle(context.tr('settings.developer.enabled')),
        MiuixSwitchPreference(
          startAction: prefIcon(Icons.developer_mode),
          title: context.tr('settings.developer.enabled'),
          summary: context.tr('settings.developer.disableHint'),
          value: true,
          onChanged: (_) => _disableDevMode(),
        ),

        MiuixSmallTitle(context.tr('settings.section.logging')),
        MiuixSwitchPreference(
          startAction: prefIcon(Icons.article_outlined),
          title: context.tr('settings.logging.enable'),
          summary: context.tr('settings.logging.enableDesc'),
          value: _logEnabled,
          onChanged: _saveLogEnabled,
        ),
        MiuixArrowPreference(
          startAction: prefIcon(Icons.filter_list),
          title: context.tr('settings.logging.level'),
          summary: context.tr('settings.logging.levelSubtitle', {
            'value': _logLevelLabel(context, _logLevel),
          }),
          enabled: _logEnabled,
          onClick: _pickLogLevel,
        ),
        MiuixArrowPreference(
          startAction: prefIcon(Icons.file_open_outlined),
          title: context.tr('settings.logging.viewer'),
          summary: context.tr('settings.logging.viewerSubtitle'),
          onClick: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const LogViewerPage())),
        ),
      ],
    );
  }
}
