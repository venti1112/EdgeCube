import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_storage/just_storage.dart';

import '../settings/appearance.dart';
import 'local_key.dart';
import 'server_entry.dart';

/// 从存储加载服务器列表,损坏或缺失时返回空列表
Future<List<ServerEntry>> loadServers(JustStandardStorage storage) async {
  final raw = await storage.read(ServerListNotifier.storageKey);
  if (raw == null || raw.isEmpty) return [];
  try {
    final list = jsonDecode(raw) as List<dynamic>;
    return [
      for (final item in list)
        ServerEntry.fromJson(item as Map<String, dynamic>),
    ];
  } catch (_) {
    return [];
  }
}

/// 从存储加载上次连接的服务器 id
Future<String?> loadLastServerId(JustStandardStorage storage) async {
  final raw = await storage.read(CurrentServerIdNotifier.storageKey);
  return (raw == null || raw.isEmpty) ? null : raw;
}

/// 连接会话:登录成功后持有长期 token(仅内存,不落盘)
class ServerSession {
  const ServerSession({
    required this.serverId,
    required this.token,
    required this.deviceId,
  });

  final String serverId;
  final String token;
  final String deviceId;
}

/// 登录/连接失败时抛出的用户可读异常
class ServerException implements Exception {
  const ServerException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// main() 启动时 override 的初始服务器列表
final initialServersProvider = Provider<List<ServerEntry>>(
  (ref) => throw UnimplementedError('须在 main() 中 override'),
);

/// main() 启动时 override 的当前服务器 id
final initialCurrentServerIdProvider = Provider<String?>(
  (ref) => throw UnimplementedError('须在 main() 中 override'),
);

/// 本机是否存在 daemon 的 local.key(启动时检测,main() override)
final hasLocalKeyProvider = Provider<bool>((ref) => false);

/// 服务器列表状态,变更即持久化
final serverListProvider =
    NotifierProvider<ServerListNotifier, List<ServerEntry>>(
  ServerListNotifier.new,
);

class ServerListNotifier extends Notifier<List<ServerEntry>> {
  static const storageKey = 'servers';

  @override
  List<ServerEntry> build() => ref.watch(initialServersProvider);

  Future<void> add(ServerEntry entry) async {
    state = [...state, entry];
    await _persist();
  }

  Future<void> remove(String id) async {
    state = state.where((e) => e.id != id).toList();
    await _persist();
  }

  Future<void> _persist() => ref.read(storageProvider).write(
        storageKey,
        jsonEncode(state.map((e) => e.toJson()).toList()),
      );
}

/// 当前服务器 id,变更即持久化
final currentServerIdProvider =
    NotifierProvider<CurrentServerIdNotifier, String?>(
  CurrentServerIdNotifier.new,
);

class CurrentServerIdNotifier extends Notifier<String?> {
  static const storageKey = 'lastServer';

  @override
  String? build() => ref.watch(initialCurrentServerIdProvider);

  Future<void> set(String? id) async {
    state = id;
    await ref.read(storageProvider).write(storageKey, id ?? '');
  }
}

/// 连接会话(内存态),登录成功后被写入
final sessionProvider = NotifierProvider<SessionNotifier, ServerSession?>(
  SessionNotifier.new,
);

class SessionNotifier extends Notifier<ServerSession?> {
  @override
  ServerSession? build() => null;

  void set(ServerSession? session) {
    state = session;
  }
}

/// 启动连接阶段:应用启动时进入 [connecting],连接结束后由 redirect 跳转。
enum StartupStage { connecting, finished }

/// 启动连接阶段状态
final startupStageProvider =
    NotifierProvider<StartupStageNotifier, StartupStage>(
  StartupStageNotifier.new,
);

class StartupStageNotifier extends Notifier<StartupStage> {
  @override
  StartupStage build() => StartupStage.connecting;

  /// 连接流程结束(无论成败),redirect 据此从连接页跳转。
  void finish() => state = StartupStage.finished;
}

/// 当前连接服务器的 API 客户端(登录成功后才可获取,已注入 Bearer token)
final edgecubeClientProvider = Provider<EdgecubeApiClient?>((ref) {
  final service = ref.watch(serverServiceProvider);
  final id = ref.watch(currentServerIdProvider);
  final session = ref.watch(sessionProvider);
  if (id == null || session == null || session.serverId != id) return null;
  return service._clients[id];
});

final serverServiceProvider = Provider<ServerService>(
  (ref) => ServerService(ref),
);

/// 服务器连接服务:管理各服务器的 API 客户端实例与登录。
class ServerService {
  ServerService(this._ref);

  final Ref _ref;

  static const _deviceName = 'EdgeCube App';

  /// 各服务器 id -> 已实例化客户端(连接成功后注入 Bearer token)
  final Map<String, EdgecubeApiClient> _clients = {};

  /// 连接并登录指定服务器:
  /// - 本地:读 local.key 走 /auth/local-login 免密;
  /// - 远程:用户名/密码走 /auth/login。
  /// 成功后写入 [sessionProvider] 并返回登录响应。
  Future<LoginResponse> connectTo(ServerEntry entry,
      {String? username, String? password}) async {
    final client = _clients.putIfAbsent(
      entry.id,
      () => EdgecubeApiClient(
        basePathOverride: 'http://${entry.host}:${entry.port}/api/v1',
      ),
    );
    final auth = client.getAuthApi();
    try {
      final LoginResponse resp;
      if (entry.type == ServerType.local) {
        final key = await loadLocalKey();
        if (key == null) {
          throw const ServerException('未找到本机 daemon 的 local.key');
        }
        final challenge = (await auth.issueLocalLoginChallenge()).data!;
        final signature = signLocalChallenge(key, challenge.challenge);
        resp = (await auth.localLogin(
          localLoginRequest: LocalLoginRequest((b) => b
            ..challenge = challenge.challenge
            ..signature = signature
            ..deviceName = _deviceName),
        ))
            .data!;
      } else {
        final user = username ?? entry.username;
        final pass = password;
        if (user == null || user.isEmpty || pass == null || pass.isEmpty) {
          throw const ServerException('请输入用户名和密码');
        }
        resp = (await auth.login(
          loginRequest: LoginRequest((b) => b
            ..username = user
            ..password = pass
            ..deviceName = _deviceName),
        ))
            .data!;
      }
      client.setBearerAuth('BearerAuth', resp.token);
      _ref
          .read(sessionProvider.notifier)
          .set(ServerSession(serverId: entry.id, token: resp.token, deviceId: resp.deviceId));
      // 同时更新“当前服务器”:单选列表选中、lastServer 持久化、
      // edgecubeClientProvider 依据 id 与 session 匹配后对外暴露。
      await _ref.read(currentServerIdProvider.notifier).set(entry.id);
      debugPrint('[EdgeCube] connected to ${entry.type} server ${entry.id}, '
          'device=${resp.deviceId}');
      return resp;
    } on ServerException {
      rethrow;
    } on DioException catch (e) {
      throw ServerException(_dioMessage(e, entry.type));
    } catch (e) {
      throw ServerException('连接失败:$e');
    }
  }

  /// 断开当前连接(不删除服务器条目)
  void disconnect() {
    final session = _ref.read(sessionProvider);
    if (session == null) return;
    _clients[session.serverId]?.removeBearerAuth('BearerAuth');
    _ref.read(sessionProvider.notifier).set(null);
  }

  static String _dioMessage(DioException e, ServerType type) {
    final status = e.response?.statusCode;
    if (status == 401) {
      return type == ServerType.local
          ? '免密登录失败(local.key 与 daemon 不匹配)'
          : '用户名或密码错误';
    }
    if (status == 403) return '当前来源被服务器拒绝(仅允许本机免密登录)';
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return '无法连接服务器';
      default:
        return '请求失败:${status ?? e.type.name}';
    }
  }
}