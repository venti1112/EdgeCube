import 'dart:io';

import 'package:flutter/material.dart';

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
import '../widgets/miuix_dialog.dart';
import '../widgets/miuix_snackbar.dart';
import '../widgets/modpack_install_ui.dart';
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
    return showModpackConfirmDialog(
      context,
      modpack,
      extraNotice: context.tr('modpackInstall.keepJarNotice'),
    );
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
    return ModpackInstallScaffold(
      title: context.tr('modpackInstall.title'),
      busy: _busy,
      busyView: _buildBusy(),
      content: _buildContent(),
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
    if (_instance == null) {
      return PlaceholderPage(
        icon: Icons.extension_outlined,
        title: context.tr('modpackInstall.emptyTitle'),
        description: context.tr('modpackInstall.emptyDescription'),
      );
    }
    return ModpackActionList(
      intro: context.tr('modpackInstall.intro'),
      footnote: context.tr('modpackInstall.keepJarNotice'),
      actions: [
        EcCardTile(
          leading: const Icon(Icons.file_download_outlined, size: 36),
          title: context.tr('modpackInstall.choose'),
          summary: context.tr('modpackInstall.chooseSubtitle'),
          onTap: _pickAndInstall,
        ),
      ],
    );
  }
}
