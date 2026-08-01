import 'dart:async';
import 'dart:ui';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:logging/logging.dart';

import 'config/ddns_store.dart';
import 'config/network_store.dart';
import 'config/stun_store.dart';
import 'config/version_store.dart';
import 'server/runtime_migration.dart';
import 'route_observer.dart';
import 'ftp/ftp_controller.dart';
import 'ftp/ftp_scope.dart';
import 'frp/frp_controller.dart';
import 'frp/frp_default_tunnel.dart';
import 'frp/frp_scope.dart';
import 'home_shell.dart';
import 'i18n/locale_controller.dart';
import 'i18n/locale_scope.dart';
import 'instance/instance_controller.dart';
import 'logging/log_service.dart';
import 'instance/instance_scope.dart';
import 'mcp/mcp_controller.dart';
import 'mcp/mcp_scope.dart';
import 'server/ecpkg_handler.dart';
import 'server/server_controller.dart';
import 'server/server_scope.dart';
import 'server/system_monitor_controller.dart';
import 'server/system_monitor_scope.dart';
import 'shell/shell_controller.dart';
import 'shell/shell_scope.dart';
import 'ssh/ssh_controller.dart';
import 'ssh/ssh_scope.dart';

import 'net/download_engine.dart';
import 'theme/theme_scope.dart';
import 'theme/theme_store.dart';
import 'theme/precipitation_effect_mode.dart';
import 'widgets/precipitation_overlay.dart';

Future<void> main() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // 初始化 .ecpkg 文件关联处理器
    EcpkgHandler.init();
    // 初始化软件日志系统（默认关闭，按设置中配置生效）
    await LogService.instance.init();
    // 安装全局异常捕获：Flutter 框架错误 + 平台异步错误
    _setupGlobalErrorHandlers();
    await _bootstrap();
  }, (error, stack) {
    // Zone 末梢兜底：捕获上述处理器未能拦截的异步错误
    Logger('ZoneGuard').severe('Uncaught async error', error, stack);
  });
}

/// 安装全局异常捕获处理器。
///
/// - [FlutterError.onError]：捕获 Flutter 框架在构建/布局/渲染阶段抛出的错误。
/// - [PlatformDispatcher.instance.onError]：捕获未被 try/catch 拦截的异步错误
///   以及其他 Isolate 抛出的错误。
void _setupGlobalErrorHandlers() {
  // Flutter 框架错误（widget 构建、布局异常等）
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    Logger('FlutterError').severe(
      details.exceptionAsString(),
      details.exception,
      details.stack,
    );
  };
  // 平台层未捕获的异步错误 / Isolate 错误
  PlatformDispatcher.instance.onError = (error, stack) {
    Logger('Platform').severe('Uncaught platform error', error, stack);
    return true; // true 表示已处理，避免应用崩溃退出
  };
}

/// 应用启动主体：在 runZonedGuarded 内执行，确保任何未捕获异常均被记录。
Future<void> _bootstrap() async {
  final lastVersion = await VersionStore.loadLastVersion();
  // 旧版内置于 assets 的运行时与新版 .ecpkg 管理系统冲突，
  // 升级时清除旧 runtimes 目录，让用户重新导入所需运行时。
  if (RuntimeMigration.shouldClearRuntimes(lastVersion)) {
    await RuntimeMigration.clearOldRuntimes();
  }
  // 记录本次启动的版本到 config/version.json（更新 lastVersion 并追加历史）。
  await VersionStore.recordOpen();
  // 多语言：加载已选语言与内置/自定义翻译表，须先于首帧渲染。
  final localeController = LocaleController();
  await localeController.init();
  final initialThemeMode = await ThemeStore.load();
  final initialSeedColor = await ThemeStore.loadSeedColor();
  final initialUseDynamicColor = await ThemeStore.loadUseDynamicColor();
  final initialSnowfallEnabled = await ThemeStore.loadSnowfallEnabled();
  final initialPrecipitationMode = await ThemeStore.loadPrecipitationMode();
  final instanceController = InstanceController();
  await instanceController.init();
  // 预热全局下载引擎（懒初始化，fire-and-forget 不阻塞启动）。
  DownloadEngine.instance.ensureInitialized();
  final serverController = ServerController();
  // 让服务端状态机能查询某实例是否开启兼容模式（兼容模式跳过「启动中」标签）。
  serverController.compatModeResolver = instanceController.compatModeFor;
  // 让服务端退出时能查询某实例是否开启关服自动重启（正常退出时自动重新拉起）。
  serverController.autoRestartOnExitResolver =
      instanceController.autoRestartOnExitFor;
  // UPnP 端口映射开关：读取 config/network.json 中的持久化配置。
  serverController.upnpEnabledResolver = NetworkStore.loadUpnpEnabled;
  serverController.upnpExternalPortResolver = NetworkStore.loadUpnpExternalPort;
  serverController.upnpProtocolResolver = NetworkStore.loadUpnpProtocol;
  // FRP 隧道开关：读取 config/network.json 中的持久化配置。
  serverController.tunnelEnabledResolver = NetworkStore.loadTunnelEnabled;
  // 默认映射隧道：开关打开时随服务端启停的隧道（生成配置并返回路径）。
  serverController.defaultTunnelResolver = FrpDefaultTunnel.resolve;
  // DDNS 动态域名解析：读取 config/ddns.json 中的持久化配置。
  serverController.ddnsConfigResolver = DdnsStore.load;
  // STUN 隧道（NAT1 打洞）：读取 config/stun.json 中的持久化配置。
  serverController.stunConfigResolver = StunStore.load;
  // 崩溃分析按当前语言取规则文案：注入当前生效的 locale 代码。
  serverController.localeResolver = () => localeController.activeLocaleCode;
  final systemMonitorController = SystemMonitorController();
  final ftpController = FtpController();
  await ftpController.init();
  await _syncFtpRootDir(instanceController, ftpController);
  instanceController.addListener(() {
    _syncFtpRootDir(instanceController, ftpController);
  });
  // MCP 服务：让外部 AI Agent 经 Streamable HTTP 获取数据与操作服务。
  // 注入三个控制器以读取状态/操作服务端；init 时若上次为开启状态会自动恢复监听。
  final mcpController = McpController(
    serverController: serverController,
    instanceController: instanceController,
    systemMonitorController: systemMonitorController,
  );
  await mcpController.init();
  // 交互式 shell 终端：进程在原生侧为单例，控制器只负责终端 I/O 与状态同步。
  final shellController = ShellController();
  await shellController.init();
  // SSH 服务：同一服务器提供 SFTP 文件访问与 SSH 终端，根目录跟随当前实例目录。
  final sshController = SshController();
  await sshController.init();
  await _syncSshRootDir(instanceController, sshController);
  instanceController.addListener(() {
    _syncSshRootDir(instanceController, sshController);
  });
  // FRP 映射隧道：多供应商隧道管理；进程仍由 serverController 独占。
  final frpController = FrpController(server: serverController);
  runApp(
    EdgeCubeApp(
      initialThemeMode: initialThemeMode,
      initialSeedColor: initialSeedColor,
      initialUseDynamicColor: initialUseDynamicColor,
      initialSnowfallEnabled: initialSnowfallEnabled,
      initialPrecipitationMode: initialPrecipitationMode,
      localeController: localeController,
      instanceController: instanceController,
      serverController: serverController,
      systemMonitorController: systemMonitorController,
      ftpController: ftpController,
      mcpController: mcpController,
      shellController: shellController,
      sshController: sshController,
      frpController: frpController,
    ),
  );
}

/// 将当前选中实例的工作目录同步为 FTP 根目录。
/// 实例切换后调用，FTP 正在运行时会自动重启以应用新根目录。
Future<void> _syncFtpRootDir(
  InstanceController instances,
  FtpController ftp,
) async {
  final selected = instances.selected;
  if (selected == null) {
    await ftp.setRootDir(null);
    return;
  }
  final dir = await instances.directoryFor(selected);
  await ftp.setRootDir(dir.path);
}

/// 将当前选中实例的工作目录同步为 SSH 服务根目录。
/// 实例切换后调用，SSH 服务正在运行时会自动重启以应用新根目录。
Future<void> _syncSshRootDir(
  InstanceController instances,
  SshController ssh,
) async {
  final selected = instances.selected;
  if (selected == null) {
    await ssh.setRootDir(null);
    return;
  }
  final dir = await instances.directoryFor(selected);
  await ssh.setRootDir(dir.path);
}

class EdgeCubeApp extends StatefulWidget {
  const EdgeCubeApp({
    super.key,
    this.initialThemeMode = ThemeMode.system,
    this.initialSeedColor = ThemeStore.defaultSeedColor,
    this.initialUseDynamicColor = false,
    this.initialSnowfallEnabled = false,
    this.initialPrecipitationMode = PrecipitationEffectMode.snow,
    required this.localeController,
    required this.instanceController,
    required this.serverController,
    required this.systemMonitorController,
    required this.ftpController,
    required this.mcpController,
    required this.shellController,
    required this.sshController,
    required this.frpController,
  });

  final ThemeMode initialThemeMode;
  final Color initialSeedColor;
  final bool initialUseDynamicColor;
  final bool initialSnowfallEnabled;
  final PrecipitationEffectMode initialPrecipitationMode;
  final LocaleController localeController;
  final InstanceController instanceController;
  final ServerController serverController;
  final SystemMonitorController systemMonitorController;
  final FtpController ftpController;
  final McpController mcpController;
  final ShellController shellController;
  final SshController sshController;
  final FrpController frpController;

  @override
  State<EdgeCubeApp> createState() => _EdgeCubeAppState();
}

class _EdgeCubeAppState extends State<EdgeCubeApp> {
  late ThemeMode _themeMode = widget.initialThemeMode;
  late Color _seedColor = widget.initialSeedColor;
  late bool _useDynamicColor = widget.initialUseDynamicColor;
  late bool _snowfallEnabled = widget.initialSnowfallEnabled;
  late PrecipitationEffectMode _precipitationMode =
      widget.initialPrecipitationMode;

  @override
  void initState() {
    super.initState();
    // 语言切换时重建整棵树，使 MaterialApp.locale 与全部文案随之更新。
    widget.localeController.addListener(_onLocaleChanged);
  }

  @override
  void dispose() {
    widget.localeController.removeListener(_onLocaleChanged);
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  void _setThemeMode(ThemeMode mode) {
    if (mode == _themeMode) return;
    setState(() => _themeMode = mode);
    ThemeStore.save(mode);
  }

  void _setSeedColor(Color color) {
    if (color == _seedColor) return;
    setState(() => _seedColor = color);
    ThemeStore.saveSeedColor(color);
  }

  void _setUseDynamicColor(bool value) {
    if (value == _useDynamicColor) return;
    setState(() => _useDynamicColor = value);
    ThemeStore.saveUseDynamicColor(value);
  }

  void _setSnowfallEnabled(bool value) {
    if (value == _snowfallEnabled) return;
    setState(() => _snowfallEnabled = value);
    ThemeStore.saveSnowfallEnabled(value);
  }

  void _setPrecipitationMode(PrecipitationEffectMode mode) {
    if (mode == _precipitationMode) return;
    setState(() => _precipitationMode = mode);
    ThemeStore.savePrecipitationMode(mode);
  }

  @override
  Widget build(BuildContext context) {
    return LocaleScope(
      controller: widget.localeController,
      child: ThemeScope(
        themeMode: _themeMode,
        setThemeMode: _setThemeMode,
        seedColor: _seedColor,
        setSeedColor: _setSeedColor,
        useDynamicColor: _useDynamicColor,
        setUseDynamicColor: _setUseDynamicColor,
        snowfallEnabled: _snowfallEnabled,
        setSnowfallEnabled: _setSnowfallEnabled,
        precipitationMode: _precipitationMode,
        setPrecipitationMode: _setPrecipitationMode,
        child: InstanceScope(
          controller: widget.instanceController,
          child: FtpScope(
            controller: widget.ftpController,
            child: ServerScope(
              controller: widget.serverController,
              child: SystemMonitorScope(
                controller: widget.systemMonitorController,
                child: McpScope(
                  controller: widget.mcpController,
                  child: ShellScope(
                    controller: widget.shellController,
                    child: SshScope(
                      controller: widget.sshController,
                      child: FrpScope(
                        controller: widget.frpController,
                        child: DynamicColorBuilder(
                        builder:
                            (
                              ColorScheme? lightDynamic,
                              ColorScheme? darkDynamic,
                            ) {
                              // 当用户开启「跟随系统主题色」且设备支持动态色时使用系统取色。
                              final useDynamic =
                                  _useDynamicColor && lightDynamic != null;
                              final lightScheme = useDynamic
                                  ? lightDynamic
                                  : ColorScheme.fromSeed(
                                      seedColor: _seedColor,
                                    );
                              final darkScheme = useDynamic
                                  ? (darkDynamic ??
                                        ColorScheme.fromSeed(
                                          seedColor: _seedColor,
                                          brightness: Brightness.dark,
                                        ))
                                  : ColorScheme.fromSeed(
                                      seedColor: _seedColor,
                                      brightness: Brightness.dark,
                                    );

                              return MaterialApp(
                                title: 'EdgeCube',
                                localizationsDelegates: [
                                  GlobalMaterialLocalizations.delegate,
                                  GlobalWidgetsLocalizations.delegate,
                                  GlobalCupertinoLocalizations.delegate,
                                ],
                                supportedLocales:
                                    widget.localeController.supportedLocales,
                                locale: widget.localeController.locale,
                                theme: ThemeData(colorScheme: lightScheme),
                                darkTheme: ThemeData(colorScheme: darkScheme),
                                themeMode: _themeMode,
                                navigatorObservers: [appRouteObserver],
                                builder: (context, child) {
                                  final content =
                                      child ?? const SizedBox.shrink();
                                  if (!_snowfallEnabled) return content;
                                  return Stack(
                                    children: [
                                      content,
                                      Positioned.fill(
                                        child: PrecipitationOverlay(
                                          mode: _precipitationMode,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                                home: const HomeShell(),
                              );
                            },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
