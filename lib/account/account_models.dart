/// 账号系统的数据模型。
///
/// 对接后端 EdgeCube-CloudServices 的 `/api/auth/*` 接口，字段命名与后端
/// `AuthResponse`（snake_case JSON）保持一致，本地持久化时同样沿用该 JSON 结构，
/// 便于 [AccountStore] 直接读写。
library;

/// 已登录用户的基本资料（不含任何令牌）。
class AccountUser {
  const AccountUser({
    required this.userId,
    required this.username,
    required this.nickname,
    required this.email,
  });

  final int userId;
  final String username;
  final String nickname;
  final String email;

  factory AccountUser.fromJson(Map<String, dynamic> json) => AccountUser(
    userId: (json['user_id'] as num?)?.toInt() ?? 0,
    username: json['username'] as String? ?? '',
    nickname: json['nickname'] as String? ?? '',
    email: json['email'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'username': username,
    'nickname': nickname,
    'email': email,
  };

  /// 展示名：优先昵称，昵称为空时回退用户名。
  String get displayName => nickname.isNotEmpty ? nickname : username;
}

/// 一次成功登录 / 刷新后得到的完整会话，包含用户资料与两个令牌。
///
/// - [sessionToken]：会话令牌，存于后端 Redis，用于调用需认证接口
///   （`Authorization: Bearer <sessionToken>`）。
/// - [refreshToken]：刷新令牌，存于后端数据库，用于续期会话。
/// - [device] / [deviceId]：登录设备信息，便于多设备会话管理与展示。
class AuthSession {
  const AuthSession({
    required this.user,
    required this.sessionToken,
    required this.refreshToken,
    this.device = '',
    this.deviceId = '',
  });

  final AccountUser user;
  final String sessionToken;
  final String refreshToken;
  final String device;
  final String deviceId;

  /// 从后端 `AuthResponse`（登录 / 刷新接口的 `data` 字段）解析。
  factory AuthSession.fromAuthData(Map<String, dynamic> data) => AuthSession(
    user: AccountUser.fromJson(data),
    sessionToken: data['session_token'] as String? ?? '',
    refreshToken: data['refresh_token'] as String? ?? '',
    device: data['device'] as String? ?? '',
    deviceId: data['device_id'] as String? ?? '',
  );

  /// 从本地持久化的 JSON 还原。
  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
    user: AccountUser.fromJson(json),
    sessionToken: json['session_token'] as String? ?? '',
    refreshToken: json['refresh_token'] as String? ?? '',
    device: json['device'] as String? ?? '',
    deviceId: json['device_id'] as String? ?? '',
  );

  /// 持久化为 JSON（与 [fromJson] 对称）。
  Map<String, dynamic> toJson() => {
    ...user.toJson(),
    'session_token': sessionToken,
    'refresh_token': refreshToken,
    'device': device,
    'device_id': deviceId,
  };

  /// 复制并替换部分字段（刷新会话时仅 [sessionToken] 变化）。
  AuthSession copyWith({
    AccountUser? user,
    String? sessionToken,
    String? refreshToken,
    String? device,
    String? deviceId,
  }) => AuthSession(
    user: user ?? this.user,
    sessionToken: sessionToken ?? this.sessionToken,
    refreshToken: refreshToken ?? this.refreshToken,
    device: device ?? this.device,
    deviceId: deviceId ?? this.deviceId,
  );

  bool get hasRefreshToken => refreshToken.isNotEmpty;
}

/// 统一的认证操作结果。
///
/// 所有 [AccountService] 方法都返回该类型：网络异常、超时、后端返回的非成功
/// `code` 均归一为 `success == false` 并携带可直接展示的 [message]；成功时
/// 可选携带解析后的数据 [data]。
class AuthResult<T> {
  const AuthResult({
    required this.success,
    required this.message,
    this.code,
    this.data,
  });

  /// 是否成功（HTTP 2xx 且后端 `code` 表示成功）。
  final bool success;

  /// 可直接展示给用户的信息（成功提示或失败原因）。
  final String message;

  /// 后端返回的业务 / HTTP 状态码；网络层异常时为 null。
  ///
  /// 调用方可据此区分特定场景，例如登录时 `code == 403` 表示邮箱未验证。
  final int? code;

  /// 成功时的数据负载（如登录返回的 [AuthSession]）。
  final T? data;

  AuthResult<R> withData<R>(R? value) => AuthResult<R>(
    success: success,
    message: message,
    code: code,
    data: value,
  );
}
