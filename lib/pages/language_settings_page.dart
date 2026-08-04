import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:path/path.dart' as p;

import '../config/locale_store.dart';
import '../files/storage_permission.dart';
import '../files/system_picker.dart';
import '../i18n/app_language.dart';
import '../i18n/i18n_service.dart';
import '../i18n/locale_controller.dart';
import '../i18n/locale_scope.dart';
import '../widgets/ec_preference.dart';
import '../widgets/error_dialog.dart';
import '../widgets/miuix_dialog.dart';
import '../widgets/miuix_snackbar.dart';

/// 语言设置页：选择内置/自定义语言，导入与删除自定义翻译，导出翻译模板。
class LanguageSettingsPage extends StatelessWidget {
  const LanguageSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    // 经 LocaleScope 取控制器并建立依赖，语言或列表变化时本页自动重建。
    final controller = LocaleScope.of(context);
    final available = controller.available;

    return EcSettingsPage(
      title: context.tr('language.title'),
      children: [
        MiuixRadioButtonPreference(
          title: context.tr('common.followSystem'),
          selected: controller.selectedCode == LocaleStore.systemCode,
          startAction: prefIcon(Icons.translate),
          onClick: () => controller.setLanguage(LocaleStore.systemCode),
        ),
        for (final lang in available) _languageTile(context, controller, lang),

        MiuixSmallTitle(context.tr('language.title')),
        MiuixArrowPreference(
          startAction: prefIcon(Icons.file_download_outlined),
          title: context.tr('language.import'),
          summary: context.tr('language.importHint'),
          onClick: () => _import(context, controller),
        ),
        MiuixArrowPreference(
          startAction: prefIcon(Icons.description_outlined),
          title: context.tr('language.exportTemplate'),
          onClick: () => _exportTemplate(context),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
          child: MiuixText(
            context.tr('language.importHint'),
            style: theme.textStyles.footnote1,
            color: theme.colors.onSurfaceVariantSummary,
          ),
        ),
      ],
    );
  }

  /// 单个语言行。内置语言只有单选；自定义语言额外带删除按钮。
  Widget _languageTile(
    BuildContext context,
    LocaleController controller,
    AppLanguage lang,
  ) {
    final badge = context.tr(
      lang.isBuiltin ? 'language.builtin' : 'language.custom',
    );
    final value = '${lang.isBuiltin ? 'b' : 'c'}:${lang.code}';
    return MiuixRadioButtonPreference(
      title: lang.name,
      summary: '${lang.code} · $badge',
      selected: controller.selectedCode == value,
      startAction: lang.isBuiltin ? prefIcon(Icons.language) : null,
      endActions: lang.isBuiltin
          ? null
          : [
              MiuixIconButton(
                onPressed: () => _confirmDelete(context, lang),
                child: const MiuixIcon(icon: Icons.delete_outline),
              ),
            ],
      onClick: () => controller.setLanguage(value),
    );
  }

  /// 确保已获得文件访问权限；未授权时引导用户去系统设置开启。返回是否可继续。
  Future<bool> _ensurePermission(BuildContext context) async {
    if (await StoragePermission.isGranted()) return true;
    if (!context.mounted) return false;
    final go = await showMiuixDialog<bool>(
      context: context,
      title: context.tr('language.permissionTitle'),
      summary: context.tr('language.permissionContent'),
      builder: (ctx) => MiuixDialogActions(
        children: [
          MiuixTextButton(
            ctx.tr('common.cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          MiuixButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            colors: MiuixButtonDefaults.buttonColorsPrimary(ctx),
            child: MiuixText(ctx.tr('language.grant')),
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
    final path = await pickFromSystem(
      context,
      mode: SystemPickMode.file,
      allowedExtensions: const ['.json'],
    );
    if (path == null || !context.mounted) return;
    final successTpl = context.tr('language.importSuccess');
    final failed = context.tr('language.importFailed');
    try {
      final lang = await controller.importCustom(path);
      showMiuixSnackbar(successTpl.replaceAll('{name}', lang.name));
    } catch (_) {
      if (context.mounted) showErrorDialog(context, failed);
    }
  }

  Future<void> _exportTemplate(BuildContext context) async {
    if (!await _ensurePermission(context)) return;
    if (!context.mounted) return;
    final dir = await pickFromSystem(context, mode: SystemPickMode.directory);
    if (dir == null || !context.mounted) return;
    final savedTpl = context.tr('language.exportTemplateSaved');
    final failedTpl = context.tr('language.exportTemplateFailed');
    try {
      final json = await I18nService.exportTemplate();
      final file = File(p.join(dir, 'edgecube_translation_template.json'));
      await file.writeAsString(json);
      showMiuixSnackbar(savedTpl.replaceAll('{path}', file.path));
    } catch (e) {
      // 写入失败（权限或路径问题）：弹窗提示。
      if (context.mounted) {
        showErrorDialog(context, failedTpl.replaceAll('{error}', '$e'));
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, AppLanguage lang) async {
    final controller = LocaleScope.of(context);
    final confirmed = await showMiuixConfirm(
      context,
      title: context.tr('language.deleteConfirmTitle'),
      message: context
          .tr('language.deleteConfirmContent')
          .replaceAll('{name}', lang.name),
      confirmLabel: context.tr('common.delete'),
    );
    if (confirmed) await controller.removeCustom(lang.code);
  }
}
