import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:url_launcher/url_launcher.dart';

import 'config/config_store.dart';
import 'config/network_store.dart' show NetworkStore;
import 'config/user_agreement_store.dart';
import 'files/file_browser.dart';
import 'files/storage_permission.dart';
import 'i18n/locale_scope.dart';
import 'online/update_service.dart';
import 'pages/console_page.dart';
import 'pages/files_page.dart';
import 'pages/manage_page.dart';
import 'pages/runtime_page.dart';
import 'pages/server_page.dart';
import 'pages/settings_page.dart';
import 'server/ecpkg_handler.dart';
import 'server/power_service.dart';
import 'server/server_controller.dart';
import 'server/server_scope.dart';
import 'widgets/error_dialog.dart';
import 'widgets/miuix_dialog.dart';
import 'widgets/miuix_snackbar.dart';
import 'widgets/update_dialog.dart';
import 'widgets/open_source_notice_dialog.dart';
import 'widgets/user_agreement_dialog.dart';

/// 应用主壳：底部导航栏 + 页面切换。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  late final List<Widget> _tabPages;
  Completer<void>? _resumeWaiter;
  bool _checkingStoragePermission = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabPages = [
      const ServerPage(),
      const ConsolePage(),
      const ManagePage(),
      const FilesPage(),
      const SettingsPage(),
    ];
    EcpkgHandler.onOpenEcpkg = _handleOpenEcpkg;
    EcpkgHandler.onError = _handleEcpkgError;
    WidgetsBinding.instance.addPostFrameCallback((_) => _runStartupTasks());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    EcpkgHandler.onOpenEcpkg = null;
    EcpkgHandler.onError = null;
    _resumeWaiter?.complete();
    super.dispose();
  }

  void _handleOpenEcpkg(String path) {
    if (!mounted) return;
    if (!path.toLowerCase().endsWith('.ecpkg')) {
      showErrorDialog(context, context.tr('runtime.notEcpkg'));
      return;
    }
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => RuntimePage(initialEcpkgPath: path),
          ),
        )
        .then((_) {
          if (mounted) {
            EcpkgHandler.onOpenEcpkg = _handleOpenEcpkg;
          }
        });
  }

  void _handleEcpkgError(String error) {
    if (!mounted) return;
    showErrorDialog(
      context,
      context.tr('runtime.openEcpkgFailed', {'error': error}),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final waiter = _resumeWaiter;
      _resumeWaiter = null;
      if (waiter != null && !waiter.isCompleted) waiter.complete();
      if (waiter == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _ensureStoragePermissionGuard();
        });
      }
    }
  }

  Future<void> _runStartupTasks() async {
    // 开源免费声明
    final noticed = await _ensureOpenSourceNoticeAcknowledged();
    if (!noticed || !mounted) return;
    // 用户协议
    final agreed = await _ensureUserAgreementAccepted();
    if (!agreed || !mounted) return;
    // 权限申请
    await _requestStartupPermissions();
    if (!mounted) return;
    final storageReady = await _ensureStoragePermissionGuard();
    if (!storageReady || !mounted) return;
    await _showFirstLaunchDialog();
    if (!mounted) return;
    await _checkUpdatesInBackground();
  }

  /// 调用原生端依次请求通知权限与本地网络权限，等待所有对话框关闭后返回。
  ///
  /// 由 [MainActivity] 的 permission Channel 处理：
  /// - Android 13+：请求 POST_NOTIFICATIONS；
  /// - Android 17+：请求 ACCESS_LOCAL_NETWORK；
  /// 链式请求结束后（无论授权与否）原生端回调，本方法返回。
  ///
  /// 非 Android 平台直接返回；通道异常时静默忽略，不阻塞后续流程。
  Future<void> _requestStartupPermissions() async {
    if (!Platform.isAndroid) return;
    try {
      await const MethodChannel(
        'com.venti1112.edgecube/permission',
      ).invokeMethod<void>('requestStartupPermissions');
    } catch (_) {
      // 通道异常时静默忽略，不阻塞后续流程。
    }
  }

  /// 检查用户是否已确认开源免费声明。
  ///
  /// - 已确认：返回 `true`，继续后续启动流程；
  /// - 未确认：弹出声明对话框，等待 3 秒倒计时后才可点击确认；
  ///   - 选择「我已知悉」：持久化后返回 `true`；
  ///   - 选择「退出应用」：调用 `SystemNavigator.pop()` 退出应用，返回 `false`。
  Future<bool> _ensureOpenSourceNoticeAcknowledged() async {
    const fileName = 'open_source_notice.json';
    final config = await ConfigStore.readConfig(fileName);
    if (config['acknowledged'] == true) return true;
    if (!mounted) return false;
    final result = await showMiuixDialog<bool>(
      context: context,
      barrierDismissible: false,
      title: OpenSourceNoticeDialog.title,
      builder: (_) => const OpenSourceNoticeDialog(),
    );
    if (result == true) {
      await ConfigStore.writeConfig(fileName, {'acknowledged': true});
      return true;
    }
    await SystemNavigator.pop();
    return false;
  }

  /// 检查用户是否已同意当前版本的用户协议。
  ///
  /// - 已同意当前版本：返回 `true`，继续后续启动流程；
  /// - 从未同意或协议版本落后：弹出协议对话框让用户阅读并选择；
  ///   - 选择「同意」：持久化后返回 `true`；
  ///   - 选择「不同意」或按下返回键：调用 `SystemNavigator.pop()` 退出应用，
  ///     返回 `false`。
  Future<bool> _ensureUserAgreementAccepted() async {
    final agreedVersion = await UserAgreementStore.loadAgreedVersion();
    if (agreedVersion != null &&
        agreedVersion >= UserAgreementStore.currentVersion) {
      return true;
    }
    if (!mounted) return false;
    final result = await showMiuixDialog<bool>(
      context: context,
      barrierDismissible: false,
      title: context.tr('userAgreement.title'),
      builder: (_) => const UserAgreementDialog(),
    );
    if (result == true) {
      await UserAgreementStore.saveAgreed();
      return true;
    }
    // 不同意 → 退出应用
    await SystemNavigator.pop();
    return false;
  }

  Future<bool> _ensureStoragePermissionGuard() async {
    if (_checkingStoragePermission) return StoragePermission.isGranted();
    _checkingStoragePermission = true;
    try {
      while (mounted && !await StoragePermission.isGranted()) {
        final go = await _showStartupStoragePermissionDialog();
        if (go != true) return false;
        final result = await StoragePermission.request();
        if (result == null) {
          // API >= 30: intent-based flow, wait for resume from system settings
          final resumeWaiter = Completer<void>();
          _resumeWaiter = resumeWaiter;
          await resumeWaiter.future;
          await _waitForStoragePermissionGranted();
        }
      }
      return mounted;
    } finally {
      _checkingStoragePermission = false;
    }
  }

  Future<void> _waitForStoragePermissionGranted() async {
    for (var i = 0; mounted && i < 25; i++) {
      if (await StoragePermission.isGranted()) return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  Future<bool?> _showStartupStoragePermissionDialog() {
    return showMiuixDialog<bool>(
      context: context,
      barrierDismissible: false,
      title: context.tr('instance.storagePermissionTitle'),
      summary: context.tr('settings.storage.startupPermissionMessage'),
      builder: (ctx) => MiuixDialogActions(
        children: [
          MiuixTextButton(
            ctx.tr('common.close'),
            onPressed: () => SystemNavigator.pop(),
          ),
          MiuixButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            colors: MiuixButtonDefaults.buttonColorsPrimary(ctx),
            child: MiuixText(ctx.tr('instance.goGrant')),
          ),
        ],
      ),
    );
  }

  /// 后台检查更新。失败不提示；有更新则弹出更新对话框。
  Future<void> _checkUpdatesInBackground() async {
    final result = await UpdateService.checkForUpdates();
    if (result == null) return;
    if (!mounted) return;
    final updateInfo = await UpdateService.pickBestUpdate(result);
    if (!mounted || updateInfo == null) return;
    showMiuixDialog<void>(
      context: context,
      barrierDismissible: false,
      title: context.tr('update.newVersionFound'),
      builder: (_) => UpdateDialog(updateInfo: updateInfo),
    );
  }

  /// 首次启动依次询问：镜像源、QQ 群（各自只询问一次）。
  Future<void> _showFirstLaunchDialog() async {
    await _maybeAskMirror();
    await _maybeAskJoinQqGroup();
  }

  /// 询问是否启用镜像源下载服务端（仅首次）。
  Future<void> _maybeAskMirror() async {
    if (await NetworkStore.loadMirrorAsked()) return;
    if (!mounted) return;

    final result = await showMiuixDialog<bool>(
      context: context,
      title: context.tr('firstLaunch.mirror.title'),
      summary: context.tr('firstLaunch.mirror.content'),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 品牌标识改置于文案上方居中，替代原先塞进标题行的做法
          // （Miuix 的标题是居中单行文本，不接受 Widget）。
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/images/msl_logo.png',
                width: 40,
                height: 40,
              ),
            ),
          ),
          const SizedBox(height: 20),
          MiuixDialogActions(
            children: [
              MiuixTextButton(
                ctx.tr('firstLaunch.mirror.decline'),
                onPressed: () => Navigator.of(ctx).pop(false),
              ),
              MiuixButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                colors: MiuixButtonDefaults.buttonColorsPrimary(ctx),
                child: MiuixText(ctx.tr('common.enable')),
              ),
            ],
          ),
        ],
      ),
    );

    await NetworkStore.saveMirrorAsked(true);
    if (result == true) {
      await NetworkStore.saveUseMirror(true);
    }
  }

  /// 询问是否加入官方 QQ 群（仅首次）。
  Future<void> _maybeAskJoinQqGroup() async {
    if (await NetworkStore.loadQqGroupAsked()) return;
    if (!mounted) return;

    await showMiuixDialog<void>(
      context: context,
      title: context.tr('firstLaunch.qqGroup.title'),
      summary: '${context.tr('firstLaunch.qqGroup.content')}1028916207',
      builder: (ctx) => MiuixDialogActions(
        children: [
          MiuixTextButton(
            ctx.tr('common.close'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          MiuixButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              launchUrl(
                Uri.parse('https://qm.qq.com/q/pnCZcmnKIS'),
                mode: LaunchMode.externalApplication,
              );
            },
            colors: MiuixButtonDefaults.buttonColorsPrimary(ctx),
            child: MiuixText(ctx.tr('firstLaunch.qqGroup.join')),
          ),
        ],
      ),
    );

    await NetworkStore.saveQqGroupAsked(true);
  }

  void _onDestinationSelected(int index) {
    // 切换页面前先收起软键盘，避免键盘收起动画期间的布局抖动导致视觉残留。
    FocusManager.instance.primaryFocus?.unfocus();
    if (index == 3) {
      FileBrowser.checkAndRefresh();
    }
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // 在服务器页面按返回键：双击退出应用
        if (_selectedIndex == 0) {
          _handleExit();
          return;
        }
        // 在文件页面：先退出多选，其次返回上级目录
        if (_selectedIndex == 3) {
          if (FileBrowser.isSearching) {
            FileBrowser.exitSearch();
            return;
          }
          if (FileBrowser.isSelecting) {
            FileBrowser.exitSelection();
            return;
          }
          if (FileBrowser.canNavigateUp) {
            FileBrowser.navigateUp();
            return;
          }
        }
        // 其它情况：返回服务器页面
        setState(() => _selectedIndex = 0);
      },
      child: MiuixScaffold(
        bottomBar: MiuixNavigationBar(
          children: [
            _navItem(0, Icons.dns_outlined, Icons.dns, 'nav.server'),
            _navItem(1, Icons.terminal_outlined, Icons.terminal, 'nav.console'),
            _navItem(2, Icons.tune_outlined, Icons.tune, 'nav.manage'),
            _navItem(3, Icons.folder_outlined, Icons.folder, 'nav.files'),
            _navItem(
              4,
              Icons.settings_outlined,
              Icons.settings,
              'nav.settings',
            ),
          ],
        ),
        // 只取底部内边距：各标签页目前仍是 Material Scaffold + AppBar，
        // 顶部安全区由它们各自处理，此处再套一遍会双重留白。
        content: (padding) => Padding(
          padding: EdgeInsets.only(bottom: padding.bottom),
          child: IndexedStack(index: _selectedIndex, children: _tabPages),
        ),
      ),
    );
  }

  MiuixNavigationBarItem _navItem(
    int index,
    IconData icon,
    IconData selectedIcon,
    String labelKey,
  ) {
    final selected = _selectedIndex == index;
    return MiuixNavigationBarItem(
      selected: selected,
      onPressed: () => _onDestinationSelected(index),
      icon: MiuixIcon(icon: selected ? selectedIcon : icon),
      label: context.tr(labelKey),
    );
  }

  /// 双击返回退出应用。
  DateTime? _lastBackPress;

  Future<void> _handleExit() async {
    final now = DateTime.now();
    if (_lastBackPress != null &&
        now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
      final server = ServerScope.of(context);
      if (server.status != ServerStatus.stopped) {
        // 服务端运行中：仅把任务移到后台（等效 Home 键）。Activity 与
        // Flutter 引擎保持存活，回前台后 UPnP/DDNS 映射信息等页面状态不丢失。
        await PowerService.moveTaskToBack();
      } else {
        // 服务端未运行：彻底退出并杀死进程，不留后台残留。
        await PowerService.exitApp();
        // 非 Android 平台的兜底退出路径。
        if (!Platform.isAndroid) await SystemNavigator.pop();
      }
    } else {
      _lastBackPress = now;
      if (!mounted) return;
      final server = ServerScope.of(context);
      final toastKey = server.status != ServerStatus.stopped
          ? 'home.backgroundToast'
          : 'home.exitToast';
      showMiuixSnackbar(context.tr(toastKey));
    }
  }
}
