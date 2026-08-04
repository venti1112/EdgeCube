import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:path/path.dart' as p;

import '../files/archive_service.dart';
import '../i18n/locale_scope.dart';
import '../net/download_engine.dart';
import '../net/download_exceptions.dart';
import '../widgets/ec_preference.dart';
import 'download_info.dart';
import 'download_info_service.dart';
import 'download_runner.dart';
import 'download_session.dart';
import 'instance_controller.dart';
import 'progress_steps.dart';

/// 流程第 6 页：下载。
///
/// 承接前序页面的选择，按服务端类型执行下载并写入实例配置，完成后通过
/// [finishDownloadFlow] 一次性弹回流程根页并返回 done。
///
/// [instanceId] 由上一页创建实例后传入；BungeeCord 无版本选择，直接由本页在
/// [initState] 中创建实例。
///
/// Survivalcraft 特殊：下载压缩包到临时文件后解压到 proot 容器目录（带解压进度）。
///
/// 用户中途退出（未完成）时，[dispose] 会清理已创建的空实例。
class DownloadProgressPage extends StatefulWidget {
  const DownloadProgressPage({
    super.key,
    required this.session,
    this.instanceId,
  });

  final DownloadSession session;
  final String? instanceId;

  @override
  State<DownloadProgressPage> createState() => _DownloadProgressPageState();
}

class _DownloadProgressPageState extends State<DownloadProgressPage> {
  DownloadSession get _session => widget.session;
  InstanceController get _controller => _session.controller;
  String get _serverType => _session.serverType ?? '';

  String? _instanceId;
  bool _completed = false;

  DownloadProgress? _downloadProgress;
  String? _downloadError;

  // Survivalcraft 解压阶段状态。
  bool _extracting = false;
  double? _extractProgress;
  String? _extractError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    // 未完成且已创建实例：清理空实例。
    if (!_completed && _instanceId != null) {
      _controller.deleteInstance(_instanceId!);
    }
    super.dispose();
  }

  Future<void> _start() async {
    // BungeeCord 直接在本页创建实例；其余类型由上一页创建并传入。
    if (widget.instanceId == null) {
      try {
        final instance = await _controller.createInstance(_session.name);
        _instanceId = instance.id;
      } on DuplicateInstanceNameException {
        if (!mounted) return;
        setState(() {
          _downloadError = context.tr('instance.duplicateName', {
            'name': _session.name,
          });
        });
        return;
      }
    } else {
      _instanceId = widget.instanceId;
    }
    if (!mounted) return;
    await _run();
  }

  Future<void> _run() async {
    setState(() {
      _downloadProgress = null;
      _downloadError = null;
    });
    switch (_serverType) {
      case 'survivalcraft':
        await _downloadSurvivalcraft();
      case 'fabric':
        await _downloadFabric();
      case 'bungeecord':
        await _downloadBungeeCord();
      default:
        await _downloadSimple();
    }
  }

  // —— 各类型下载 ——

  Future<void> _downloadSimple() async {
    final version = _session.selectedVersion!;
    DownloadInfo info;
    try {
      info =
          await DownloadRunner.tryMirrorDownloadInfo(_serverType, version) ??
          await DownloadRunner.fetchDownloadInfo(
            _serverType,
            version,
            _session.vanillaVersionUrls,
          );
    } catch (e) {
      if (!mounted) return;
      _setDownloadError(
        context.tr('instance.fetchDownloadInfoFailed', {'error': '$e'}),
      );
      return;
    }

    final String serverFileName;
    if (_serverType == 'powernukkitx') {
      serverFileName = 'powernukkitx.jar';
    } else if (_serverType == 'pocketmine') {
      serverFileName = 'PocketMine-MP.phar';
    } else if (_serverType == 'allay') {
      serverFileName = 'allay-server.jar';
    } else {
      serverFileName = 'server.jar';
    }
    await _download(info, serverFileName);
  }

  Future<void> _downloadFabric() async {
    DownloadInfo info;
    try {
      info =
          await DownloadRunner.tryMirrorDownloadInfo(
            'fabric',
            _session.selectedMcVersion!,
          ) ??
          await DownloadRunner.fetchFabricDownloadInfo(
            _session.selectedMcVersion!,
            _session.selectedLoaderVersion!,
          );
    } catch (e) {
      if (!mounted) return;
      _setDownloadError(
        context.tr('instance.fetchDownloadInfoFailed', {'error': '$e'}),
      );
      return;
    }
    await _download(info, 'server.jar');
  }

  Future<void> _downloadBungeeCord() async {
    DownloadInfo info;
    try {
      info =
          await DownloadRunner.tryMirrorDownloadInfo('bungeecord', 'latest') ??
          await DownloadInfoService.fetchBungeeCordDownloadInfo();
    } catch (e) {
      if (!mounted) return;
      _setDownloadError(
        context.tr('instance.fetchDownloadInfoFailed', {'error': '$e'}),
      );
      return;
    }
    await _download(info, 'bungeecord.jar');
  }

  /// 通用下载：下载服务端文件 → 校验 → 写配置 → 结束流程。
  Future<void> _download(DownloadInfo info, String serverFileName) async {
    try {
      await DownloadRunner.downloadAndConfigure(
        controller: _controller,
        instanceId: _instanceId!,
        info: info,
        serverType: _serverType,
        serverFileName: serverFileName,
        selectedVersion: _session.selectedVersion,
        selectedMcVersion: _session.selectedMcVersion,
        onProgress: (prog) {
          if (mounted) setState(() => _downloadProgress = prog);
        },
      );
      _completed = true;
      if (mounted) finishDownloadFlow(context);
    } on DownloadHttpException catch (e) {
      if (!mounted) return;
      _setDownloadError(
        context.tr('instance.downloadFailedHttp', {
          'status': '${e.statusCode}',
        }),
      );
    } on HashMismatchException {
      if (!mounted) return;
      _setDownloadError(context.tr('instance.hashVerifyFailed'));
    } catch (e) {
      if (!mounted) return;
      _setDownloadError(context.tr('instance.downloadFailed', {'error': '$e'}));
    }
  }

  /// Survivalcraft：下载服务端压缩包到临时文件，解压到实例目录（proot 容器内）。
  Future<void> _downloadSurvivalcraft() async {
    final version = _session.selectedVersion!;
    DownloadInfo info;
    try {
      info = await DownloadInfoService.fetchSurvivalcraftDownloadInfo(version);
    } catch (e) {
      if (!mounted) return;
      _setDownloadError(
        context.tr('instance.fetchDownloadInfoFailed', {'error': '$e'}),
      );
      return;
    }

    // 下载压缩包到临时文件。
    File? tempFile;
    try {
      final tempDir = await Directory.systemTemp.createTemp('scnet_');
      final tempPath = p.join(tempDir.path, _scArchiveFileName(info.url));
      tempFile = File(tempPath);

      await DownloadEngine.instance.downloadToFile(
        info.url,
        tempPath,
        onProgress: (prog) {
          if (mounted) setState(() => _downloadProgress = prog);
        },
      );
    } on DownloadHttpError catch (e) {
      if (!mounted) return;
      _setDownloadError(
        context.tr('instance.downloadFailedHttp', {
          'status': '${e.statusCode}',
        }),
      );
      return;
    } catch (e) {
      if (!mounted) return;
      _setDownloadError(context.tr('instance.downloadFailed', {'error': '$e'}));
      return;
    }

    final archive = tempFile;
    if (!await archive.exists()) return;

    // 解压到实例目录。
    if (!mounted) return;
    setState(() {
      _extracting = true;
      _extractError = null;
      _extractProgress = null;
    });
    try {
      final dir = await _controller.directoryForId(_instanceId!);
      await ArchiveService.extractWithProgress(
        archive.path,
        dir.path,
        onProgress: (current, total) {
          if (!mounted) return;
          setState(() {
            _extractProgress = total > 0 ? current / total : null;
          });
        },
      );
      try {
        await archive.parent.delete(recursive: true);
      } catch (_) {}

      // 解压完成，强制从磁盘重载实例配置并刷新 UI。
      // 确保控制面板/文件管理在流程返回后拿到最新的 path/runtime/prootStartupCommand，
      // 而不是 initState 时缓存的那个空实例快照。
      await _controller.refreshSelected();
      _completed = true;
      if (mounted) finishDownloadFlow(context);
    } catch (e) {
      try {
        await archive.parent.delete(recursive: true);
      } catch (_) {}
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

  String _scArchiveFileName(String url) {
    try {
      final name = Uri.parse(url).pathSegments.last;
      if (name.isNotEmpty) return name;
    } catch (_) {}
    return 'survivalcraft.zip';
  }

  void _setDownloadError(String message) {
    if (!mounted) return;
    setState(() => _downloadError = message);
  }

  /// 出错后「重新选择」：删除已创建的空实例并返回上一页（版本/加载器页）。
  void _reselect() {
    if (_instanceId != null) {
      _controller.deleteInstance(_instanceId!);
      _instanceId = null;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return MiuixScaffold(
      topBar: MiuixSmallTopAppBar(
        title: _extracting
            ? context.tr('instance.titleImportArchive')
            : context.tr('instance.titleDownloading'),
        navigationIcon: const EcBackButton(),
      ),
      content: (padding) => Padding(
        padding: padding,
        child: SafeArea(
          child: _extracting || _extractError != null
              ? ExtractingArchiveStep(
                  extracting: _extracting,
                  progress: _extractProgress,
                  error: _extractError,
                  onCancel: _reselect,
                  onReselect: _reselect,
                )
              : DownloadingStep(
                  progress: _downloadProgress,
                  error: _downloadError,
                  onRetry: _reselect,
                  onCancel: _reselect,
                ),
        ),
      ),
    );
  }
}
