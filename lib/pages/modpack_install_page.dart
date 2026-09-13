import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../files/storage_permission.dart';
import '../files/system_picker.dart';
import '../i18n/locale_scope.dart';
import '../instance/instance.dart';
import '../instance/instance_controller.dart';
import '../instance/instance_scope.dart';
import '../instance/progress_steps.dart';
import '../mods/modpack_service.dart';
import '../server/server_service.dart';
import '../widgets/ec_preference.dart';
import '../widgets/error_dialog.dart';
import '../widgets/instance_picker_page.dart';
import '../widgets/miuix_dialog.dart';
import '../widgets/miuix_snackbar.dart';
import '../widgets/placeholder_page.dart';

/// 「整合包导入」页：把 Modrinth 整合包（.mrpack，或含清单的 zip）导入**已有实例**。
///
/// 与新建实例向导里的整合包导入不同，这里不创建实例、也不替换服务端 jar：
/// 只把清单里服务端需要的模组下载到实例目录，并展开 overrides 覆盖文件
/// （配置、默认地图等）。因此需要用户自行保证现有服务端的版本 / 加载器与整合包一致。
class InstallModpackPage extends StatefulWidget {
  const InstallModpackPage({super.key});

  @override
  State<InstallModpackPage> createState() => _InstallModpackPageState();
}

class _InstallModpackPageState extends State<InstallModpackPage> {
  InstanceController? _controller;
  String? _loadedInstanceId;
  Instance? _instance;
  Directory? _instanceDir;

  /// 导入进行中（含解析 / 下载 / 解压三个阶段）。
  bool _busy = false;
  String _phase = '';
  int _current = 0;
  int _total = 0;
  String _currentFile = '';
  bool _cancelRequested = false;
  List<ModDownloadTask> _tasks = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = InstanceScope.of(context);
    if (controller != _controller) {
      _controller?.removeListener(_onControllerChanged);
      _controller = controller;
      _controller?.addListener(_onControllerChanged);
    }
    _onControllerChanged();
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    final id = _controller?.selected?.id;
    if (id == _loadedInstanceId) return;
    _loadedInstanceId = id;
    // didChangeDependencies 阶段不能同步 setState，挪到当前帧结束后再加载。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final controller = _controller;
    if (controller == null) return;
    final instance = controller.selected;
    final dir = instance == null
        ? null
        : await controller.directoryFor(instance);
    if (!mounted) return;
    setState(() {
      _instance = instance;
      _instanceDir = dir;
    });
  }

  Future<void> _pickAndInstall() async {
    final dir = _instanceDir;
    if (dir == null) return;
    if (!await _requireServerStopped()) return;
    if (!await _ensurePermission()) return;
    if (!mounted) return;

    final sourcePath = await pickFromSystem(
      context,
      mode: SystemPickMode.file,
      allowedExtensions: const ['.mrpack', '.zip'],
    );
    if (sourcePath == null || !mounted) return;

    setState(() {
      _busy = true;
      _phase = 'parsing';
      _cancelRequested = false;
      _current = 0;
      _total = 0;
      _currentFile = '';
      _tasks = const [];
    });

    try {
      final modpack = await ModpackService.detectAndParse(sourcePath);
      if (!mounted) return;
      if (modpack == null) {
        setState(() => _busy = false);
        showErrorDialog(context, context.tr('modpackInstall.notAModpack'));
        return;
      }

      final confirmed = await _showConfirm(modpack);
      if (confirmed != true || !mounted) {
        setState(() => _busy = false);
        return;
      }

      setState(() {
        _phase = 'downloading';
        _current = 0;
        _total = modpack.serverFiles.length;
      });
      await ModpackService.downloadServerFiles(
        modpack,
        dir,
        onProgress: (current, total, fileName) {
          if (!mounted) return;
          setState(() {
            _current = current;
            _total = total;
            _currentFile = fileName;
          });
        },
        onTaskUpdate: (tasks) {
          if (!mounted) return;
          setState(() => _tasks = tasks);
        },
        isCancelled: () => _cancelRequested,
      );

      if (!mounted) return;
      if (_cancelRequested) {
        setState(() => _busy = false);
        return;
      }
      setState(() => _phase = 'extracting');
      await ModpackService.extractOverrides(sourcePath, modpack, dir);

      if (!mounted) return;
      setState(() => _busy = false);
      showMiuixSnackbar(context.tr('modpackInstall.success'));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorDialog(
        context,
        context.tr('instance.modpackFailed', {'error': '$e'}),
      );
    }
  }

  Future<bool?> _showConfirm(ParsedModpack modpack) {
    final mc = modpack.dependencies['minecraft'] ?? '-';
    final modCount = modpack.serverFiles.length;
    return showMiuixConfirm(
      context,
      title: context.tr('instance.modpackConfirmTitle'),
      message:
          '${context.tr('instance.modpackSummary', {
            'name': modpack.name ?? '-',
            'mc': mc,
            'loader': _loaderLabel(modpack),
            'count': '$modCount',
          })}\n\n${context.tr('modpackInstall.keepJarNotice')}',
      cancelLabel: context.tr('common.cancel'),
      confirmLabel: context.tr('common.ok'),
    );
  }

  String _loaderLabel(ParsedModpack modpack) {
    final deps = modpack.dependencies;
    if (deps['fabric-loader'] != null) return 'Fabric';
    if (deps['quilt-loader'] != null) return 'Quilt';
    if (deps['forge'] != null) return 'Forge';
    if (deps['neo-forge'] != null || deps['neoforge'] != null) {
      return 'NeoForge';
    }
    if (deps['minecraft'] != null) return context.tr('instance.modpackVanilla');
    return '-';
  }

  Future<void> _switchInstance() async {
    await pickInstance(context, title: context.tr('instancePicker.title'));
    if (mounted) await _load();
  }

  /// 导入会写入 mods / 配置目录，服务端运行中写入会造成文件损坏，先要求停止。
  Future<bool> _requireServerStopped() async {
    if (!await ServerService().isRunning()) return true;
    if (mounted) {
      showErrorDialog(context, context.tr('saveConfig.serverRunning'));
    }
    return false;
  }

  Future<bool> _ensurePermission() async {
    if (!mounted) return false;
    if (await StoragePermission.isGranted()) return true;
    if (!mounted) return false;
    final go = await showMiuixConfirm(
      context,
      title: context.tr('saveConfig.permissionTitle'),
      message: context.tr('saveConfig.permissionContent'),
      cancelLabel: context.tr('common.cancel'),
      confirmLabel: context.tr('saveConfig.grantPermission'),
    );
    if (go == true) {
      await StoragePermission.request();
    }
    if (!mounted) return false;
    return StoragePermission.isGranted();
  }

  @override
  Widget build(BuildContext context) {
    // 下载/解压过程中不允许返回：中途离开会留下不完整的模组文件。
    return PopScope(
      canPop: !_busy,
      child: MiuixScaffold(
        topBar: EcTopAppBar(title: context.tr('modpackInstall.title')),
        content: (padding) => Padding(
          padding: padding,
          // padding.top 已含顶栏（连同状态栏）高度，故 SafeArea 只保留左右与底部。
          child: SafeArea(
            top: false,
            child: _busy ? _buildBusy() : _buildContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildBusy() {
    return ModpackImportStep(
      phase: _phase,
      current: _current,
      total: _total,
      currentFile: _currentFile,
      error: null,
      // 下载阶段可取消：置标志后由 downloadServerFiles 的在途回调尽快收尾。
      onCancel: () {
        if (_phase != 'downloading') return;
        setState(() => _cancelRequested = true);
      },
      tasks: _tasks,
    );
  }

  Widget _buildContent() {
    final instance = _instance;
    if (instance == null) {
      return PlaceholderPage(
        icon: Icons.extension_outlined,
        title: context.tr('modpackInstall.emptyTitle'),
        description: context.tr('modpackInstall.emptyDescription'),
      );
    }
    final theme = MiuixTheme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            context.tr('modpackInstall.intro'),
            style: theme.textStyles.body2.copyWith(
              color: theme.colors.onSurfaceVariantSummary,
            ),
          ),
        ),
        EcCardTile(
          leading: const Icon(Icons.dns_outlined, size: 36),
          title: instance.name,
          summary: context.tr('modpackInstall.targetInstance'),
          trailing: [
            MiuixTextButton(
              context.tr('saveConfig.switchInstance'),
              onPressed: _switchInstance,
            ),
          ],
          onTap: _switchInstance,
        ),
        EcCardTile(
          leading: const Icon(Icons.file_download_outlined, size: 36),
          title: context.tr('modpackInstall.choose'),
          summary: context.tr('modpackInstall.chooseSubtitle'),
          onTap: _pickAndInstall,
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            context.tr('modpackInstall.keepJarNotice'),
            style: theme.textStyles.footnote1.copyWith(
              color: theme.colors.onSurfaceVariantSummary,
            ),
          ),
        ),
      ],
    );
  }
}
