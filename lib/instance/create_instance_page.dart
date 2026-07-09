import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../files/archive_service.dart';
import '../files/file_service.dart';
import '../files/storage_permission.dart';
import '../files/system_picker.dart';
import '../i18n/locale_scope.dart';
import '../instance/instance.dart';
import '../instance/instance_controller.dart';
import '../instance/instance_scope.dart';
import '../mods/modpack_service.dart';
import 'create_download_edition_page.dart';
import 'create_download_install_loader_page.dart';
import 'download_info.dart';
import 'download_runner.dart';
import 'download_session.dart';
import 'name_entry_step.dart';
import 'progress_steps.dart';

/// 向导中除「下载服务端」外的步骤。
///
/// 「下载服务端」流程已拆分为独立的 push 页面（见 create_download_*.dart），
/// 由 [_goToDownloadFlow] 进入；此处仅保留名称输入、导入与整合包导入等步骤。
enum _WizardStep {
  nameEntry,
  importFile,
  importArchive,
  extractArchive,
  modpackImport,
}

/// 新建实例向导结果。
enum CreateInstanceResult { done, cancelled }

/// 新建实例向导页。
///
/// 流程：
/// 1. 输入名称 → 选择「下载服务端」或「导入服务端」/「导入压缩包」/「导入整合包」
/// 2a. 下载服务端 → push 独立的下载流程页（选类型 → 分类 → 服务端 → 版本 →
///     加载器版本 → 下载/安装），完成后一次性弹回本页。
/// 2b. 导入服务端 → 创建实例 → 选文件导入
/// 2c. 导入压缩包 → 创建实例 → 选压缩包解压
/// 2d. 导入整合包 → 创建实例 → 解析并安装
///
/// 如果用户中途退出（未完成）导入类流程，自动删除已创建的空实例。
class CreateInstancePage extends StatefulWidget {
  const CreateInstancePage({super.key});

  @override
  State<CreateInstancePage> createState() => _CreateInstancePageState();
}

class _CreateInstancePageState extends State<CreateInstancePage> {
  static const _fileService = FileService();

  _WizardStep _step = _WizardStep.nameEntry;
  final _nameController = TextEditingController();

  /// 导入类流程创建的实例 id（下载流程的实例由其页面自行管理，不在此记录）。
  String? _instanceId;
  bool _completed = false;

  bool _extracting = false;
  String? _extractError;
  double? _extractProgress;

  /// 整合包导入状态。
  String _modpackPhase =
      ''; // parsing / downloading / extracting / preparing / idle
  int _modpackCurrent = 0;
  int _modpackTotal = 0;
  String _modpackCurrentFile = '';
  String? _modpackError;

  /// 整合包 Vanilla 服务端下载所需的版本详情 URL 映射。
  Map<String, String> _vanillaVersionUrls = {};

  late InstanceController _instanceController;

  @override
  void initState() {
    super.initState();
    _instanceController = InstanceScope.of(context);
    _nameController.text = context.tr('instance.defaultName');
  }

  @override
  void dispose() {
    _nameController.dispose();
    // 如果向导未完成且已创建了实例（导入类流程），清理空实例。
    if (!_completed && _instanceId != null) {
      _instanceController.deleteInstance(_instanceId!);
    }
    super.dispose();
  }

  // —— 名称校验 ——

  /// 校验名称：非空且不重名。空或重复时弹出提示对话框。
  Future<bool> _validateName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      await _showNameEmptyDialog();
      return false;
    }
    if (_instanceController.instances.any((i) => i.name == name)) {
      await _showDuplicateDialog(name);
      return false;
    }
    return _ensureInstanceStoragePermission();
  }

  Future<bool> _ensureInstanceStoragePermission() async {
    if (await StoragePermission.isGranted()) return true;
    if (!mounted) return false;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('instance.storagePermissionTitle')),
        content: Text(ctx.tr('instance.createStoragePermissionMessage')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.tr('instance.goGrant')),
          ),
        ],
      ),
    );
    if (go != true) return false;
    await StoragePermission.request();
    return false;
  }

  // —— 进入下载服务端流程 ——

  /// 校验名称后进入独立的「下载服务端」流程（push 到「选择类型」页）。
  ///
  /// 该流程的实例创建/清理由各下载页自行负责；完成时通过 [finishDownloadFlow]
  /// 一次性弹回本页并返回 [CreateInstanceResult.done]，此处随即关闭向导。
  Future<void> _goToDownloadFlow() async {
    if (!await _validateName()) return;
    if (!mounted) return;
    final session = DownloadSession(
      controller: _instanceController,
      name: _nameController.text.trim(),
    );
    final result = await Navigator.of(context).push<CreateInstanceResult>(
      MaterialPageRoute(
        settings: const RouteSettings(name: kDownloadFlowRootRouteName),
        builder: (_) => SelectEditionPage(session: session),
      ),
    );
    if (result == CreateInstanceResult.done && mounted) {
      _completed = true;
      _finishWizard();
    }
  }

  // —— 导入服务端（jar/phar）——

  Future<void> _startImport() async {
    if (!await _validateName()) return;
    final name = _nameController.text.trim();
    try {
      final instance = await _instanceController.createInstance(name);
      if (!mounted) return;
      _instanceId = instance.id;
      setState(() => _step = _WizardStep.importFile);
      _doImport(instance.id);
    } on DuplicateInstanceNameException {
      if (!mounted) return;
      _showDuplicateDialog(name);
    }
  }

  Future<void> _doImport(String instanceId) async {
    // 确保有文件访问权限。
    if (!await StoragePermission.isGranted()) {
      if (!mounted) return;
      final go = await _showImportPermissionDialog();
      if (go != true) {
        _closeWizard();
        return;
      }
      await StoragePermission.request();
      if (!mounted) return;
      _doImport(instanceId);
      return;
    }

    if (!mounted) return;
    final sourcePath = await pickFromSystem(
      context,
      mode: SystemPickMode.file,
      allowedExtensions: const ['.jar', '.phar'],
    );
    if (sourcePath == null) {
      // 用户取消选择，关闭向导（dispose 会自动清理空实例）。
      _closeWizard();
      return;
    }
    try {
      final dir = await _instanceController.directoryForId(instanceId);
      final savedPath = await _fileService.importFile(sourcePath, dir);
      final jarName = p.basename(savedPath);
      // 导入 .phar 时自动切到 PHP（PocketMine）运行环境，其余按 Java 处理。
      final isPhar = jarName.toLowerCase().endsWith('.phar');
      await _instanceController.updateConfig(
        instanceId,
        selectedJar: jarName,
        runtime: isPhar ? kRuntimePhp : kRuntimeJava,
      );
      _completed = true;
      _finishWizard();
    } catch (_) {
      _closeWizard();
    }
  }

  // —— 导入压缩包 ——

  Future<void> _startImportArchive() async {
    if (!await _validateName()) return;
    final name = _nameController.text.trim();
    try {
      final instance = await _instanceController.createInstance(name);
      if (!mounted) return;
      _instanceId = instance.id;
      setState(() => _step = _WizardStep.importArchive);
      _doImportArchive(instance.id);
    } on DuplicateInstanceNameException {
      if (!mounted) return;
      _showDuplicateDialog(name);
    }
  }

  Future<void> _doImportArchive(String instanceId) async {
    if (!await StoragePermission.isGranted()) {
      if (!mounted) return;
      final go = await _showImportPermissionDialog();
      if (go != true) {
        _closeWizard();
        return;
      }
      await StoragePermission.request();
      if (!mounted) return;
      _doImportArchive(instanceId);
      return;
    }

    if (!mounted) return;
    final sourcePath = await pickFromSystem(
      context,
      mode: SystemPickMode.file,
      // 与原生 ArchiveExtractor 支持的格式保持一致。
      allowedExtensions: const [
        '.zip',
        '.tar',
        '.tar.gz',
        '.tgz',
        '.tar.xz',
        '.txz',
        '.tar.bz2',
        '.tbz2',
        '.tar.zst',
        '.tzst',
        '.tar.lz4',
        '.7z',
      ],
    );
    if (sourcePath == null) {
      _closeWizard();
      return;
    }

    setState(() {
      _step = _WizardStep.extractArchive;
      _extracting = true;
      _extractError = null;
      _extractProgress = null;
    });

    try {
      final dir = await _instanceController.directoryForId(instanceId);
      await ArchiveService.extractWithProgress(
        sourcePath,
        dir.path,
        onProgress: (current, total) {
          if (!mounted) return;
          setState(() {
            _extractProgress = total > 0 ? current / total : null;
          });
        },
      );

      _completed = true;
      if (mounted) {
        setState(() {
          _extracting = false;
          _extractProgress = null;
        });
        _finishWizard();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _extracting = false;
        _extractProgress = null;
        _extractError = context.tr('instance.extractArchiveFailed', {
          'error': '$e',
        });
      });
    }
  }

  // —— 创建空实例 ——

  /// 创建空实例：不下载/导入任何 jar，直接完成向导。
  Future<void> _createEmptyInstance() async {
    if (!await _validateName()) return;
    final name = _nameController.text.trim();
    try {
      final instance = await _instanceController.createInstance(name);
      _instanceId = instance.id;
      _completed = true;
      _finishWizard();
    } on DuplicateInstanceNameException {
      if (!mounted) return;
      _showDuplicateDialog(name);
    }
  }

  // —— 整合包导入流程 ——
  // 参考 PCL-CE 的 ModModpack.ModpackInstall / InstallPackModrinth：
  // 1. 选择整合包文件 → 2. 检测格式 → 3.（Modrinth）解析清单 →
  //    4. 确认 → 5. 下载服务端 mod → 6. 解压 overrides → 7. 下载服务端 jar。
  // 普通 zip：直接解压到实例目录后完成。

  Future<void> _startModpackImport() async {
    if (!await _validateName()) return;
    final name = _nameController.text.trim();
    try {
      final instance = await _instanceController.createInstance(name);
      if (!mounted) return;
      _instanceId = instance.id;
      setState(() {
        _step = _WizardStep.modpackImport;
        _modpackPhase = '';
        _modpackError = null;
      });
      await _doModpackImport(instance.id);
    } on DuplicateInstanceNameException {
      if (!mounted) return;
      _showDuplicateDialog(name);
    }
  }

  Future<void> _doModpackImport(String instanceId) async {
    // 文件访问权限。
    if (!await StoragePermission.isGranted()) {
      if (!mounted) return;
      final go = await _showImportPermissionDialog();
      if (go != true) {
        _deleteCreatedInstance();
        _closeWizard();
        return;
      }
      await StoragePermission.request();
      if (!mounted) return;
      _doModpackImport(instanceId);
      return;
    }

    // 选择整合包文件。
    if (!mounted) return;
    final sourcePath = await pickFromSystem(
      context,
      mode: SystemPickMode.file,
      allowedExtensions: const ['.mrpack', '.zip'],
    );
    if (sourcePath == null) {
      _deleteCreatedInstance();
      _closeWizard();
      return;
    }

    setState(() => _modpackPhase = 'parsing');
    try {
      final format = await ModpackService.detectFormat(sourcePath);
      if (format == ModpackFormat.plainZip) {
        // 普通 zip：直接解压到实例目录后完成。
        await _extractPlainZip(instanceId, sourcePath);
        return;
      }

      // Modrinth：解析清单。
      final modpack = await ModpackService.parseModrinth(sourcePath);
      if (!mounted) return;

      // 确认对话框。
      final confirmed = await _showModpackConfirm(modpack);
      if (confirmed != true) {
        _deleteCreatedInstance();
        _closeWizard();
        return;
      }

      final dir = await _instanceController.directoryForId(instanceId);

      // 下载服务端 mod 文件。
      setState(() {
        _modpackPhase = 'downloading';
        _modpackCurrent = 0;
        _modpackTotal = modpack.serverFiles.length;
        _modpackError = null;
      });
      await ModpackService.downloadServerFiles(
        modpack,
        dir,
        onProgress: (current, total, fileName) {
          if (!mounted) return;
          setState(() {
            _modpackCurrent = current;
            _modpackTotal = total;
            _modpackCurrentFile = fileName;
          });
        },
      );

      // 解压 overrides。
      if (!mounted) return;
      setState(() {
        _modpackPhase = 'extracting';
        _modpackError = null;
      });
      await ModpackService.extractOverrides(sourcePath, dir);

      // 下载服务端 jar。
      if (!mounted) return;
      setState(() => _modpackPhase = 'preparing');
      await _downloadServerJarFromModpack(instanceId, modpack);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _modpackError = context.tr('instance.modpackFailed', {'error': '$e'});
      });
    }
  }

  /// 普通 zip 整合包：解压到实例目录后完成（与导入压缩包行为一致）。
  Future<void> _extractPlainZip(String instanceId, String sourcePath) async {
    setState(() {
      _modpackPhase = 'extracting';
      _modpackError = null;
    });
    try {
      final dir = await _instanceController.directoryForId(instanceId);
      await ArchiveService.extractWithProgress(
        sourcePath,
        dir.path,
        onProgress: (current, total) {
          if (!mounted) return;
          setState(() {
            _extractProgress = total > 0 ? current / total : null;
          });
        },
      );
      _completed = true;
      if (mounted) {
        setState(() {
          _extracting = false;
          _extractProgress = null;
        });
        _finishWizard();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _modpackError = context.tr('instance.extractArchiveFailed', {
          'error': '$e',
        });
      });
    }
  }

  /// 根据整合包 dependencies 下载对应服务端 jar，复用共享下载逻辑。
  Future<void> _downloadServerJarFromModpack(
    String instanceId,
    ModrinthModpack modpack,
  ) async {
    final deps = modpack.dependencies;
    final mcVersion = deps['minecraft'];
    if (mcVersion == null || mcVersion.isEmpty) {
      // 无 MC 版本信息，无法自动下载服务端，直接完成。
      _completed = true;
      if (mounted) _finishWizard();
      return;
    }

    final fabricLoader = deps['fabric-loader'];
    final forge = deps['forge'];
    final neoforge = deps['neo-forge'] ?? deps['neoforge'];
    final quiltLoader = deps['quilt-loader'];

    if (fabricLoader != null) {
      await _modpackDownloadJar(
        instanceId,
        serverType: 'fabric',
        info: await DownloadRunner.tryMirrorDownloadInfo('fabric', mcVersion) ??
            await DownloadRunner.fetchFabricDownloadInfo(
                mcVersion, fabricLoader),
        selectedMcVersion: mcVersion,
      );
    } else if (forge != null) {
      await _modpackInstallLoader(
        instanceId,
        installerType: 'forge',
        mcVersion: mcVersion,
        loaderVersion: forge,
      );
    } else if (neoforge != null) {
      await _modpackInstallLoader(
        instanceId,
        installerType: 'neoforge',
        mcVersion: _deriveNeoforgeMcKey(neoforge),
        loaderVersion: neoforge,
      );
    } else if (quiltLoader != null) {
      // Quilt 无独立服务端下载流程：Fabric 兼容，下载 Fabric 服务端。
      await _modpackDownloadJar(
        instanceId,
        serverType: 'fabric',
        info: await DownloadRunner.tryMirrorDownloadInfo('fabric', mcVersion) ??
            await DownloadRunner.fetchFabricDownloadInfo(
                mcVersion, quiltLoader),
        selectedMcVersion: mcVersion,
      );
    } else {
      // Vanilla 服务端：先填充版本详情 URL 映射。
      try {
        final r = await DownloadRunner.fetchVanillaVersions();
        _vanillaVersionUrls = r.urls;
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _modpackError = context.tr('instance.fetchVersionsFailed', {
            'error': '$e',
          });
        });
        return;
      }
      await _modpackDownloadJar(
        instanceId,
        serverType: 'vanilla',
        info: await DownloadRunner.tryMirrorDownloadInfo('vanilla', mcVersion) ??
            await DownloadRunner.fetchVanillaDownloadInfo(
                mcVersion, _vanillaVersionUrls),
        selectedVersion: mcVersion,
      );
    }
  }

  /// 整合包场景下载服务端 jar（复用 DownloadRunner，保持在整合包进度页）。
  Future<void> _modpackDownloadJar(
    String instanceId, {
    required String serverType,
    required DownloadInfo info,
    String? selectedVersion,
    String? selectedMcVersion,
  }) async {
    try {
      await DownloadRunner.downloadAndConfigure(
        controller: _instanceController,
        instanceId: instanceId,
        info: info,
        serverType: serverType,
        selectedVersion: selectedVersion,
        selectedMcVersion: selectedMcVersion,
      );
      _completed = true;
      if (mounted) _finishWizard();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _modpackError = context.tr('instance.downloadFailed', {'error': '$e'});
      });
    }
  }

  /// 整合包场景安装 Forge/NeoForge 加载器（push 到安装页）。
  Future<void> _modpackInstallLoader(
    String instanceId, {
    required String installerType,
    required String mcVersion,
    required String loaderVersion,
  }) async {
    if (!mounted) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => InstallLoaderPage(
          instanceController: _instanceController,
          instanceId: instanceId,
          mcVersion: mcVersion,
          loaderVersion: loaderVersion,
          installerType: installerType,
        ),
      ),
    );
    if (result == true && mounted) {
      _completed = true;
      _finishWizard();
    }
  }

  /// 由 NeoForge 版本号推导 MC 版本键（与 fetchAllNeoforgeVersions 分组规则一致）。
  /// 三段式 "21.1.234" → "21.1"；四段式 "26.1.2.71" → "26.1.2"。
  String _deriveNeoforgeMcKey(String nfVersion) {
    final parts = nfVersion.split('-').first.split('.');
    if (parts.length >= 4) return '${parts[0]}.${parts[1]}.${parts[2]}';
    if (parts.length >= 2) return '${parts[0]}.${parts[1]}';
    return nfVersion;
  }

  Future<bool?> _showModpackConfirm(ModrinthModpack modpack) {
    final mc = modpack.dependencies['minecraft'] ?? '-';
    final loader = _modpackLoaderLabel(modpack);
    final modCount = modpack.serverFiles.length;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('instance.modpackConfirmTitle')),
        content: Text(
          ctx.tr('instance.modpackSummary', {
            'name': modpack.name ?? '-',
            'mc': mc,
            'loader': loader,
            'count': '$modCount',
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.tr('common.ok')),
          ),
        ],
      ),
    );
  }

  String _modpackLoaderLabel(ModrinthModpack modpack) {
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

  // —— 对话框 ——

  Future<bool?> _showImportPermissionDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('instance.storagePermissionTitle')),
        content: Text(ctx.tr('instance.importStoragePermissionMessage')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.tr('instance.goGrant')),
          ),
        ],
      ),
    );
  }

  Future<void> _showDuplicateDialog(String name) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('instance.noticeTitle')),
        content: Text(ctx.tr('instance.duplicateName', {'name': name})),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.tr('common.ok')),
          ),
        ],
      ),
    );
  }

  Future<void> _showNameEmptyDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('instance.noticeTitle')),
        content: Text(ctx.tr('instance.nameEmpty')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.tr('common.ok')),
          ),
        ],
      ),
    );
  }

  // —— 导航收尾 ——

  void _onBack() {
    switch (_step) {
      case _WizardStep.nameEntry:
        _closeWizard();
      case _WizardStep.importFile:
      case _WizardStep.importArchive:
      case _WizardStep.modpackImport:
        _deleteCreatedInstance();
        _closeWizard();
      case _WizardStep.extractArchive:
        break;
    }
  }

  void _closeWizard() {
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop(CreateInstanceResult.cancelled);
    }
  }

  void _finishWizard() {
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop(CreateInstanceResult.done);
    }
  }

  void _deleteCreatedInstance() {
    if (_instanceId != null) {
      _instanceController.deleteInstance(_instanceId!);
      _instanceId = null;
    }
  }

  // —— UI 构建 ——

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _onBack,
          ),
          title: Text(_appBarTitle),
        ),
        body: SafeArea(child: _buildStepContent(theme)),
      ),
    );
  }

  String get _appBarTitle {
    return switch (_step) {
      _WizardStep.nameEntry => context.tr('instance.titleNameEntry'),
      _WizardStep.importFile => context.tr('instance.titleImportServer'),
      _WizardStep.importArchive => context.tr('instance.titleImportServer'),
      _WizardStep.extractArchive => context.tr('instance.titleImportArchive'),
      _WizardStep.modpackImport => context.tr('instance.titleModpackImport'),
    };
  }

  Widget _buildStepContent(ThemeData theme) {
    return switch (_step) {
      _WizardStep.nameEntry => _buildNameEntry(theme),
      _WizardStep.importFile => _buildImporting(theme),
      _WizardStep.importArchive => _buildImporting(theme),
      _WizardStep.extractArchive => _buildExtractingArchive(theme),
      _WizardStep.modpackImport => _buildModpackImport(theme),
    };
  }

  Widget _buildNameEntry(ThemeData theme) {
    return NameEntryStep(
      controller: _nameController,
      showBungeeCordTile: false,
      onGoToServerType: _goToDownloadFlow,
      onStartImport: _startImport,
      onStartArchive: _startImportArchive,
      onStartModpack: _startModpackImport,
      onCreateBungeeCord: () {},
      onCreateEmpty: _createEmptyInstance,
    );
  }

  Widget _buildImporting(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(
            context.tr('instance.selectJarPrompt'),
            style: theme.textTheme.titleMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildExtractingArchive(ThemeData theme) {
    return ExtractingArchiveStep(
      extracting: _extracting,
      progress: _extractProgress,
      error: _extractError,
      onCancel: _deleteCreatedInstance,
      onReselect: () {
        _deleteCreatedInstance();
        setState(() {
          _extractError = null;
          _extractProgress = null;
          _extracting = false;
          _step = _WizardStep.nameEntry;
        });
      },
    );
  }

  /// 整合包导入进度页。
  Widget _buildModpackImport(ThemeData theme) {
    return ModpackImportStep(
      phase: _modpackPhase,
      current: _modpackCurrent,
      total: _modpackTotal,
      currentFile: _modpackCurrentFile,
      error: _modpackError,
      onCancel: _deleteCreatedInstance,
    );
  }
}
