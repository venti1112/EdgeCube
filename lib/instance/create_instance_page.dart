import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../files/file_service.dart';
import '../files/storage_permission.dart';
import '../files/system_picker.dart';
import '../instance/instance.dart';
import '../instance/instance_controller.dart';
import '../instance/instance_scope.dart';

enum _WizardStep {
  nameEntry,
  serverType,
  versionSelect,
  downloading,
  importFile,
}

/// 新建实例向导结果。
enum CreateInstanceResult { done, cancelled }

/// 新建实例向导页。
///
/// 流程：
/// 1. 输入名称 → 选择「下载服务端」或「导入服务端」
/// 2a. 下载服务端 → 选类型 → 选版本 → 创建实例并下载
/// 2b. 导入服务端 → 创建实例 → 选文件导入
///
/// 如果用户中途退出（未完成），自动删除已创建的空实例。
class CreateInstancePage extends StatefulWidget {
  const CreateInstancePage({super.key});

  @override
  State<CreateInstancePage> createState() => _CreateInstancePageState();
}

class _CreateInstancePageState extends State<CreateInstancePage> {
  static const _fileService = FileService();

  _WizardStep _step = _WizardStep.nameEntry;
  final _nameController = TextEditingController(text: '新实例');
  String? _instanceId;
  String? _serverType;
  List<String> _versions = [];
  bool _loadingVersions = false;
  String? _versionError;
  double? _downloadProgress;
  String? _downloadError;
  bool _completed = false;

  /// 缓存版本详情页 URL（Vanilla）。
  Map<String, String> _vanillaVersionUrls = {};
  /// 用户确认要下载的版本号（弹窗确认后记录，供下载和自动 Java 版本推断使用）。
  String? _selectedVersion;

  late InstanceController _instanceController;

  @override
  void initState() {
    super.initState();
    _instanceController = InstanceScope.of(context);
  }

  @override
  void dispose() {
    _nameController.dispose();
    // 如果向导未完成且已创建了实例，清理空实例。
    if (!_completed && _instanceId != null) {
      _instanceController.deleteInstance(_instanceId!);
    }
    super.dispose();
  }

  // —— 步骤导航 ——

  /// 校验名称：非空且不重名。重复时弹出提示对话框。
  Future<bool> _validateName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return false;
    if (_instanceController.instances.any((i) => i.name == name)) {
      await _showDuplicateDialog(name);
      return false;
    }
    return true;
  }

  Future<void> _goToServerType() async {
    if (!await _validateName()) return;
    setState(() => _step = _WizardStep.serverType);
  }

  Future<void> _selectServerType(String type) async {
    _serverType = type;
    setState(() {
      _step = _WizardStep.versionSelect;
      _loadingVersions = true;
      _versionError = null;
      _versions = [];
    });
    try {
      _versions = await _fetchVersions(type);
      if (!mounted) return;
      setState(() => _loadingVersions = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingVersions = false;
        _versionError = '获取版本列表失败：$e';
      });
    }
  }

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

  Future<void> _doImport(String instanceId) async {
    // 确保有文件访问权限。
    if (!await StoragePermission.isGranted()) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('需要文件访问权限'),
          content: const Text(
            '导入需要「所有文件访问权限」。点击「去授权」后，请在系统设置中为本应用打开该权限，再返回重试。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('去授权'),
            ),
          ],
        ),
      );
      if (go != true) {
        _closeWizard();
        return;
      }
      await StoragePermission.request();
      // 授权后重新尝试导入。
      if (!mounted) return;
      _doImport(instanceId);
      return;
    }

    if (!mounted) return;
    final sourcePath =
        await pickFromSystem(context, mode: SystemPickMode.file);
    if (sourcePath == null) {
      // 用户取消选择，关闭向导（dispose 会自动清理空实例）。
      _closeWizard();
      return;
    }
    try {
      final instance = _instanceController.instances
          .firstWhere((i) => i.id == instanceId);
      final dir = await _instanceController.directoryFor(instance);
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

  Future<void> _selectVersion(String version) async {
    // 步骤 1：确认弹窗
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认版本'),
        content: Text('确定要下载 $version 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // 步骤 2：创建实例并导航到下载页
    final name = _nameController.text.trim();
    try {
      final instance = await _instanceController.createInstance(name);
      if (!mounted) return;
      _instanceId = instance.id;
      _selectedVersion = version;
      setState(() => _step = _WizardStep.downloading);
      // 步骤 3：在下载页内获取下载信息并下载
      await _fetchAndDownload(instance.id, version);
    } on DuplicateInstanceNameException {
      if (!mounted) return;
      _showDuplicateDialog(name);
    }
  }

  /// 在下载页中先获取下载信息，再执行下载。
  Future<void> _fetchAndDownload(String instanceId, String version) async {
    setState(() {
      _downloadProgress = null;
      _downloadError = null;
    });

    _DownloadInfo info;
    try {
      info = await _fetchDownloadInfo(version);
    } catch (e) {
      if (!mounted) return;
      setState(() => _downloadError = '获取下载信息失败：$e');
      return;
    }

    await _downloadJar(instanceId, info);
  }

  Future<void> _downloadJar(String instanceId, _DownloadInfo info) async {
    setState(() {
      _downloadProgress = null;
      _downloadError = null;
    });

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(info.url));
      final response = await request.close();

      if (response.statusCode != 200) {
        if (!mounted) return;
        setState(() => _downloadError = '下载失败（HTTP ${response.statusCode}）');
        return;
      }

      final instance = _instanceController.instances
          .firstWhere((i) => i.id == instanceId);
      final dir = await _instanceController.directoryFor(instance);
      final file = File(p.join(dir.path, 'server.jar'));

      final contentLength = response.contentLength;
      int received = 0;

      // 流式下载并记录所有字节用于哈希校验。
      final sink = file.openWrite();
      final allBytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        received += chunk.length;
        allBytes.add(chunk);
        if (contentLength > 0 && mounted) {
          setState(() => _downloadProgress = received / contentLength);
        }
        sink.add(chunk);
      }
      await sink.close();

      // 校验哈希。
      final hashOk = _verifyHash(allBytes.toBytes(), info);
      if (!hashOk) {
        await file.delete();
        if (!mounted) return;
        setState(() => _downloadError = '文件哈希校验失败，请重试');
        return;
      }

      final mcVersion = _selectedVersion ?? '';
      final javaVer = _javaVersionForMc(mcVersion);
      await _instanceController.updateConfig(
        instanceId,
        selectedJar: 'server.jar',
        javaVersion: javaVer,
      );

      _completed = true;
      if (mounted) _finishWizard();
    } catch (e) {
      if (!mounted) return;
      setState(() => _downloadError = '下载失败：$e');
    } finally {
      client.close();
    }
  }

  /// 根据 MC 版本号推断所需的 Java 版本（已移除 jre8）。
  ///
  /// MC 26+（年份命名）          → jre25
  /// MC 1.20.5 - 1.21.11（含边界） → jre21
  /// MC ≤1.20.4                  → jre17
  static String _javaVersionForMc(String mcVersion) {
    final parts = mcVersion.split('.');
    if (parts.isEmpty) return 'jre17';
    final major = int.tryParse(parts[0]) ?? 1;
    // Mojang 新版本采用年份开头（如 26 = 2026 年），统一使用 jre25。
    if (major >= 26) return 'jre25';
    if (major == 1) {
      final minor = parts.length >= 2 ? (int.tryParse(parts[1]) ?? 0) : 0;
      final patch = parts.length >= 3 ? (int.tryParse(parts[2]) ?? 0) : 0;
      // 1.20.5 ≤ version ≤ 1.21.11 → jre21
      if (minor > 21) return 'jre21';
      if (minor == 21 && patch <= 11) return 'jre21';
      if (minor == 20 && patch >= 5) return 'jre21';
      return 'jre17';
    }
    return 'jre17';
  }

  /// 根据下载信息校验文件哈希（Vanilla 用 SHA-1，Paper 用 SHA-256）。
  bool _verifyHash(Uint8List bytes, _DownloadInfo info) {
    if (info.sha1 != null) {
      final digest = sha1.convert(bytes).toString();
      return digest == info.sha1;
    } else if (info.sha256 != null) {
      final digest = sha256.convert(bytes).toString();
      return digest == info.sha256;
    }
    return true; // 无校验信息时视为通过。
  }

  void _onBack() {
    switch (_step) {
      case _WizardStep.nameEntry:
        _closeWizard();
      case _WizardStep.serverType:
        setState(() => _step = _WizardStep.nameEntry);
      case _WizardStep.versionSelect:
        setState(() => _step = _WizardStep.serverType);
      case _WizardStep.importFile:
        // 导入流程已创建实例，返回时删除空实例并关闭向导。
        _deleteCreatedInstance();
        _closeWizard();
      case _WizardStep.downloading:
        // 下载流程已创建实例，返回时删除空实例并关闭向导。
        _deleteCreatedInstance();
        _closeWizard();
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

  Future<void> _showDuplicateDialog(String name) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: Text('已存在同名实例：$name'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
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
        body: SafeArea(
          child: _buildStepContent(theme),
        ),
      ),
    );
  }

  String get _appBarTitle {
    return switch (_step) {
      _WizardStep.nameEntry => '新建实例',
      _WizardStep.serverType => '下载服务端',
      _WizardStep.versionSelect => '选择版本',
      _WizardStep.downloading => '下载中',
      _WizardStep.importFile => '导入服务端',
    };
  }

  Widget _buildStepContent(ThemeData theme) {
    return switch (_step) {
      _WizardStep.nameEntry => _buildNameEntry(theme),
      _WizardStep.serverType => _buildServerTypeSelect(theme),
      _WizardStep.versionSelect => _buildVersionSelect(theme),
      _WizardStep.downloading => _buildDownloading(theme),
      _WizardStep.importFile => _buildImporting(theme),
    };
  }

  /// 步骤 1：名称输入 + 两个大选项卡。
  Widget _buildNameEntry(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '名称',
              hintText: '请输入实例名称',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          _ServerTypeTile(
            icon: Icons.cloud_download_outlined,
            title: '下载服务端',
            subtitle: '从官方端或 Paper 端选择版本下载',
            onTap: _goToServerType,
          ),
          const SizedBox(height: 12),
          _ServerTypeTile(
            icon: Icons.file_upload_outlined,
            title: '导入服务端',
            subtitle: '从本地导入已有的 jar / phar 文件',
            onTap: _startImport,
          ),
          const SizedBox(height: 12),
          _ServerTypeTile(
            icon: Icons.create_new_folder_outlined,
            title: '创建空实例',
            subtitle: '创建一个空实例，稍后手动添加 jar',
            onTap: _createEmptyInstance,
          ),
        ],
      ),
    );
  }

  /// 步骤 2a：服务端类型选择（官方端 / Paper 端）。
  Widget _buildServerTypeSelect(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 8),
        _ServerTypeTile(
          icon: Icons.storage_outlined,
          title: '官方端',
          subtitle: 'Minecraft 原版服务端',
          onTap: () => _selectServerType('vanilla'),
        ),
        const SizedBox(height: 12),
        _ServerTypeTile(
          icon: Icons.article_outlined,
          title: 'Paper 端',
          subtitle: '高性能优化服务端',
          onTap: () => _selectServerType('paper'),
        ),
      ],
    );
  }

  /// 步骤 3a：版本列表选择。
  Widget _buildVersionSelect(ThemeData theme) {
    if (_loadingVersions) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_versionError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text(
                _versionError!,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => _selectServerType(_serverType!),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_versions.isEmpty) {
      return const Center(child: Text('没有可用版本'));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _versions.length,
      itemBuilder: (_, i) {
        final v = _versions[i];
        return ListTile(
          title: Text(v),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _selectVersion(v),
        );
      },
    );
  }

  /// 步骤 4a：下载进度页。
  Widget _buildDownloading(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    value: _downloadProgress,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  _downloadProgress != null ? '正在下载服务端…' : '正在准备下载…',
                  style: theme.textTheme.titleMedium,
                ),
                if (_downloadProgress != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${(_downloadProgress! * 100).toStringAsFixed(1)}%',
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
                if (_downloadError != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _downloadError!,
                    style: TextStyle(color: theme.colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton(
                        onPressed: () {
                          _deleteCreatedInstance();
                          _closeWizard();
                        },
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: () {
                          _deleteCreatedInstance();
                          setState(() => _step = _WizardStep.versionSelect);
                        },
                        child: const Text('重新选择'),
                      ),
                    ],
                  ),
                ] else ...[
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () {
                      _deleteCreatedInstance();
                      _closeWizard();
                    },
                    child: const Text('取消'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 步骤 2b：导入中提示。
  Widget _buildImporting(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(
            '请选择要导入的服务端 jar 文件',
            style: theme.textTheme.titleMedium,
          ),
        ],
      ),
    );
  }

  // —— 网络请求 ——

  Future<List<String>> _fetchVersions(String type) async {
    if (type == 'vanilla') {
      return _fetchVanillaVersions();
    } else {
      return _fetchPaperVersions();
    }
  }

  /// 获取官方端版本列表，同时缓存每个版本的详情 URL。
  Future<List<String>> _fetchVanillaVersions() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse(
            'https://launchermeta.mojang.com/mc/game/version_manifest.json'),
      );
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final versions = json['versions'] as List<dynamic>;
      final releases = versions.where((v) => v['type'] == 'release').toList();

      _vanillaVersionUrls = {
        for (final v in releases) v['id'] as String: v['url'] as String,
      };

      return releases.map<String>((v) => v['id'] as String).toList();
    } finally {
      client.close();
    }
  }

  /// 获取 Paper 端版本列表，过滤掉含 rc/pre 的预发布版本。
  Future<List<String>> _fetchPaperVersions() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse('https://api.papermc.io/v2/projects/paper'),
      );
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final versions = json['versions'] as List<dynamic>;
      return versions
          .where((v) {
            final lower = (v as String).toLowerCase();
            return !lower.contains('rc') && !lower.contains('pre');
          })
          .toList()
          .reversed
          .map<String>((v) => v as String)
          .toList();
    } finally {
      client.close();
    }
  }

  /// 根据服务端类型获取指定版本的下载信息。
  Future<_DownloadInfo> _fetchDownloadInfo(String version) async {
    if (_serverType == 'vanilla') {
      return _fetchVanillaDownloadInfo(version);
    } else {
      return _fetchPaperDownloadInfo(version);
    }
  }

  /// 从版本详情 JSON 获取官方端服务端的真实下载 URL 和 SHA-1。
  Future<_DownloadInfo> _fetchVanillaDownloadInfo(String version) async {
    final detailUrl = _vanillaVersionUrls[version];
    if (detailUrl == null) {
      throw Exception('未找到版本 $version 的详情地址');
    }
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(detailUrl));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final server = json['downloads']?['server'];
      if (server == null) {
        throw Exception('该版本没有服务端 JAR');
      }
      return _DownloadInfo(
        url: server['url'] as String,
        sha1: server['sha1'] as String?,
      );
    } finally {
      client.close();
    }
  }

  /// 通过 Paper API 获取最新构建的下载 URL 和 SHA-256。
  Future<_DownloadInfo> _fetchPaperDownloadInfo(String version) async {
    const base = 'https://api.papermc.io/v2/projects/paper';
    final client = HttpClient();
    try {
      // 获取该版本的构建列表。
      final verReq = await client.getUrl(Uri.parse('$base/versions/$version'));
      final verRes = await verReq.close();
      final verBody = await verRes.transform(utf8.decoder).join();
      final verJson = jsonDecode(verBody) as Map<String, dynamic>;
      final builds = verJson['builds'] as List<dynamic>;
      if (builds.isEmpty) {
        throw Exception('该版本没有任何构建');
      }
      final latestBuild = builds.cast<int>().reduce((a, b) => a > b ? a : b);

      // 获取最新构建的下载信息。
      final buildReq = await client.getUrl(
        Uri.parse('$base/versions/$version/builds/$latestBuild'),
      );
      final buildRes = await buildReq.close();
      final buildBody = await buildRes.transform(utf8.decoder).join();
      final buildJson = jsonDecode(buildBody) as Map<String, dynamic>;
      final app = buildJson['downloads']?['application'];
      if (app == null) {
        throw Exception('该构建没有 application JAR');
      }
      final jarName = app['name'] as String;
      final sha256 = app['sha256'] as String?;
      return _DownloadInfo(
        url: '$base/versions/$version/builds/$latestBuild/downloads/$jarName',
        sha256: sha256,
      );
    } finally {
      client.close();
    }
  }
}

/// 服务端 JAR 的下载信息。
class _DownloadInfo {
  const _DownloadInfo({required this.url, this.sha1, this.sha256});

  final String url;
  final String? sha1;
  final String? sha256;
}

/// 服务端类型选择项。
class _ServerTypeTile extends StatelessWidget {
  const _ServerTypeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, size: 36),
        title: Text(title, style: const TextStyle(fontSize: 16)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: onTap,
      ),
    );
  }
}
