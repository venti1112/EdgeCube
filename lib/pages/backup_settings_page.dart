import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';

import '../backup/backup_controller.dart';
import '../backup/backup_scope.dart';
import '../config/backup_store.dart';
import '../files/storage_permission.dart';
import '../files/system_picker.dart';
import '../i18n/i18n_service.dart';
import '../i18n/locale_scope.dart';
import '../instance/instance_scope.dart';
import '../widgets/ec_preference.dart';
import '../widgets/ec_text_field.dart';
import '../widgets/error_dialog.dart';
import '../widgets/loading_dialog.dart';
import '../widgets/miuix_dialog.dart';
import '../widgets/miuix_snackbar.dart';

/// 备份设置页：调度、备份实例、本地/WebDav 目标、保留策略与手动备份。
class BackupSettingsPage extends StatefulWidget {
  const BackupSettingsPage({super.key});

  @override
  State<BackupSettingsPage> createState() => _BackupSettingsPageState();
}

class _BackupSettingsPageState extends State<BackupSettingsPage> {
  final _webdavUrlController = TextEditingController();
  final _webdavUserController = TextEditingController();
  final _webdavPassController = TextEditingController();
  final _webdavPathController = TextEditingController();
  bool _webdavLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadWebdavFields();
  }

  @override
  void dispose() {
    _webdavUrlController.dispose();
    _webdavUserController.dispose();
    _webdavPassController.dispose();
    _webdavPathController.dispose();
    super.dispose();
  }

  Future<void> _loadWebdavFields() async {
    final controller = BackupScope.of(context);
    final password = await controller.loadWebdavPassword();
    if (!mounted) return;
    setState(() {
      _webdavUrlController.text = controller.webdavUrl;
      _webdavUserController.text = controller.webdavUsername;
      _webdavPassController.text = password;
      _webdavPathController.text = controller.webdavRemotePath;
      _webdavLoaded = true;
    });
  }

  String _modeLabel(BuildContext context, BackupMode mode) {
    return mode == BackupMode.full
        ? context.tr('backup.mode.full')
        : context.tr('backup.mode.incremental');
  }

  String _intervalLabel(int hours) {
    if (hours < 24) return '$hours${context.tr('backup.interval.hours')}';
    if (hours == 24) return context.tr('backup.interval.daily');
    final days = hours ~/ 24;
    return '$days${context.tr('backup.interval.days')}';
  }

  String _lastBackupLabel(BuildContext context, BackupController controller) {
    final ts = controller.lastBackupTime;
    if (ts == null) return context.tr('backup.lastBackup.never');
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _pickMode() async {
    final controller = BackupScope.of(context);
    final selected = await showMiuixSingleChoice<BackupMode>(
      context: context,
      title: context.tr('backup.mode.title'),
      options: BackupMode.values,
      selected: controller.mode,
      labelOf: _modeLabel,
      hint: context.tr('backup.mode.hint'),
    );
    if (selected != null) await controller.setMode(selected);
  }

  /// 哨兵值：表示单选列表中的「自定义」项。
  static const int _kCustomOption = -1;

  Future<void> _pickInterval() async {
    final controller = BackupScope.of(context);
    final current = controller.intervalHours;
    final isPreset = kBackupIntervalOptions.contains(current);
    final selected = await showMiuixSingleChoice<int>(
      context: context,
      title: context.tr('backup.interval.title'),
      options: [...kBackupIntervalOptions, _kCustomOption],
      selected: isPreset ? current : _kCustomOption,
      labelOf: (_, hours) => hours == _kCustomOption
          ? context.tr('backup.custom')
          : _intervalLabel(hours),
    );
    if (selected == null || !mounted) return;
    if (selected != _kCustomOption) {
      await controller.setIntervalHours(selected);
      return;
    }
    final value = await _editNumber(
      title: context.tr('backup.interval.title'),
      hint: context.tr('backup.interval.customHint'),
      currentValue: current,
      min: 1,
      max: 720,
      invalidMessage: context.tr('backup.interval.invalid'),
    );
    if (value != null) await controller.setIntervalHours(value);
  }

  Future<void> _pickRetention() async {
    final controller = BackupScope.of(context);
    final current = controller.retentionSets;
    final isPreset = kBackupRetentionOptions.contains(current);
    final selected = await showMiuixSingleChoice<int>(
      context: context,
      title: context.tr('backup.retention.title'),
      options: [...kBackupRetentionOptions, _kCustomOption],
      selected: isPreset ? current : _kCustomOption,
      labelOf: (_, sets) => sets == _kCustomOption
          ? context.tr('backup.custom')
          : '$sets${context.tr('backup.retention.sets')}',
      hint: context.tr('backup.retention.hint'),
    );
    if (selected == null || !mounted) return;
    if (selected != _kCustomOption) {
      await controller.setRetentionSets(selected);
      return;
    }
    final value = await _editNumber(
      title: context.tr('backup.retention.title'),
      hint: context.tr('backup.retention.customHint'),
      currentValue: current,
      min: 1,
      max: 50,
      invalidMessage: context.tr('backup.retention.invalid'),
    );
    if (value != null) await controller.setRetentionSets(value);
  }

  /// 数字输入对话框：用于自定义备份间隔或保留组数。
  ///
  /// 返回用户输入的有效整数；取消或输入非法时返回 null。
  Future<int?> _editNumber({
    required String title,
    required String hint,
    required int currentValue,
    required int min,
    required int max,
    required String invalidMessage,
  }) async {
    final controller = TextEditingController(text: '$currentValue');
    String? errorText;
    final result = await showMiuixDialog<int>(
      context: context,
      title: title,
      builder: (ctx) {
        final theme = MiuixTheme.of(ctx);
        return StatefulBuilder(
          builder: (ctx, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MiuixText(
                  hint,
                  style: theme.textStyles.footnote1,
                  color: theme.colors.onSurfaceVariantSummary,
                ),
                const SizedBox(height: 12),
                EcTextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  errorText: errorText,
                  onChanged: (_) {
                    if (errorText != null) {
                      setState(() => errorText = null);
                    }
                  },
                ),
                const SizedBox(height: 20),
                MiuixDialogActions(
                  children: [
                    MiuixTextButton(
                      ctx.tr('common.cancel'),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                    MiuixButton(
                      onPressed: () {
                        final raw = controller.text.trim();
                        final value = int.tryParse(raw);
                        if (value == null || value < min || value > max) {
                          setState(() => errorText = invalidMessage);
                          return;
                        }
                        Navigator.of(ctx).pop(value);
                      },
                      colors: MiuixButtonDefaults.buttonColorsPrimary(ctx),
                      child: MiuixText(ctx.tr('common.save')),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    return result;
  }

  Future<void> _pickLocalPath() async {
    final controller = BackupScope.of(context);
    if (!await _ensurePermission()) return;
    if (!mounted) return;
    final picked = await pickFromSystem(
      context,
      mode: SystemPickMode.directory,
    );
    if (picked == null || !mounted) return;
    await controller.setLocalPath(picked);
  }

  Future<bool> _ensurePermission() async {
    if (await StoragePermission.isGranted()) return true;
    if (!mounted) return false;
    final go = await showMiuixConfirm(
      context,
      title: context.tr('backup.permission.title'),
      message: context.tr('backup.permission.content'),
      cancelLabel: context.tr('common.cancel'),
      confirmLabel: context.tr('backup.permission.grant'),
    );
    if (go == true) {
      await StoragePermission.request();
    }
    return false;
  }

  Future<void> _testWebdav() async {
    final controller = BackupScope.of(context);
    final url = _webdavUrlController.text.trim();
    if (url.isEmpty) {
      showMiuixSnackbar(tr('backup.webdav.urlEmpty'));
      return;
    }
    if (!mounted) return;
    showLoadingDialog(context, context.tr('backup.webdav.testing'));
    try {
      final ok = await controller.testWebdavConnection(
        url: url,
        username: _webdavUserController.text.trim(),
        password: _webdavPassController.text,
        remotePath: _webdavPathController.text.trim().isEmpty
            ? '/EdgeCube'
            : _webdavPathController.text.trim(),
      );
      if (mounted) Navigator.of(context).pop();
      showMiuixSnackbar(
        ok ? tr('backup.webdav.testSuccess') : tr('backup.webdav.testFailed'),
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        showErrorDialog(
          context,
          '${tr('backup.webdav.testFailed')}: $e',
        );
      }
    }
  }

  Future<void> _backupNow() async {
    final controller = BackupScope.of(context);
    if (controller.selectedInstanceIds.isEmpty) {
      showMiuixSnackbar(tr('backup.noInstance'));
      return;
    }
    if (!controller.localEnabled && !controller.webdavEnabled) {
      showMiuixSnackbar(tr('backup.noTarget'));
      return;
    }
    if (!mounted) return;
    showLoadingDialog(context, context.tr('backup.running'));
    try {
      final result = await controller.runBackupNow();
      if (mounted) Navigator.of(context).pop();
      if (!mounted) return;
      if (result.error != null) {
        final msg = result.error == 'no_instance'
            ? tr('backup.noInstance')
            : result.error == 'no_target'
            ? tr('backup.noTarget')
            : tr('backup.failed');
        showMiuixSnackbar(msg);
      } else if (result.backed > 0) {
        showMiuixSnackbar(
          tr('backup.success', {
            'backed': '${result.backed}',
            'skipped': '${result.skipped}',
          }),
        );
      } else if (result.skipped > 0) {
        showMiuixSnackbar(tr('backup.nothingChanged'));
      } else {
        showMiuixSnackbar(tr('backup.nothingChanged'));
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        showErrorDialog(context, '${tr('backup.failed')}: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = BackupScope.of(context);
    final instances = InstanceScope.of(context).instances;
    final theme = MiuixTheme.of(context);

    return EcSettingsPage(
      title: context.tr('backup.title'),
      children: [
        // ── 调度 ──────────────────────────────────────────
        MiuixSmallTitle(context.tr('backup.section.schedule')),
        MiuixSwitchPreference(
          startAction: prefIcon(Icons.schedule),
          title: context.tr('backup.enabled'),
          summary: context.tr('backup.enabledDescription'),
          value: controller.enabled,
          onChanged: controller.setEnabled,
        ),
        MiuixArrowPreference(
          startAction: prefIcon(Icons.layers_outlined),
          title: context.tr('backup.mode.title'),
          summary: _modeLabel(context, controller.mode),
          onClick: _pickMode,
        ),
        MiuixArrowPreference(
          startAction: prefIcon(Icons.timer_outlined),
          title: context.tr('backup.interval.title'),
          summary: _intervalLabel(controller.intervalHours),
          onClick: _pickInterval,
        ),

        // ── 备份实例 ──────────────────────────────────────
        MiuixSmallTitle(context.tr('backup.section.instances')),
        if (instances.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: MiuixText(
              context.tr('backup.instances.empty'),
              style: theme.textStyles.body2,
              color: theme.colors.onSurfaceVariantSummary,
            ),
          )
        else
          for (final instance in instances)
            MiuixSwitchPreference(
              startAction: prefIcon(Icons.dns_outlined),
              title: instance.name,
              summary: instance.id,
              value: controller.selectedInstanceIds.contains(instance.id),
              onChanged: (value) {
                final ids = List<String>.from(controller.selectedInstanceIds);
                if (value) {
                  if (!ids.contains(instance.id)) ids.add(instance.id);
                } else {
                  ids.remove(instance.id);
                }
                controller.setSelectedInstanceIds(ids);
              },
            ),

        // ── 本地备份 ──────────────────────────────────────
        MiuixSmallTitle(context.tr('backup.section.local')),
        MiuixSwitchPreference(
          startAction: prefIcon(Icons.folder_outlined),
          title: context.tr('backup.local.enabled'),
          summary: context.tr('backup.local.enabledDescription'),
          value: controller.localEnabled,
          onChanged: controller.setLocalEnabled,
        ),
        MiuixArrowPreference(
          startAction: prefIcon(Icons.drive_folder_upload_outlined),
          title: context.tr('backup.local.path'),
          summary: controller.localPath ??
              context.tr('backup.local.pathNotSet'),
          onClick: _pickLocalPath,
        ),

        // ── WebDav ────────────────────────────────────────
        MiuixSmallTitle(context.tr('backup.section.webdav')),
        MiuixSwitchPreference(
          startAction: prefIcon(Icons.cloud_outlined),
          title: context.tr('backup.webdav.enabled'),
          summary: context.tr('backup.webdav.enabledDescription'),
          value: controller.webdavEnabled,
          onChanged: controller.setWebdavEnabled,
        ),
        if (_webdavLoaded) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: EcTextField(
              controller: _webdavUrlController,
              label: context.tr('backup.webdav.url'),
              hint: 'https://dav.example.com/',
              keyboardType: TextInputType.url,
              onChanged: (v) => controller.setWebdavUrl(v.trim()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: EcTextField(
              controller: _webdavUserController,
              label: context.tr('backup.webdav.username'),
              onChanged: (v) => controller.setWebdavUsername(v.trim()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: EcTextField(
              controller: _webdavPassController,
              label: context.tr('backup.webdav.password'),
              obscureText: true,
              onChanged: (v) => controller.setWebdavPassword(v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: EcTextField(
              controller: _webdavPathController,
              label: context.tr('backup.webdav.remotePath'),
              hint: '/EdgeCube',
              onChanged: (v) => controller.setWebdavRemotePath(
                v.trim().isEmpty ? '/EdgeCube' : v.trim(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: MiuixButton(
              onPressed: _testWebdav,
              child: MiuixText(context.tr('backup.webdav.test')),
            ),
          ),
        ],

        // ── 保留 ──────────────────────────────────────────
        MiuixSmallTitle(context.tr('backup.section.retention')),
        MiuixArrowPreference(
          startAction: prefIcon(Icons.cleaning_services_outlined),
          title: context.tr('backup.retention.title'),
          summary:
              '${controller.retentionSets}${context.tr('backup.retention.sets')}',
          onClick: _pickRetention,
        ),

        // ── 操作 ──────────────────────────────────────────
        MiuixSmallTitle(context.tr('backup.section.actions')),
        MiuixBasicComponent(
          startAction: prefIcon(Icons.backup_outlined),
          title: context.tr('backup.now'),
          summary:
              "${context.tr('backup.lastBackup')}${_lastBackupLabel(context, controller)}",
          onClick: controller.isRunning ? null : _backupNow,
          endActions: [
            if (controller.isRunning)
              const MiuixInfiniteProgressIndicator(size: 22)
            else
              MiuixButton(
                onPressed: _backupNow,
                insideMargin:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                minWidth: 0,
                minHeight: 0,
                child: MiuixText(
                  context.tr('backup.now'),
                  style: theme.textStyles.button,
                ),
              ),
          ],
        ),
        if (controller.isRunning && controller.totalCount > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: MiuixText(
              context.tr('backup.progress', {
                'current': '${controller.processedCount}',
                'total': '${controller.totalCount}',
                'name': controller.currentInstanceName,
              }),
              style: theme.textStyles.footnote1,
              color: theme.colors.onSurfaceVariantSummary,
            ),
          ),
      ],
    );
  }
}
