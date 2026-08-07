import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../config/developer_options_store.dart';
import '../files/storage_permission.dart';
import '../files/system_picker.dart';
import '../i18n/locale_scope.dart';
import '../widgets/error_dialog.dart';
import '../widgets/loading_dialog.dart';
import '../net/download_format.dart';
import '../server/ecpkg_handler.dart';
import '../server/proot_service.dart';
import '../server/runtime_service.dart';
import '../server/runtime_update_service.dart';
import '../server/signature_verify_result.dart';
import '../widgets/ec_preference.dart';
import '../widgets/ec_text_field.dart';
import '../widgets/miuix_dialog.dart';
import '../widgets/miuix_snackbar.dart';
import 'container_files_page.dart';
import 'ecpkg_download_page.dart';

/// 「运行环境」管理页：列出已安装运行时，导入/删除/更新 .ecpkg。
///
/// 也管理 proot rootfs：支持导入裸 tar 压缩包与 ZIP 包装包
/// （`.zip` / `.ecpkg`，内含 rootfs.tar.zst）。
class RuntimePage extends StatefulWidget {
  const RuntimePage({super.key, this.initialEcpkgPath});

  /// 从文件关联打开时传入的 .ecpkg 文件路径。
  final String? initialEcpkgPath;

  @override
  State<RuntimePage> createState() => _RuntimePageState();
}

class _RuntimePageState extends State<RuntimePage> {
  final _service = const RuntimeService();
  final _prootService = const ProotService();
  List<RuntimeInfo> _runtimes = [];
  List<ProotRootfsInfo> _prootRootfs = [];
  bool _prootAvailable = false;
  bool _loading = true;
  bool _importing = false;
  bool _importingRootfs = false;

  @override
  void initState() {
    super.initState();
    _load();
    EcpkgHandler.onOpenEcpkg = _handleOpenEcpkg;
    RuntimeService.refreshSignal.addListener(_onRuntimesChanged);
    ProotService.refreshSignal.addListener(_onRuntimesChanged);
    // 处理从文件关联传入的路径
    if (widget.initialEcpkgPath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleOpenEcpkg(widget.initialEcpkgPath!);
      });
    }
  }

  @override
  void dispose() {
    RuntimeService.refreshSignal.removeListener(_onRuntimesChanged);
    ProotService.refreshSignal.removeListener(_onRuntimesChanged);
    super.dispose();
  }

  void _onRuntimesChanged() {
    if (mounted) _load();
  }

  Future<void> _handleOpenEcpkg(String path) async {
    if (!mounted) return;
    if (!path.toLowerCase().endsWith('.ecpkg')) {
      showErrorDialog(context, context.tr('runtime.notEcpkg'));
      return;
    }
    // .ecpkg 也可能是 rootfs 包（ZIP 内含 rootfs.tar.zst），先探测再路由。
    final isRootfs = await _prootService.isRootfsPackage(path);
    if (!mounted) return;
    if (isRootfs) {
      await _importRootfsFromPath(path);
    } else {
      _doImport(path);
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await _service.installedRuntimes();
      // proot rootfs 与可用性并行加载，任一失败不影响另一个
      final results = await Future.wait([
        _prootService.listRootfs().catchError((_) => <ProotRootfsInfo>[]),
        _prootService.isAvailable().catchError((_) => false),
      ]);
      if (!mounted) return;
      setState(() {
        _runtimes = list;
        _prootRootfs = results[0] as List<ProotRootfsInfo>;
        _prootAvailable = results[1] as bool;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 确保存储权限已授予；未授予时弹出确认对话框引导用户授权。
  /// 返回 true 表示权限已就绪，可以继续后续文件选择。
  Future<bool> _ensureStoragePermission() async {
    if (await StoragePermission.isGranted()) return true;
    if (!mounted) return false;
    final go = await showMiuixConfirm(
      context,
      title: context.tr('fileBrowser.permissionTitle'),
      message: context.tr('fileBrowser.permissionContent'),
      cancelLabel: context.tr('common.cancel'),
      confirmLabel: context.tr('fileBrowser.grantPermission'),
    );
    if (go != true) return false;
    await StoragePermission.request();
    if (!mounted) return false;
    return _ensureStoragePermission();
  }

  /// 统一导入入口：选择文件后根据包类型自动路由到运行时或 rootfs 导入流程。
  ///
  /// 支持的文件格式：
  /// - `.ecpkg` / `.zip`：通过 [ProotService.isRootfsPackage] 探测包清单
  ///   `edgecube-package.json` 的 `type` 字段（`proot` → rootfs，其他 → 运行时）。
  /// - 裸 tar 压缩包（`.tar.zst` / `.tar.xz` / `.tar.gz` / `.tgz`）：直接走 rootfs 导入。
  Future<void> _importUnified() async {
    if (!await _ensureStoragePermission()) return;
    if (!mounted) return;

    final path = await pickFromSystem(
      context,
      mode: SystemPickMode.file,
      allowedExtensions: const [
        '.ecpkg',
        '.zip',
        '.tar.zst',
        '.tar.xz',
        '.tar.gz',
        '.tgz',
      ],
    );
    if (path == null || !mounted) return;

    // 探测包类型并路由：rootfs 包走 proot 流程，其余走运行时流程。
    final isRootfs = await _prootService.isRootfsPackage(path);
    if (!mounted) return;
    if (isRootfs) {
      if (!_prootAvailable) {
        showErrorDialog(context, context.tr('runtime.proot.notAvailable'));
        return;
      }
      await _importRootfsFromPath(path);
    } else {
      if (!path.toLowerCase().endsWith('.ecpkg')) {
        showErrorDialog(context, context.tr('runtime.notEcpkg'));
        return;
      }
      await _doImport(path);
    }
  }

  /// 验证包签名，根据验证模式和开发者选项决定是否允许导入。
  ///
  /// 返回 `true` 表示可以继续导入（签名有效，或警告模式下用户确认继续）；
  /// 返回 `false` 表示应中止导入（严格模式下签名无效/无签名，或用户取消）。
  Future<bool> _checkSignature(SignatureVerifyResult result) async {
    if (result.isTrusted) return true;

    final tr = LocaleScope.of(context).translations;
    final devMode = await DeveloperOptionsStore.loadEnabled();

    if (!devMode) {
      // 严格模式：拒绝导入
      if (!mounted) return false;
      await showMiuixDialog<void>(
        context: context,
        title: tr.get('runtime.signature.warningTitle'),
        builder: (ctx) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              result.hasSignature
                  ? tr.get('runtime.signature.invalid')
                  : tr.get('runtime.signature.noSignature'),
            ),
            const SizedBox(height: 20),
            MiuixDialogActions(
              children: [
                MiuixTextButton(
                  tr.get('common.close'),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
          ],
        ),
      );
      return false;
    }

    // 警告模式：提示用户选择
    if (!mounted) return false;
    final confirmed = await showMiuixConfirm(
      context,
      title: tr.get('runtime.signature.warningTitle'),
      message: result.hasSignature
          ? tr.get('runtime.signature.warningInvalid')
          : tr.get('runtime.signature.warningNoSig'),
      cancelLabel: tr.get('common.cancel'),
      confirmLabel: tr.get('runtime.signature.continueAnyway'),
    );
    return confirmed == true;
  }

  Future<void> _doImport(String path, {bool force = false}) async {
    final tr = LocaleScope.of(context).translations;
    setState(() => _importing = true);
    try {
      // 导入前验证签名
      final sigResult = await runWithLoadingDialog(
        context,
        tr.get('runtime.signature.verifying'),
        () => _service.verifyEcpkgSignature(path),
      );
      if (!await _checkSignature(sigResult)) return;
      if (!mounted) return;

      await runWithLoadingDialog(
        context,
        tr.get('runtime.importing'),
        () => _service.importPackage(path, force: force),
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      showMiuixSnackbar(tr.get('runtime.importSuccess'));
    } on PlatformException catch (e) {
      if (!mounted) return;
      if (e.code == 'IMPORT_FAILED' &&
          e.message?.contains('RUNTIME_EXISTS') == true &&
          !force) {
        final confirmed = await showMiuixConfirm(
          context,
          title: tr.get('runtime.importConfirmTitle'),
          message: tr.get('runtime.importConfirmContent'),
          cancelLabel: tr.get('common.cancel'),
          confirmLabel: tr.get('common.replace'),
        );
        if (confirmed == true) {
          await _doImport(path, force: true);
        }
        return;
      }
      showErrorDialog(
        context,
        tr.get('runtime.importFailed', {'error': '${e.message}'}),
      );
    } catch (e) {
      if (!mounted) return;
      showErrorDialog(context, tr.get('runtime.importFailed', {'error': '$e'}));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _delete(RuntimeInfo info) async {
    final tr = LocaleScope.of(context).translations;
    final runtimeRunning = await _service.isRuntimeRunning(info.id);
    if (runtimeRunning) {
      if (!mounted) return;
      showErrorDialog(context, tr.get('runtime.cannotDeleteRunning'));
      return;
    }

    if (!mounted) return;
    final confirmed = await showMiuixConfirm(
      context,
      title: tr.get('runtime.deleteConfirmTitle'),
      message: tr.get('runtime.deleteConfirmContent', {'name': info.name}),
      cancelLabel: tr.get('common.cancel'),
      confirmLabel: tr.get('common.delete'),
    );
    if (confirmed != true || !mounted) return;

    try {
      await runWithLoadingDialog(
        context,
        tr.get('common.deleting'),
        () => _service.deleteRuntime(info.id),
      );
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      showErrorDialog(context, tr.get('runtime.deleteFailed', {'error': '$e'}));
    }
  }

  // —— proot rootfs 导入/删除 ——

  /// 从文件挑选/文件关联得到的路径进入 rootfs 导入：弹名称输入框（默认去扩展名），
  /// 确认后执行导入。文件关联打开 .ecpkg 时路径已在应用缓存/可读目录，无需再请求存储权限。
  Future<void> _importRootfsFromPath(String path) async {
    if (!mounted) return;

    // 始终弹出名称输入框，默认为去掉压缩包扩展名的文件名
    final defaultName = _rootfsNameFromPath(path);
    final id = await _promptForRootfsId(
      title: context.tr('runtime.proot.importRootfsTitle'),
      message: context.tr('runtime.proot.importRootfsMessage'),
      defaultName: defaultName,
    );
    if (id == null || id.isEmpty) return; // 用户取消
    await _doImportRootfs(path, id: id);
  }

  /// 从文件路径推导 rootfs 名称：取 basename 并剥离已知压缩包扩展名。
  String _rootfsNameFromPath(String path) {
    var name = p.basename(path);
    const exts = [
      '.ecpkg',
      '.zip',
      '.tar.zst',
      '.tar.xz',
      '.tar.gz',
      '.tgz',
      '.tar',
    ];
    for (final ext in exts) {
      if (name.toLowerCase().endsWith(ext)) {
        name = name.substring(0, name.length - ext.length);
        break;
      }
    }
    return name;
  }

  Future<void> _doImportRootfs(String path, {required String id}) async {
    setState(() => _importingRootfs = true);
    try {
      // 导入前验证签名
      final sigResult = await runWithLoadingDialog(
        context,
        context.tr('runtime.signature.verifying'),
        () => _prootService.verifyRootfsSignature(path),
      );
      if (!await _checkSignature(sigResult)) return;
      if (!mounted) return;

      await runWithLoadingDialog(
        context,
        context.tr('runtime.importing'),
        () => _prootService.importRootfs(path, id: id),
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      showMiuixSnackbar(context.tr('runtime.proot.importRootfsSuccess'));
    } on PlatformException catch (e) {
      if (!mounted) return;
      if (e.code == 'ROOTFS_EXISTS') {
        // 同名 rootfs 已存在，让用户输入新 id 或取消；默认填入刚试过的名称
        // 方便用户在其基础上修改（如加后缀）。
        final newId = await _promptForRootfsId(
          title: context.tr('runtime.proot.rootfsExistsTitle'),
          message: context.tr('runtime.proot.rootfsExistsMessage', {
            'error': e.message ?? 'ROOTFS_EXISTS',
          }),
          defaultName: id,
        );
        if (newId != null && newId.isNotEmpty && mounted) {
          await _doImportRootfs(path, id: newId);
        }
        return;
      }
      showErrorDialog(
        context,
        context.tr('runtime.proot.importRootfsFailed', {
          'error': e.message ?? '',
        }),
      );
    } catch (e) {
      if (!mounted) return;
      showErrorDialog(
        context,
        context.tr('runtime.proot.importRootfsFailed', {'error': '$e'}),
      );
    } finally {
      if (mounted) setState(() => _importingRootfs = false);
    }
  }

  /// 弹出对话框让用户输入 rootfs 名称。
  ///
  /// [defaultName] 为输入框默认内容（通常为去掉扩展名的文件名）；冲突重试时
  /// 传入刚试过的名称，方便用户在其基础上修改。
  ///
  /// 名称仅允许英文字母、数字、`.`、`_`、`-`（与原生侧 rootfs 目录命名规则
  /// [ProotEnvironment.importRootfs] 的正则 `[^A-Za-z0-9._-]` 一致）；
  /// 且不能以 `.` 开头（rootfs 列表会跳过 `.` 开头的目录）。
  Future<String?> _promptForRootfsId({
    required String title,
    required String message,
    String? defaultName,
  }) {
    final controller = TextEditingController(text: defaultName ?? '');
    // 输入错误提示；用 ValueNotifier 让对话框内可局部刷新。
    final errorNotifier = ValueNotifier<String?>(null);
    return showMiuixDialog<String>(
      context: context,
      title: title,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              const SizedBox(height: 8),
              EcTextField(
                controller: controller,
                hint: ctx.tr('runtime.proot.rootfsNameHint'),
                helperText: ctx.tr('runtime.proot.rootfsNameHelper'),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9._-]')),
                ],
                onChanged: (_) {
                  if (errorNotifier.value != null) {
                    errorNotifier.value = null;
                  }
                },
                autofocus: true,
              ),
              ValueListenableBuilder<String?>(
                valueListenable: errorNotifier,
                builder: (_, err, _) => err == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          err,
                          style: TextStyle(
                            color: Theme.of(ctx).colorScheme.error,
                            fontSize: 12,
                          ),
                        ),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          MiuixDialogActions(
            children: [
              MiuixTextButton(
                ctx.tr('common.cancel'),
                onPressed: () => Navigator.of(ctx).pop(null),
              ),
              MiuixButton(
                onPressed: () {
                  final name = controller.text.trim();
                  if (name.isEmpty) {
                    errorNotifier.value = ctx.tr('runtime.proot.nameEmpty');
                    return;
                  }
                  if (name.startsWith('.')) {
                    errorNotifier.value = ctx.tr(
                      'runtime.proot.nameStartsWithDot',
                    );
                    return;
                  }
                  Navigator.of(ctx).pop(name);
                },
                colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                child: MiuixText(ctx.tr('common.ok')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _deleteRootfs(ProotRootfsInfo info) async {
    final confirmed = await showMiuixConfirm(
      context,
      title: context.tr('runtime.proot.deleteRootfsTitle'),
      message: context.tr('runtime.proot.deleteRootfsContent', {'id': info.id}),
      cancelLabel: context.tr('common.cancel'),
      confirmLabel: context.tr('common.delete'),
    );
    if (confirmed != true || !mounted) return;

    try {
      await runWithLoadingDialog(
        context,
        context.tr('common.deleting'),
        () => _prootService.deleteRootfs(info.id),
      );
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      showErrorDialog(
        context,
        context.tr('runtime.proot.deleteRootfsFailed', {'error': '$e'}),
      );
    }
  }

  /// 检查单个运行时更新。
  Future<void> _checkUpdate(RuntimeInfo info) async {
    final tr = LocaleScope.of(context).translations;

    if (!info.canCheckUpdate) {
      showErrorDialog(context, tr.get('runtime.update.noUpdateUrl'));
      return;
    }

    // 检查更新期间，先确认运行时未在运行（避免更新覆盖正在使用的二进制）。
    final running = await _service.isRuntimeRunning(info.id);
    if (running) {
      if (!mounted) return;
      showErrorDialog(context, tr.get('runtime.cannotUpdateRunning'));
      return;
    }

    if (!mounted) return;
    // 显示加载对话框
    showLoadingDialog(context, tr.get('runtime.update.checking'));

    RuntimeUpdateInfo? updateInfo;
    String? error;
    try {
      updateInfo = await RuntimeUpdateService.checkForUpdates(info);
    } catch (e) {
      error = '$e';
    }
    if (!mounted) return;
    Navigator.of(context).pop(); // 关闭加载对话框

    if (updateInfo == null) {
      showErrorDialog(
        context,
        tr.get('runtime.update.checkFailed', {'error': error ?? ''}),
      );
      return;
    }

    if (!RuntimeUpdateService.hasUpdate(info, updateInfo)) {
      showMiuixSnackbar(tr.get('runtime.update.alreadyLatest'));
      return;
    }

    if (!mounted) return;
    await _showUpdateDialog(info, updateInfo);
  }

  /// 展示更新详情对话框，确认后下载并安装。
  Future<void> _showUpdateDialog(
    RuntimeInfo runtime,
    RuntimeUpdateInfo info,
  ) async {
    final tr = LocaleScope.of(context).translations;

    final confirmed = await showMiuixDialog<bool>(
      context: context,
      title: tr.get('runtime.update.availableTitle'),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr.get('runtime.update.versionRow', {
                    'current': tr.get('runtime.versionWithBuild', {
                      'version': runtime.displayVersion,
                      'build': runtime.version.toString(),
                    }),
                    'latest': tr.get('runtime.versionWithBuild', {
                      'version': info.displayVersion,
                      'build': info.version.toString(),
                    }),
                  }),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (info.publishedAt != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    tr.get('runtime.update.publishedAt', {
                      'date': info.publishedAt!,
                    }),
                  ),
                ],
                if (info.releaseNotes != null &&
                    info.releaseNotes!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(info.releaseNotes!),
                ],
                const SizedBox(height: 12),
                MiuixText(
                  tr.get('runtime.update.noteOverwrite'),
                  style: MiuixTheme.of(ctx).textStyles.footnote1,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          MiuixDialogActions(
            children: [
              MiuixTextButton(
                tr.get('common.cancel'),
                onPressed: () => Navigator.of(ctx).pop(false),
              ),
              MiuixButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                child: MiuixText(tr.get('runtime.update.download')),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    // 选取下载包
    final deviceArch = await _service.getDeviceArch();
    final pkg = RuntimeUpdateService.pickPackage(info, deviceArch);
    if (pkg == null) {
      if (mounted) {
        showErrorDialog(context, tr.get('runtime.update.noMatchingPackage'));
      }
      return;
    }

    if (!mounted) return;
    await _downloadAndInstall(runtime, pkg);
  }

  /// 下载并安装更新包，展示进度对话框。
  Future<void> _downloadAndInstall(
    RuntimeInfo runtime,
    RuntimeUpdatePackage pkg,
  ) async {
    final tr = LocaleScope.of(context).translations;

    final progressNotifier = ValueNotifier<_DownloadProgress>(
      _DownloadProgress(
        stage: _DownloadStage.downloading,
        received: 0,
        total: pkg.size,
      ),
    );
    var cancelled = false;

    // 进度对话框（用户可取消下载）
    final dialogFuture = showMiuixDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _UpdateProgressDialog(
        progressNotifier: progressNotifier,
        sizeBytes: pkg.size,
        onCancel: () => cancelled = true,
        tr: tr,
      ),
    );

    String? downloadedPath;
    String? error;
    try {
      downloadedPath = await RuntimeUpdateService.downloadPackage(
        pkg,
        onProgress: (progress) {
          progressNotifier.value = _DownloadProgress(
            stage: _DownloadStage.downloading,
            received: progress.receivedBytes,
            total: progress.totalBytes ?? pkg.size,
            speedBytesPerSec: progress.speedBytesPerSec,
            etaMs: progress.etaMs,
          );
        },
        isCancelled: () => cancelled,
      );
    } on CancellationException {
      // 用户取消
    } catch (e) {
      error = '$e';
    }

    if (!mounted) {
      // 页面已销毁，关闭对话框并退出
      progressNotifier.dispose();
      return;
    }

    if (error != null) {
      // 下载/校验失败：关闭对话框并提示
      progressNotifier.value = _DownloadProgress(
        stage: _DownloadStage.failed,
        received: 0,
        total: pkg.size,
        error: error,
      );
      // 等待对话框关闭（用户点击关闭）
      await dialogFuture;
      progressNotifier.dispose();
      if (mounted) {
        showErrorDialog(
          context,
          tr.get('runtime.update.downloadFailed', {'error': error}),
        );
      }
      return;
    }

    if (downloadedPath == null) {
      // 用户取消
      progressNotifier.value = _DownloadProgress(
        stage: _DownloadStage.cancelled,
        received: 0,
        total: pkg.size,
      );
      await dialogFuture;
      progressNotifier.dispose();
      if (mounted) {
        showMiuixSnackbar(tr.get('runtime.update.cancelled'));
      }
      return;
    }

    // 下载成功，切换到安装阶段
    progressNotifier.value = _DownloadProgress(
      stage: _DownloadStage.installing,
      received: pkg.size ?? 0,
      total: pkg.size,
    );

    try {
      await _service.importPackage(downloadedPath, force: true);
      if (!mounted) {
        progressNotifier.dispose();
        return;
      }
      // 安装成功：关闭对话框，刷新列表，提示
      progressNotifier.value = _DownloadProgress(
        stage: _DownloadStage.done,
        received: pkg.size ?? 0,
        total: pkg.size,
      );
      await dialogFuture;
      progressNotifier.dispose();
      await _load();
      if (mounted) {
        showMiuixSnackbar(tr.get('runtime.update.success'));
      }
    } catch (e) {
      if (!mounted) {
        progressNotifier.dispose();
        return;
      }
      progressNotifier.value = _DownloadProgress(
        stage: _DownloadStage.failed,
        received: pkg.size ?? 0,
        total: pkg.size,
        error: '$e',
      );
      await dialogFuture;
      progressNotifier.dispose();
      if (mounted) {
        showErrorDialog(
          context,
          tr.get('runtime.update.installFailed', {'error': '$e'}),
        );
      }
    }
  }

  String _typeLabel(String type) {
    return switch (type) {
      'jre' => 'Java',
      'php' => 'PHP',
      'frpc' => 'FRP',
      _ => type,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final showProotSection = _prootAvailable || _prootRootfs.isNotEmpty;
    return MiuixScaffold(
      topBar: EcTopAppBar(
        title: context.tr('runtime.title'),

        actions: [
          MiuixIconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EcpkgDownloadPage()),
            ),
            child: MiuixIcon(icon: Icons.cloud_download_outlined),
          ),
        ],
      ),
      content: (padding) => Padding(
        padding: padding,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // —— 原生运行时区（直接在 Android 上运行，区别于 proot 容器）——
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.extension_outlined, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          context.tr('runtime.nativeRuntimeSection'),
                          style: theme.textStyles.subtitle,
                        ),
                        const Spacer(),
                        if (_runtimes.isNotEmpty)
                          Text(
                            context.tr('runtime.count', {
                              'count': '${_runtimes.length}',
                            }),
                            style: theme.textStyles.footnote1,
                          ),
                      ],
                    ),
                  ),
                  for (final rt in _runtimes) ...[
                    MiuixCard(
                      child: MiuixBasicComponent(
                        startAction: Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: Icon(switch (rt.type) {
                            'jre' => Icons.coffee,
                            'php' => Icons.code,
                            'frpc' => Icons.network_check,
                            _ => Icons.memory,
                          }, size: 32),
                        ),
                        content: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(rt.name),
                              Text(
                                '${_typeLabel(rt.type)} · ${context.tr('runtime.versionWithBuild', {'version': rt.displayVersion, 'build': rt.version.toString()})}',
                                style: theme.textStyles.footnote1,
                              ),
                            ],
                          ),
                        ],
                        endActions: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              MiuixIconButton(
                                onPressed: rt.canCheckUpdate
                                    ? () => _checkUpdate(rt)
                                    : null,
                                child: MiuixIcon(icon: Icons.system_update_alt),
                              ),
                              MiuixIconButton(
                                onPressed: () => _delete(rt),
                                child: MiuixIcon(icon: Icons.delete_outline),
                              ),
                              MiuixOverlayIconDropdownMenu(
                                entry: MiuixDropdownEntry(
                                  items: [
                                    if (rt.homepage != null &&
                                        rt.homepage!.isNotEmpty)
                                      MiuixDropdownItem(
                                        text: context.tr(
                                          'runtime.openHomepage',
                                        ),
                                        onClick: () => launchUrl(
                                          Uri.parse(rt.homepage!),
                                          mode: LaunchMode.externalApplication,
                                        ),
                                      ),
                                    if (rt.repository != null &&
                                        rt.repository!.isNotEmpty)
                                      MiuixDropdownItem(
                                        text: context.tr(
                                          'runtime.openRepository',
                                        ),
                                        onClick: () => launchUrl(
                                          Uri.parse(rt.repository!),
                                          mode: LaunchMode.externalApplication,
                                        ),
                                      ),
                                  ],
                                ),
                                child: const MiuixIcon(icon: Icons.more_vert),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (_runtimes.isEmpty && _prootRootfs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.inventory_2_outlined,
                              size: 48,
                              color: theme.colors.onSurfaceVariantSummary,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              context.tr('runtime.emptyTitle'),
                              style: theme.textStyles.title4,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              context.tr('runtime.emptyDescription'),
                              style: theme.textStyles.footnote1,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  // —— proot rootfs 区 ——
                  if (showProotSection) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.dns_outlined, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            context.tr('runtime.proot.rootfsSection'),
                            style: theme.textStyles.subtitle,
                          ),
                          const Spacer(),
                          if (_prootRootfs.isNotEmpty)
                            Text(
                              context.tr('runtime.count', {
                                'count': '${_prootRootfs.length}',
                              }),
                              style: theme.textStyles.footnote1,
                            ),
                        ],
                      ),
                    ),
                    if (!_prootAvailable)
                      MiuixCard(
                        insideMargin: const EdgeInsets.all(12),
                        colors: MiuixCardColors(
                          color: theme.colors.errorContainer.withValues(
                            alpha: 0.3,
                          ),
                          contentColor: MiuixTheme.of(context).colors.onSurface,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.warning_amber,
                              color: theme.colors.error,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                context.tr('runtime.proot.notAvailableShort'),
                                style: theme.textStyles.footnote1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    for (final rootfs in _prootRootfs) ...[
                      MiuixCard(
                        child: MiuixBasicComponent(
                          startAction: Padding(
                            padding: const EdgeInsets.only(right: 16),
                            child: const Icon(Icons.terminal, size: 32),
                          ),
                          content: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  rootfs.envName.isNotEmpty
                                      ? '${rootfs.envName} (${rootfs.id})'
                                      : rootfs.id,
                                ),
                                Text(
                                  rootfs.isGeneric
                                      ? context.tr(
                                          'runtime.proot.genericContainer',
                                        )
                                      : '${context.tr('runtime.proot.rootfsSubtitle', {'type': rootfs.envType, 'bin': rootfs.envMainBin})}'
                                            '${rootfs.envVersionName.isNotEmpty ? ' (${rootfs.envVersionName})' : ''}',
                                  style: theme.textStyles.footnote1.copyWith(
                                    color: rootfs.isGeneric
                                        ? theme.colors.primary
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          endActions: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                MiuixIconButton(
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          ContainerFilesPage(rootfs: rootfs),
                                    ),
                                  ),
                                  child: MiuixIcon(
                                    icon: Icons.folder_open_outlined,
                                  ),
                                ),
                                MiuixIconButton(
                                  onPressed: () => _deleteRootfs(rootfs),
                                  child: MiuixIcon(icon: Icons.delete_outline),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ],
              ),
      ),
      floatingActionButton: Tooltip(
        message: context.tr('runtime.importTooltip'),
        child: MiuixFloatingActionButton(
          onPressed: (_importing || _importingRootfs) ? null : _importUnified,
          child: MiuixIcon(icon: Icons.add),
        ),
      ),
    );
  }
}

/// 下载阶段。
enum _DownloadStage { downloading, installing, done, failed, cancelled }

/// 下载进度快照。
class _DownloadProgress {
  const _DownloadProgress({
    required this.stage,
    required this.received,
    required this.total,
    this.speedBytesPerSec = 0,
    this.etaMs,
    this.error,
  });

  final _DownloadStage stage;
  final int received;
  final int? total;
  final double speedBytesPerSec;
  final int? etaMs;
  final String? error;

  /// 0–100，未知时为 null。
  int? get percent {
    final t = total;
    if (t == null || t <= 0) return null;
    return (received * 100 ~/ t).clamp(0, 100);
  }
}

/// 更新下载/安装进度对话框。
///
/// 通过 [progressNotifier] 监听进度变化。下载阶段可点击「取消」；
/// 完成/失败/取消阶段显示对应状态与「关闭」按钮。
class _UpdateProgressDialog extends StatelessWidget {
  const _UpdateProgressDialog({
    required this.progressNotifier,
    required this.sizeBytes,
    required this.onCancel,
    required this.tr,
  });

  final ValueNotifier<_DownloadProgress> progressNotifier;
  final int? sizeBytes;
  final VoidCallback onCancel;
  final dynamic tr;

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  /// 速度 + 剩余时间行，如 `5.3 MB/s · ~16s`；速度<=0 时返回空串。
  String _speedEta(_DownloadProgress progress) {
    final speed = formatSpeed(progress.speedBytesPerSec);
    if (speed.isEmpty) return '';
    final eta = formatEta(progress.etaMs);
    return eta.isEmpty ? speed : '$speed · $eta';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_DownloadProgress>(
      valueListenable: progressNotifier,
      builder: (ctx, progress, _) {
        final stage = progress.stage;
        final canCancel = stage == _DownloadStage.downloading;
        final isTerminal =
            stage == _DownloadStage.done ||
            stage == _DownloadStage.failed ||
            stage == _DownloadStage.cancelled;

        String title;
        String? message;
        switch (stage) {
          case _DownloadStage.downloading:
            title = tr.get('runtime.update.downloading');
            break;
          case _DownloadStage.installing:
            title = tr.get('runtime.update.installing');
            break;
          case _DownloadStage.done:
            title = tr.get('runtime.update.doneTitle');
            break;
          case _DownloadStage.failed:
            title = tr.get('runtime.update.failedTitle');
            message = progress.error;
            break;
          case _DownloadStage.cancelled:
            title = tr.get('runtime.update.cancelledTitle');
            break;
        }

        final theme = MiuixTheme.of(ctx);
        return PopScope(
          canPop: false,
          // 标题随下载阶段变化，不能提到 showMiuixDialog 的静态 title 参数，
          // 故与内容一起放在内容体里自绘。
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                child: MiuixText(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textStyles.title4,
                ),
              ),
              const SizedBox(height: 12),
              if (stage == _DownloadStage.downloading ||
                  stage == _DownloadStage.installing) ...[
                progress.percent != null
                    ? TweenAnimationBuilder<double>(
                        tween: Tween(
                          begin: progress.percent! / 100.0,
                          end: progress.percent! / 100.0,
                        ),
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.linear,
                        builder: (context, value, _) =>
                            MiuixLinearProgressIndicator(progress: value),
                      )
                    : const MiuixLinearProgressIndicator(),
                const SizedBox(height: 12),
                if (stage == _DownloadStage.downloading) ...[
                  TweenAnimationBuilder<double>(
                    tween: Tween(
                      begin: progress.received.toDouble(),
                      end: progress.received.toDouble(),
                    ),
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.linear,
                    builder: (context, received, _) {
                      if (progress.percent != null) {
                        final pct = (received / progress.total! * 100)
                            .toStringAsFixed(1);
                        return Text(
                          '$pct% · ${_formatBytes(received.round())} / ${progress.total != null ? _formatBytes(progress.total!) : '?'}',
                          style: theme.textStyles.footnote1,
                        );
                      }
                      return Text(
                        _formatBytes(received.round()),
                        style: theme.textStyles.footnote1,
                      );
                    },
                  ),
                  if (progress.speedBytesPerSec > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      _speedEta(progress),
                      style: theme.textStyles.footnote1,
                    ),
                  ],
                ],
              ],
              if (message != null) ...[
                const SizedBox(height: 8),
                MiuixText(message, color: theme.colors.error, fontSize: 13),
              ],
              if (canCancel || isTerminal) ...[
                const SizedBox(height: 20),
                MiuixDialogActions(
                  children: [
                    if (canCancel)
                      MiuixTextButton(
                        tr.get('common.cancel'),
                        onPressed: onCancel,
                      ),
                    if (isTerminal)
                      MiuixButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        colors: MiuixButtonDefaults.buttonColorsPrimary(
                          context,
                        ),
                        child: MiuixText(tr.get('common.close')),
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
