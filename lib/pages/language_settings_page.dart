import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../config/locale_store.dart';
import '../files/storage_permission.dart';
import '../files/system_picker.dart';
import '../i18n/app_language.dart';
import '../i18n/i18n_service.dart';
import '../i18n/locale_controller.dart';
import '../i18n/locale_scope.dart';

/// 语言设置页：选择内置/自定义语言，导入与删除自定义翻译，导出翻译模板。
class LanguageSettingsPage extends StatelessWidget {
  const LanguageSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 经 LocaleScope 取控制器并建立依赖，语言或列表变化时本页自动重建。
    final controller = LocaleScope.of(context);
    final available = controller.available;

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('language.title'))),
      body: ListView(
        children: [
          RadioGroup<String>(
            groupValue: controller.selectedCode,
            onChanged: (code) {
              if (code != null) controller.setLanguage(code);
            },
            child: Column(
              children: [
                RadioListTile<String>(
                  value: LocaleStore.systemCode,
                  title: Text(context.tr('common.followSystem')),
                  secondary: const Icon(Icons.translate),
                ),
                for (final lang in available) _languageTile(context, lang),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: Text(context.tr('language.import')),
            subtitle: Text(context.tr('language.importHint')),
            onTap: () => _import(context, controller),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(context.tr('language.exportTemplate')),
            onTap: () => _exportTemplate(context),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Text(
              context.tr('language.importHint'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 单个语言行。内置语言用 `b:<code>` 单选项；自定义语言用 `c:<code>` 额外带删除按钮。
  Widget _languageTile(BuildContext context, AppLanguage lang) {
    final badge = context.tr(
      lang.isBuiltin ? 'language.builtin' : 'language.custom',
    );
    final value = '${lang.isBuiltin ? 'b' : 'c'}:${lang.code}';
    if (lang.isBuiltin) {
      return RadioListTile<String>(
        value: value,
        title: Text(lang.name),
        subtitle: Text('${lang.code} · $badge'),
        secondary: const Icon(Icons.language),
      );
    }
    // 自定义语言：单选 + 右侧删除。
    return RadioListTile<String>(
      value: value,
      title: Text(lang.name),
      subtitle: Text('${lang.code} · $badge'),
      secondary: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: context.tr('common.delete'),
        onPressed: () => _confirmDelete(context, lang),
      ),
    );
  }

  /// 确保已获得文件访问权限；未授权时引导用户去系统设置开启。返回是否可继续。
  Future<bool> _ensurePermission(BuildContext context) async {
    if (await StoragePermission.isGranted()) return true;
    if (!context.mounted) return false;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('language.permissionTitle')),
        content: Text(ctx.tr('language.permissionContent')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.tr('language.grant')),
          ),
        ],
      ),
    );
    if (go == true) await StoragePermission.request();
    return false;
  }

  Future<void> _import(
    BuildContext context,
    LocaleController controller,
  ) async {
    if (!await _ensurePermission(context)) return;
    if (!context.mounted) return;
    final path = await pickFromSystem(context, mode: SystemPickMode.file);
    if (path == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final successTpl = context.tr('language.importSuccess');
    final failed = context.tr('language.importFailed');
    try {
      final lang = await controller.importCustom(path);
      messenger.showSnackBar(
        SnackBar(content: Text(successTpl.replaceAll('{name}', lang.name))),
      );
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  Future<void> _exportTemplate(BuildContext context) async {
    if (!await _ensurePermission(context)) return;
    if (!context.mounted) return;
    final dir = await pickFromSystem(context, mode: SystemPickMode.directory);
    if (dir == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final savedTpl = context.tr('language.exportTemplateSaved');
    try {
      final json = await I18nService.exportTemplate();
      final file = File(p.join(dir, 'edgecube_translation_template.json'));
      await file.writeAsString(json);
      messenger.showSnackBar(
        SnackBar(content: Text(savedTpl.replaceAll('{path}', file.path))),
      );
    } catch (_) {
      // 写入失败静默忽略（权限或路径问题）。
    }
  }

  Future<void> _confirmDelete(BuildContext context, AppLanguage lang) async {
    final controller = LocaleScope.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('language.deleteConfirmTitle')),
        content: Text(
          ctx
              .tr('language.deleteConfirmContent')
              .replaceAll('{name}', lang.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.tr('common.delete')),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.removeCustom(lang.code);
  }
}
