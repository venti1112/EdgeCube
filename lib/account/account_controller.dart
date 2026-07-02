import 'package:flutter/foundation.dart';

import '../config/account_store.dart';
import '../i18n/i18n_service.dart';
import '../online/online_service.dart';
import '../server/system_monitor_service.dart';
import 'account_models.dart';
import 'account_service.dart';

/// 账号登录态的全局管理器。
///
/// 职责：
/// - 持有当前 [AuthSession]（登录态的唯一真实来源），变化时 [notifyListeners]；
/// - [init] 从 [AccountStore] 载入上次会话，并尝试用 refresh_token 静默续期；
/// - 封装注册 / 验证 / 重发 / 登录 / 登出，成功登录后持久化会话；
/// - 登录时自动附带设备型号与在线服务设备 ID（若可用）。
///
/// 由 [main] 创建、`init()`，并经 `AccountScope` 注入 widget 树。
/// [onlineService] 用于读取设备 ID（可为 null / 未启用，此时 device_id 留空）。
class AccountController extends ChangeNotifier {
  AccountController({this.onlineService}) {
    // 在线服务开关变化时一并通知本控制器的监听者，
    // 使设置入口与账号页能实时响应「在线服务」的启用 / 关闭。
    onlineService?.addListener(_onOnlineChanged);
  }

  /// 在线服务管理器：既用于获取设备 ID，也决定账号功能是否可用（可选）。
  final OnlineService? onlineService;

  AuthSession? _session;
  bool _initialized = false;

  /// 当前会话；未登录时为 null。
  AuthSession? get session => _session;

  /// 当前登录用户资料；未登录时为 null。
  AccountUser? get user => _session?.user;

  /// 是否已登录（存在有效会话）。
  bool get isLoggedIn => _session != null;

  /// 账号功能是否可用：仅当「在线服务」总开关启用时才可用。
  /// 关闭在线服务时账号页只展示引导，且不发起任何账号相关的网络请求。
  bool get available => onlineService?.enabled ?? false;

  /// 是否已完成初始化（载入 + 续期尝试）。
  bool get initialized => _initialized;

  /// 载入持久化会话并尝试续期。应在应用启动时调用一次。
  ///
  /// 续期失败不一定代表登出：网络错误时保留本地会话（用户仍视为已登录，
  /// 后续调用认证接口时再由 401 触发清理）；仅当后端明确判定 refresh_token
  /// 失效（401）时才清空本地会话。
  Future<void> init() async {
    final saved = await AccountStore.load();
    if (saved != null) {
      _session = saved;
      // 未启用在线服务时不发起续期请求（账号功能整体不可用）。
      if (available) await _tryRefresh(saved);
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> _tryRefresh(AuthSession saved) async {
    if (!saved.hasRefreshToken) return;
    final result = await AccountService.refresh(saved.refreshToken);
    if (result.success && result.data != null) {
      // 刷新成功：更新 session_token（refresh_token 不变），保留原设备信息。
      final refreshed = result.data!;
      _session = refreshed.copyWith(
        device: refreshed.device.isNotEmpty ? refreshed.device : saved.device,
        deviceId: refreshed.deviceId.isNotEmpty
            ? refreshed.deviceId
            : saved.deviceId,
      );
      await AccountStore.save(_session!);
    } else if (result.code == 401) {
      // refresh_token 明确失效：清除本地会话，转为未登录。
      await _clearSession();
    }
    // 其它情况（网络异常等）：保留既有会话，不改动。
  }

  /// 注册新账号。成功后需调用 [verify] 完成邮箱验证。
  Future<AuthResult<AccountUser>> register({
    required String username,
    required String email,
    required String password,
    String? nickname,
  }) {
    if (!available) return Future.value(_unavailable<AccountUser>());
    return AccountService.register(
      username: username,
      email: email,
      password: password,
      nickname: nickname,
    );
  }

  /// 使用邮箱验证码完成验证。
  Future<AuthResult<void>> verify({
    required String account,
    required String password,
    required String code,
  }) {
    if (!available) return Future.value(_unavailable<void>());
    return AccountService.verify(
      account: account,
      password: password,
      code: code,
    );
  }

  /// 重新发送邮箱验证码。
  Future<AuthResult<void>> resendVerification({
    required String account,
    required String password,
  }) {
    if (!available) return Future.value(_unavailable<void>());
    return AccountService.resendVerification(
      account: account,
      password: password,
    );
  }

  /// 登录。成功后持久化会话并通知监听者。
  Future<AuthResult<AuthSession>> login({
    required String account,
    required String password,
  }) async {
    if (!available) return _unavailable<AuthSession>();
    final device = await _deviceModel();
    final deviceId = onlineService?.deviceId;
    final result = await AccountService.login(
      account: account,
      password: password,
      device: device,
      deviceId: deviceId,
    );
    if (result.success && result.data != null) {
      _session = result.data;
      await AccountStore.save(_session!);
      notifyListeners();
    }
    return result;
  }

  /// 登出。无论后端是否成功，都清除本地会话。
  Future<AuthResult<void>> logout() async {
    final token = _session?.sessionToken;
    AuthResult<void> result = const AuthResult<void>(
      success: true,
      message: '',
    );
    if (available && token != null && token.isNotEmpty) {
      result = await AccountService.logout(token);
    }
    await _clearSession();
    return result;
  }

  Future<void> _clearSession() async {
    _session = null;
    await AccountStore.clear();
    notifyListeners();
  }

  /// 组合「制造商 型号」作为登录设备名；获取失败时返回 null（字段留空）。
  Future<String?> _deviceModel() async {
    try {
      final info = await SystemMonitorService().getDeviceInfo();
      final manufacturer = info.manufacturer.trim();
      final model = info.model.trim();
      final parts = [
        if (manufacturer.isNotEmpty && manufacturer != 'unknown') manufacturer,
        if (model.isNotEmpty && model != 'unknown') model,
      ];
      if (parts.isEmpty) return null;
      return parts.join(' ');
    } catch (_) {
      return null;
    }
  }

  /// 在线服务开关变化时转发通知，驱动账号入口 / 账号页重建。
  void _onOnlineChanged() => notifyListeners();

  /// 账号功能不可用（未启用在线服务）时的统一失败结果。
  AuthResult<T> _unavailable<T>() => AuthResult<T>(
    success: false,
    message: tr('account.error.onlineDisabled'),
  );

  @override
  void dispose() {
    onlineService?.removeListener(_onOnlineChanged);
    super.dispose();
  }
}
