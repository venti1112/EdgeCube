import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../files/storage_permission.dart';
import '../files/system_picker.dart';
import '../i18n/locale_scope.dart';
import '../server/ecpkg_handler.dart';
import '../server/proot_service.dart';
import '../server/runtime_service.dart';
import '../server/runtime_update_service.dart';
import 'ecpkg_download_page.dart';

/// 「运行环境」管理页：列出已安装运行时，导入/删除/更新 .ecpkg。
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
    EcpkgHandler.onOpenEcpkg = null;
    super.dispose();
  }

  void _onRuntimesChanged() {
    if (mounted) _load();
  }

  void _handleOpenEcpkg(String path) {
    if (!mounted) return;
    if (!path.toLowerCase().endsWith('.ecpkg')) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('runtime.notEcpkg'))));
      return;
    }
    _doImport(path);
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

  Future<void> _import() async {
    if (!await StoragePermission.isGranted()) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.tr('fileBrowser.permissionTitle')),
          content: Text(ctx.tr('fileBrowser.permissionContent')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(ctx.tr('common.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(ctx.tr('fileBrowser.grantPermission')),
            ),
          ],
        ),
      );
      if (go != true) return;
      await StoragePermission.request();
      if (!mounted) return;
      return _import();
    }

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final tr = LocaleScope.of(context).translations;
    final path = await pickFromSystem(
      context,
      mode: SystemPickMode.file,
      allowedExtensions: const ['.ecpkg'],
    );
    if (path == null || !path.toLowerCase().endsWith('.ecpkg')) {
      if (mounted && path != null) {
        messenger.showSnackBar(
          SnackBar(content: Text(tr.get('runtime.notEcpkg'))),
        );
      }
      return;
    }

    await _doImport(path);
  }

  Future<void> _doImport(String path, {bool force = false}) async {
    final messenger = ScaffoldMessenger.of(context);
    final tr = LocaleScope.of(context).translations;
    setState(() => _importing = true);
    try {
      await _service.importPackage(path, force: force);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(tr.get('runtime.importSuccess'))),
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      if (e.code == 'IMPORT_FAILED' &&
          e.message?.contains('RUNTIME_EXISTS') == true &&
          !force) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr.get('runtime.importConfirmTitle')),
            content: Text(tr.get('runtime.importConfirmContent')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(tr.get('common.cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(tr.get('common.replace')),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          await _doImport(path, force: true);
        }
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            tr.get('runtime.importFailed', {'error': '${e.message}'}),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(tr.get('runtime.importFailed', {'error': '$e'})),
        ),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _delete(RuntimeInfo info) async {
    final theme = Theme.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final tr = LocaleScope.of(context).translations;
    final runtimeRunning = await _service.isRuntimeRunning(info.id);
    if (runtimeRunning) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(tr.get('runtime.cannotDeleteRunning'))),
      );
      return;
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr.get('runtime.deleteConfirmTitle')),
        content: Text(
          tr.get('runtime.deleteConfirmContent', {'name': info.name}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr.get('common.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr.get('common.delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _service.deleteRuntime(info.id);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(tr.get('runtime.deleteFailed', {'error': '$e'})),
        ),
      );
    }
  }

  // —— proot rootfs 导入/删除 ——

  Future<void> _importRootfs() async {
    if (!_prootAvailable) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'proot 原生库未打包。请从 tiny_container releases 下载 jniLibs.zip '
            '解压到 android/app/src/main/jniLibs/arm64-v8a/ 后重新构建。',
          ),
        ),
      );
      return;
    }

    if (!await StoragePermission.isGranted()) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.tr('fileBrowser.permissionTitle')),
          content: Text(ctx.tr('fileBrowser.permissionContent')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(ctx.tr('common.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(ctx.tr('fileBrowser.grantPermission')),
            ),
          ],
        ),
      );
      if (go != true) return;
      await StoragePermission.request();
      if (!mounted) return;
      return _importRootfs();
    }

    if (!mounted) return;
    final path = await pickFromSystem(
      context,
      mode: SystemPickMode.file,
      allowedExtensions: const ['.tar.zst', '.tar.xz', '.tar.gz', '.tgz'],
    );
    if (path == null) return;

    // 始终弹出名称输入框，默认为去掉压缩包扩展名的文件名
    final defaultName = _rootfsNameFromPath(path);
    final id = await _promptForRootfsId(
      title: '导入 rootfs',
      message: '请输入 rootfs 名称：',
      defaultName: defaultName,
    );
    if (id == null || id.isEmpty) return; // 用户取消
    await _doImportRootfs(path, id: id);
  }

  /// 从文件路径推导 rootfs 名称：取 basename 并剥离已知压缩包扩展名。
  String _rootfsNameFromPath(String path) {
    var name = p.basename(path);
    const exts = ['.tar.zst', '.tar.xz', '.tar.gz', '.tgz', '.tar'];
    for (final ext in exts) {
      if (name.toLowerCase().endsWith(ext)) {
        name = name.substring(0, name.length - ext.length);
        break;
      }
    }
    return name;
  }

  Future<void> _doImportRootfs(String path, {required String id}) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _importingRootfs = true);
    try {
      await _prootService.importRootfs(path, id: id);
      if (!mounted) return;
      await _load();
      messenger.showSnackBar(
        const SnackBar(content: Text('rootfs 导入成功')),
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      if (e.code == 'ROOTFS_EXISTS') {
        // 同名 rootfs 已存在，让用户输入新 id 或取消；默认填入刚试过的名称
        // 方便用户在其基础上修改（如加后缀）。
        final newId = await _promptForRootfsId(
          title: 'rootfs 已存在',
          message: '${e.message ?? 'ROOTFS_EXISTS'}\n请输入新的 rootfs 名称：',
          defaultName: id,
        );
        if (newId != null && newId.isNotEmpty && mounted) {
          await _doImportRootfs(path, id: newId);
        }
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('rootfs 导入失败：${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('rootfs 导入失败：$e')),
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
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: '如 debian-12-jdk21',
                helperText: '仅允许字母、数字、. _ -',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9._-]')),
              ],
              onChanged: (_) {
                if (errorNotifier.value != null) {
                  errorNotifier.value = null;
                }
              },
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
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isEmpty) {
                errorNotifier.value = '名称不能为空';
                return;
              }
              if (name.startsWith('.')) {
                errorNotifier.value = '名称不能以 . 开头';
                return;
              }
              Navigator.of(ctx).pop(name);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteRootfs(ProotRootfsInfo info) async {
    final theme = Theme.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除 rootfs'),
        content: Text('确认删除 rootfs「${info.id}」？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _prootService.deleteRootfs(info.id);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('删除 rootfs 失败：$e')),
      );
    }
  }

  /// 检查单个运行时更新。
  Future<void> _checkUpdate(RuntimeInfo info) async {
    final tr = LocaleScope.of(context).translations;
    final messenger = ScaffoldMessenger.of(context);

    if (!info.canCheckUpdate) {
      messenger.showSnackBar(
        SnackBar(content: Text(tr.get('runtime.update.noUpdateUrl'))),
      );
      return;
    }

    // 检查更新期间，先确认运行时未在运行（避免更新覆盖正在使用的二进制）。
    final running = await _service.isRuntimeRunning(info.id);
    if (running) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(tr.get('runtime.cannotUpdateRunning'))),
      );
      return;
    }

    if (!mounted) return;
    // 显示加载对话框
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Text(tr.get('runtime.update.checking')),
          ],
        ),
      ),
    );

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
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            tr.get('runtime.update.checkFailed', {'error': error ?? ''}),
          ),
        ),
      );
      return;
    }

    if (!RuntimeUpdateService.hasUpdate(info, updateInfo)) {
      messenger.showSnackBar(
        SnackBar(content: Text(tr.get('runtime.update.alreadyLatest'))),
      );
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
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr.get('runtime.update.availableTitle')),
        content: SingleChildScrollView(
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
              Text(
                tr.get('runtime.update.noteOverwrite'),
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr.get('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr.get('runtime.update.download')),
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
      messenger.showSnackBar(
        SnackBar(content: Text(tr.get('runtime.update.noMatchingPackage'))),
      );
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
    final messenger = ScaffoldMessenger.of(context);

    final progressNotifier = ValueNotifier<_DownloadProgress>(
      _DownloadProgress(
        stage: _DownloadStage.downloading,
        received: 0,
        total: pkg.size,
      ),
    );
    var cancelled = false;

    // 进度对话框（用户可取消下载）
    final dialogFuture = showDialog<void>(
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
        onProgress: (received, total) {
          progressNotifier.value = _DownloadProgress(
            stage: _DownloadStage.downloading,
            received: received,
            total: total ?? pkg.size,
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
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              tr.get('runtime.update.downloadFailed', {'error': error}),
            ),
          ),
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
        messenger.showSnackBar(
          SnackBar(content: Text(tr.get('runtime.update.cancelled'))),
        );
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
        messenger.showSnackBar(
          SnackBar(content: Text(tr.get('runtime.update.success'))),
        );
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
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            tr.get('runtime.update.installFailed', {'error': '$e'}),
          ),
        ),
      );
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
    final theme = Theme.of(context);
    final showProotSection = _prootAvailable || _prootRootfs.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
  title: Text(context.tr('runtime.title')),
  actions: [
    IconButton(
      icon: const Icon(Icons.cloud_download_outlined),
      tooltip: context.tr('ecpkgDownload.browse'),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const EcpkgDownloadPage()),
      ),
    ),
  ],
),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // —— 原生运行时区（直接在 Android 上运行，区别于 proot 容器）——
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.extension_outlined, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        '原生运行时',
                        style: theme.textTheme.titleSmall,
                      ),
                      const Spacer(),
                      if (_runtimes.isNotEmpty)
                        Text(
                          '${_runtimes.length} 个',
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                for (final rt in _runtimes)
                  Card(
                      child: ListTile(
                        leading: Icon(switch (rt.type) {
                          'jre' => Icons.coffee,
                          'php' => Icons.code,
                          'frpc' => Icons.network_check,
                          _ => Icons.memory,
                        }, size: 32),
                        title: Text(rt.name),
                        subtitle: Text(
                          '${_typeLabel(rt.type)} · ${context.tr('runtime.versionWithBuild', {
                            'version': rt.displayVersion,
                            'build': rt.version.toString(),
                          })}',
                          style: theme.textTheme.bodySmall,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.system_update_alt),
                              tooltip: context.tr('runtime.update.tooltip'),
                              onPressed: rt.canCheckUpdate
                                  ? () => _checkUpdate(rt)
                                  : null,
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(rt),
                            ),
                            PopupMenuButton<String>(
                              tooltip: context.tr('runtime.more'),
                              icon: const Icon(Icons.more_vert),
                              onSelected: (action) {
                                if (action == 'homepage') {
                                  launchUrl(Uri.parse(rt.homepage!),
                                      mode: LaunchMode.externalApplication);
                                } else if (action == 'repository') {
                                  launchUrl(Uri.parse(rt.repository!),
                                      mode: LaunchMode.externalApplication);
                                }
                              },
                              itemBuilder: (ctx) => [
                                if (rt.homepage != null && rt.homepage!.isNotEmpty)
                                  PopupMenuItem(
                                    value: 'homepage',
                                    child: ListTile(
                                      leading: const Icon(Icons.home_outlined),
                                      title: Text(ctx.tr('runtime.openHomepage')),
                                      contentPadding: EdgeInsets.zero,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                if (rt.repository != null &&
                                    rt.repository!.isNotEmpty)
                                  PopupMenuItem(
                                    value: 'repository',
                                    child: ListTile(
                                      leading: const Icon(Icons.code),
                                      title:
                                          Text(ctx.tr('runtime.openRepository')),
                                      contentPadding: EdgeInsets.zero,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                Card(
                  child: ListTile(
                    leading: _importing
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add),
                    title: Text(_importing ? '导入中…' : '导入 .ecpkg'),
                    subtitle: Text(
                      '从 .ecpkg 文件导入 Java / PHP / FRP 运行时',
                      style: theme.textTheme.bodySmall,
                    ),
                    onTap: _importing ? null : _import,
                  ),
                ),
                // —— proot rootfs 区 ——
                if (showProotSection) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.dns_outlined, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'proot 容器 rootfs',
                          style: theme.textTheme.titleSmall,
                        ),
                        const Spacer(),
                        if (_prootRootfs.isNotEmpty)
                          Text(
                            '${_prootRootfs.length} 个',
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  if (!_prootAvailable)
                    Card(
                      color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber,
                                color: theme.colorScheme.error),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'proot 原生库未打包。请从 tiny_container releases '
                                '下载 jniLibs.zip 解压到 jniLibs/arm64-v8a/ 后重新构建。',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  for (final rootfs in _prootRootfs)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.terminal, size: 32),
                        title: Text(
                          rootfs.envName.isNotEmpty
                              ? '${rootfs.envName} (${rootfs.id})'
                              : rootfs.id,
                        ),
                        subtitle: Text(
                          rootfs.isGeneric
                              ? '纯容器（无元数据，需手动填写启动命令）'
                              : '${rootfs.envType}: ${rootfs.envMainBin}'
                                  '${rootfs.envVersionName.isNotEmpty ? ' (${rootfs.envVersionName})' : ''}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: rootfs.isGeneric
                                ? theme.colorScheme.primary
                                : null,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _deleteRootfs(rootfs),
                        ),
                      ),
                    ),
                  if (_prootAvailable)
                    Card(
                      child: ListTile(
                        leading: _importingRootfs
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.add),
                        title: Text(
                          _importingRootfs ? '导入中…' : '导入 rootfs.tar.zst',
                        ),
                        subtitle: Text(
                          '从 rootfs.tar.zst 导入 Linux 根文件系统（带元数据或纯容器）',
                          style: theme.textTheme.bodySmall,
                        ),
                        onTap: _importingRootfs ? null : _importRootfs,
                      ),
                    ),
                ],
              ],
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
    this.error,
  });

  final _DownloadStage stage;
  final int received;
  final int? total;
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

        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (stage == _DownloadStage.downloading ||
                    stage == _DownloadStage.installing) ...[
                  LinearProgressIndicator(
                    value: progress.percent != null
                        ? progress.percent! / 100.0
                        : null,
                  ),
                  const SizedBox(height: 12),
                  if (stage == _DownloadStage.downloading)
                    Text(
                      progress.percent != null
                          ? '${progress.percent}% · ${_formatBytes(progress.received)} / ${progress.total != null ? _formatBytes(progress.total!) : '?'}'
                          : _formatBytes(progress.received),
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                ],
                if (message != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    message,
                    style: TextStyle(
                      color: Theme.of(ctx).colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              if (canCancel)
                TextButton(
                  onPressed: onCancel,
                  child: Text(tr.get('common.cancel')),
                ),
              if (isTerminal)
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(tr.get('common.close')),
                ),
            ],
          ),
        );
      },
    );
  }
}
