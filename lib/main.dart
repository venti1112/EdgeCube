import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:logging/logging.dart';

import 'backup/backup_controller.dart';
import 'backup/backup_scope.dart';
import 'config/ddns_store.dart';
import 'config/network_store.dart';
import 'config/stun_store.dart';
import 'config/version_store.dart';
import 'server/runtime_migration.dart';
import 'files/storage_permission.dart';
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
import 'widgets/miuix_snackbar.dart';
import 'theme/theme_scope.dart';
import 'theme/theme_store.dart';
import 'theme/system_color.dart';
import 'theme/precipitation_effect_mode.dart';
import 'widgets/precipitation_overlay.dart';

Future<void> main() async {
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      // 初始化 .ecpkg 文件关联处理器
      EcpkgHandler.init();
      // 初始化软件日志系统（默认关闭，按设置中配置生效）
      await LogService.instance.init();
      // 安装全局异常捕获：Flutter 框架错误 + 平台异步错误
      _setupGlobalErrorHandlers();
      await _bootstrap();
    },
    (error, stack) {
      // Zone 末梢兜底：捕获上述处理器未能拦截的异步错误
      Logger('ZoneGuard').severe('Uncaught async error', error, stack);
    },
  );
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
    Logger(
      'FlutterError',
    ).severe(details.exceptionAsString(), details.exception, details.stack);
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
    await _bootSafe('旧运行时清理', RuntimeMigration.clearOldRuntimes);
  }
  // 记录本次启动的版本到 config/version.json（更新 lastVersion 并追加历史）。
  await _bootSafe('版本记录', VersionStore.recordOpen);
  // 多语言：加载已选语言与内置/自定义翻译表，须先于首帧渲染。
  final localeController = LocaleController();
  await _bootSafe('多语言', localeController.init);
  final initialThemeMode = await ThemeStore.load();
  final initialSeedColor = await ThemeStore.loadSeedColor();
  final initialUseDynamicColor = await ThemeStore.loadUseDynamicColor();
  // 跟随系统主题色：开关已开启时先读一次系统种子色，让首帧就用正确配色，
  // 否则会先按用户自选色渲染再跳变。读不到（Android 12 以下）时保持 null，
  // 由 UI 层回退到自选种子色。
  final initialSystemSeedColor = initialUseDynamicColor
      ? await loadSystemSeedColor()
      : null;
  if (initialUseDynamicColor && initialSystemSeedColor == null) {
    Logger('Boot').warning('系统主题色不可用（Android 12 以下或读取失败），回退到自选种子色');
  }
  final initialSnowfallEnabled = await ThemeStore.loadSnowfallEnabled();
  final initialPrecipitationMode = await ThemeStore.loadPrecipitationMode();
  final initialFloatingNavBarEnabled =
      await ThemeStore.loadFloatingNavBarEnabled();
  final instanceController = InstanceController();
  // 外部存储权限未授予时跳过实例目录遍历：低版本 Android 上对未授权的
  // /storage/emulated/0 目录做 list() 会直接抛 EACCES 权限异常（而非静默
  // 返回空），若任其向上抛，_bootstrap 中断、runApp 永远执行不到，设备上
  // 就只剩启动白屏。授权完成后由 HomeShell 启动流程补扫（见
  // _syncInstancesAfterPermissionGrant）。
  if (await StoragePermission.isGranted()) {
    await _bootSafe('实例索引', instanceController.init);
  }
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
  await _bootSafe('FTP', ftpController.init);
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
  await _bootSafe('MCP 服务', mcpController.init);
  // 交互式 shell 终端：进程在原生侧为单例，控制器只负责终端 I/O 与状态同步。
  final shellController = ShellController();
  await _bootSafe('交互式 Shell', shellController.init);
  // SSH 服务：同一服务器提供 SFTP 文件访问与 SSH 终端，根目录跟随当前实例目录。
  final sshController = SshController();
  await _bootSafe('SSH 服务', sshController.init);
  await _syncSshRootDir(instanceController, sshController);
  instanceController.addListener(() {
    _syncSshRootDir(instanceController, sshController);
  });
  // FRP 映射隧道：多供应商隧道管理；进程仍由 serverController 独占。
  final frpController = FrpController(server: serverController);
  // 定时备份：前台定时检查 + 启动时补做，依赖实例控制器解析目录。
  final backupController = BackupController(
    instanceController: instanceController,
  );
  await _bootSafe('定时备份', backupController.init);
  runApp(
    EdgeCubeApp(
      initialThemeMode: initialThemeMode,
      initialSeedColor: initialSeedColor,
      initialUseDynamicColor: initialUseDynamicColor,
      initialSystemSeedColor: initialSystemSeedColor,
      initialSnowfallEnabled: initialSnowfallEnabled,
      initialPrecipitationMode: initialPrecipitationMode,
      initialFloatingNavBarEnabled: initialFloatingNavBarEnabled,
      localeController: localeController,
      instanceController: instanceController,
      serverController: serverController,
      systemMonitorController: systemMonitorController,
      ftpController: ftpController,
      mcpController: mcpController,
      shellController: shellController,
      sshController: sshController,
      frpController: frpController,
      backupController: backupController,
    ),
  );
}

/// 执行一步启动初始化；单个组件失败只记日志、不中断启动流程。
///
/// 启动阶段任何一步抛异常而未被捕获，都会让 [_bootstrap] 中断、[runApp]
/// 永远执行不到——设备上只有一片白屏。所有组件初始化统一走这里兜底。
Future<void> _bootSafe(String component, Future<void> Function() action) async {
  try {
    await action();
  } catch (e, s) {
    Logger('Boot').severe('$component 初始化失败，已跳过', e, s);
  }
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
    this.initialSystemSeedColor,
    this.initialSnowfallEnabled = false,
    this.initialPrecipitationMode = PrecipitationEffectMode.snow,
    this.initialFloatingNavBarEnabled = false,
    required this.localeController,
    required this.instanceController,
    required this.serverController,
    required this.systemMonitorController,
    required this.ftpController,
    required this.mcpController,
    required this.shellController,
    required this.sshController,
    required this.frpController,
    required this.backupController,
  });

  final ThemeMode initialThemeMode;
  final Color initialSeedColor;
  final bool initialUseDynamicColor;

  /// 启动时读到的系统主题色种子；开启「跟随系统主题色」但读不到时为 null。
  final Color? initialSystemSeedColor;
  final bool initialSnowfallEnabled;
  final PrecipitationEffectMode initialPrecipitationMode;
  final bool initialFloatingNavBarEnabled;
  final LocaleController localeController;
  final InstanceController instanceController;
  final ServerController serverController;
  final SystemMonitorController systemMonitorController;
  final FtpController ftpController;
  final McpController mcpController;
  final ShellController shellController;
  final SshController sshController;
  final FrpController frpController;
  final BackupController backupController;

  @override
  State<EdgeCubeApp> createState() => _EdgeCubeAppState();
}

class _EdgeCubeAppState extends State<EdgeCubeApp> {
  late ThemeMode _themeMode = widget.initialThemeMode;
  late Color _seedColor = widget.initialSeedColor;
  late bool _useDynamicColor = widget.initialUseDynamicColor;

  /// 当前生效的系统主题色种子（开启跟随时使用）。
  late Color? _systemSeedColor = widget.initialSystemSeedColor;

  /// 生命周期监听：换壁纸后系统主色板会变，回前台时补读一次。
  late final AppLifecycleListener _lifecycleListener;

  late bool _snowfallEnabled = widget.initialSnowfallEnabled;
  late PrecipitationEffectMode _precipitationMode =
      widget.initialPrecipitationMode;
  late bool _floatingNavBarEnabled = widget.initialFloatingNavBarEnabled;

  @override
  void initState() {
    super.initState();
    // 语言切换时重建整棵树，使 MaterialApp.locale 与全部文案随之更新。
    widget.localeController.addListener(_onLocaleChanged);
    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        // 只在跟随系统主题色时补读：换壁纸后系统主色板才会变。
        if (_useDynamicColor) _refreshSystemSeedColor();
      },
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
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
    // 启动阶段只在开关已开启时预读过，首次打开开关时补读。
    if (value) _refreshSystemSeedColor();
  }

  /// 补读系统主题色种子；仅在结果发生变化时重建，避免无谓刷新。
  Future<void> _refreshSystemSeedColor() async {
    final seed = await loadSystemSeedColor();
    if (!mounted || seed == null || seed == _systemSeedColor) return;
    setState(() => _systemSeedColor = seed);
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

  void _setFloatingNavBarEnabled(bool value) {
    if (value == _floatingNavBarEnabled) return;
    setState(() => _floatingNavBarEnabled = value);
    ThemeStore.saveFloatingNavBarEnabled(value);
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
        floatingNavBarEnabled: _floatingNavBarEnabled,
        setFloatingNavBarEnabled: _setFloatingNavBarEnabled,
        child: InstanceScope(
          controller: widget.instanceController,
          child: BackupScope(
            controller: widget.backupController,
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
                          child: MiuixThemeController(
                            colorSchemeMode: MiuixColorSchemeMode.monetSystem,
                            keyColor: _useDynamicColor
                                ? (_systemSeedColor ?? _seedColor)
                                : _seedColor,
                            isDark: switch (_themeMode) {
                              ThemeMode.system => null,
                              ThemeMode.light => false,
                              ThemeMode.dark => true,
                            },
                            child: Builder(
                              builder: (context) {
                                final miuix = MiuixTheme.of(context);
                                return MaterialApp(
                                  title: 'EdgeCube',
                                  localizationsDelegates:
                                      GlobalMaterialLocalizations.delegates,
                                  supportedLocales:
                                      widget.localeController.supportedLocales,
                                  locale: widget.localeController.locale,
                                  theme: ThemeData(
                                    useMaterial3: true,
                                    brightness: miuix.brightness,
                                    colorScheme: ColorScheme.fromSeed(
                                      seedColor: miuix.colors.primary,
                                      brightness: miuix.brightness,
                                    ),
                                  ),
                                  navigatorObservers: [appRouteObserver],
                                  builder: (context, child) {
                                    Widget content =
                                        child ?? const SizedBox.shrink();
                                    content = Material(
                                      type: MaterialType.transparency,
                                      child: content,
                                    );
                                    content = MiuixContentColor(
                                      color: miuix.colors.onBackground,
                                      child: content,
                                    );
                                    if (_snowfallEnabled) {
                                      content = Stack(
                                        children: [
                                          content,
                                          Positioned.fill(
                                            child: PrecipitationOverlay(
                                              mode: _precipitationMode,
                                            ),
                                          ),
                                        ],
                                      );
                                    }
                                    return MiuixSnackbarOverlay(child: content);
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
        ),
      ),
    );
  }
}
