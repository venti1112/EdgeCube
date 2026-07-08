import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../config/network_store.dart';
import '../i18n/locale_scope.dart';
import '../instance/instance_controller.dart';
import '../net/msl_mirror.dart';
import '../server/server_service.dart';
import 'download_info.dart';
import 'progress_steps.dart';

class ForgeInstallerPage extends StatefulWidget {
  const ForgeInstallerPage({
    super.key,
    required this.instanceController,
    required this.instanceId,
    required this.mcVersion,
    required this.forgeVersion,
    required this.installerType,
  });

  final InstanceController instanceController;
  final String instanceId;
  final String mcVersion;
  final String forgeVersion;
  final String installerType; // 'forge' or 'neoforge'

  @override
  State<ForgeInstallerPage> createState() => _ForgeInstallerPageState();
}

class _ForgeInstallerPageState extends State<ForgeInstallerPage> {
  double? _downloadProgress;
  String? _downloadError;
  bool _installing = false;
  final List<String> _installLogs = [];
  String? _installError;
  StreamSubscription<dynamic>? _eventSub;

  static const _forgeChannel = MethodChannel('com.venti1112.edgecube/forge');
  static const _forgeEventChannel = EventChannel(
    'com.venti1112.edgecube/forge_events',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _downloadProgress = null;
      _downloadError = null;
    });

    final info = await _tryMirrorDownloadInfo() ??
        _defaultDownloadInfo();
    if (!mounted) return;

    await _downloadJar(info);
  }

  Future<DownloadInfo?> _tryMirrorDownloadInfo() async {
    if (!await NetworkStore.loadUseMirror()) return null;
    final key = widget.installerType == 'neoforge'
        ? _neoforgeMcToMslVersion(widget.mcVersion)
        : widget.mcVersion;
    final info = await MslMirror.fetchDownloadInfo(widget.installerType, key);
    if (info == null) return null;
    return DownloadInfo(url: info.url, sha256: info.sha256);
  }

  DownloadInfo _defaultDownloadInfo() {
    if (widget.installerType == 'forge') {
      return DownloadInfo(
        url:
            'https://maven.minecraftforge.net/net/minecraftforge/forge/${widget.mcVersion}-${widget.forgeVersion}/forge-${widget.mcVersion}-${widget.forgeVersion}-installer.jar',
      );
    }
    return DownloadInfo(
      url:
          'https://maven.neoforged.net/releases/net/neoforged/neoforge/${widget.forgeVersion}/neoforge-${widget.forgeVersion}-installer.jar',
    );
  }

  String _neoforgeMcToMslVersion(String key) {
    final major = int.tryParse(key.split('.').first) ?? 0;
    return major >= 26 ? key : '1.$key';
  }

  Future<void> _downloadJar(DownloadInfo info) async {
    final installerJar = widget.installerType == 'forge'
        ? 'forge-installer.jar'
        : 'neoforge-installer.jar';

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(info.url));
      final response = await request.close();

      if (response.statusCode != 200) {
        if (!mounted) return;
        setState(
          () => _downloadError = context.tr('instance.downloadFailedHttp', {
            'status': '${response.statusCode}',
          }),
        );
        return;
      }

      final dir = await widget.instanceController.directoryForId(
        widget.instanceId,
      );
      final file = File(p.join(dir.path, installerJar));

      final contentLength = response.contentLength;
      int received = 0;

      final sink = file.openWrite();
      await for (final chunk in response) {
        received += chunk.length;
        if (contentLength > 0 && mounted) {
          setState(
            () => _downloadProgress = received / contentLength,
          );
        }
        sink.add(chunk);
      }
      await sink.close();

      if (!mounted) return;
      await _runInstaller(file.path);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _downloadError = context.tr('instance.downloadFailed', {
          'error': '$e',
        }),
      );
    } finally {
      client.close();
    }
  }

  Future<void> _runInstaller(String installerPath) async {
    setState(() {
      _installing = true;
      _installError = null;
      _installLogs.clear();
    });

    _eventSub = _forgeEventChannel.receiveBroadcastStream().listen((event) {
      if (mounted && event is String) {
        setState(() {
          _installLogs.add(event);
          if (_installLogs.length > 200) {
            _installLogs.removeRange(0, _installLogs.length - 200);
          }
        });
      }
    });

    try {
      final javaVer = await _resolveJavaVersion(_mcVersionForJava());

      final exitCode = await _forgeChannel.invokeMethod<int>('runInstaller', {
        'installerJar': installerPath,
        'workingDir': (await widget.instanceController.directoryForId(
          widget.instanceId,
        )).path,
        'javaVersion': javaVer,
      });

      await _eventSub?.cancel();
      _eventSub = null;

      if (exitCode != 0) {
        if (!mounted) return;
        setState(() {
          _installing = false;
          _installError = context.tr('instance.forgeInstallerExited', {
            'code': '$exitCode',
          });
        });
        return;
      }

      final prefix = widget.installerType == 'forge' ? 'forge-' : 'neoforge-';
      final dir = await widget.instanceController.directoryForId(
        widget.instanceId,
      );
      final serverJar = _findServerJar(dir, prefix: prefix);
      if (serverJar == null) {
        if (!mounted) return;
        setState(() {
          _installing = false;
          _installError = context.tr('instance.serverJarNotFound');
        });
        return;
      }

      await widget.instanceController.updateConfig(
        widget.instanceId,
        selectedJar: serverJar,
        javaVersion: javaVer,
      );

      try {
        await File(p.join(dir.path, installerPath.split(p.separator).last))
            .delete();
      } catch (_) {}

      if (mounted) {
        setState(() => _installing = false);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      await _eventSub?.cancel();
      _eventSub = null;
      if (!mounted) return;
      setState(() {
        _installing = false;
        _installError = context.tr('instance.forgeInstallFailed', {
          'error': '$e',
        });
      });
    }
  }

  String? _findServerJar(Directory dir, {String prefix = 'forge-'}) {
    final files = dir.listSync();
    String? serverJar;
    for (final f in files) {
      if (f is! File) continue;
      final name = p.basename(f.path);
      if (name == 'forge-installer.jar') continue;
      if (name == 'neoforge-installer.jar') continue;
      if (name == 'server.jar') continue;
      if (name.startsWith(prefix) && name.endsWith('.jar')) {
        serverJar = name;
      }
    }
    return serverJar;
  }

  static String _javaVersionForMc(String mcVersion) {
    final majorStr = mcVersion.split('.').first;
    final major = int.tryParse(majorStr) ?? 0;
    if (major >= 26) return 'jre25';
    if (major >= 21) return 'jre21';
    if (major >= 18) return 'jre17';
    if (major >= 17) return 'jre16';
    return 'jre8';
  }

  /// 将 Forge/NeoForge 的 MC 版本键转换为 Java 版本检测用的 MC 版本号。
  /// NeoForge 使用 "21.1" 格式 → 转为 "1.21.1"（MC < 26）。
  String _mcVersionForJava() {
    if (widget.installerType != 'neoforge') return widget.mcVersion;
    final parts = widget.mcVersion.split('.');
    final major = int.tryParse(parts[0]) ?? 1;
    if (major >= 26) return widget.mcVersion;
    if (parts.length >= 2) return '1.${parts[0]}.${parts[1]}';
    return widget.mcVersion;
  }

  static Future<String> _resolveJavaVersion(String mcVersion) async {
    final preferred = _javaVersionForMc(mcVersion);
    final available = await ServerService().availableJreIds();
    if (available.contains(preferred)) return preferred;
    if (available.isEmpty) return preferred;
    return available.first;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.installerType == 'neoforge'
              ? context.tr('instance.titleInstallNeoforge')
              : context.tr('instance.titleInstallForge'),
        ),
      ),
      body: _downloadError != null || _downloadProgress != null
          ? DownloadingStep(
              progress: _downloadProgress,
              error: _downloadError,
              onRetry: () {
                Navigator.of(context).pop(false);
              },
              onCancel: () => Navigator.of(context).pop(false),
            )
          : ForgeInstallingStep(
              logs: _installLogs,
              installing: _installing,
              error: _installError,
              installerType: widget.installerType,
              onCancel: () => Navigator.of(context).pop(false),
              onReselect: () => Navigator.of(context).pop(false),
            ),
    );
  }
}
