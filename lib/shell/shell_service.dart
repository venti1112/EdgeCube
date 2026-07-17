import 'package:flutter/services.dart';

/// UI 可选的 shell 条目。
///
/// - [id] 传给 `start(shellId: ...)` 指定要启动哪个 shell：
///   - "system_sh"：系统自带的 /system/bin/sh
///   - `"proot:<rootfsId>"`：进入指定 rootfs 的 proot 容器交互 shell
/// - [label] 为展示名（如 "system sh"、"proot: debian-12-jdk21"）
/// - [type] 为 "system" 或 "proot"，便于 UI 分组渲染
class ShellOption {
  const ShellOption({required this.id, required this.label, required this.type});

  final String id;
  final String label;
  final String type;

  factory ShellOption.fromMap(Map<String, dynamic> m) {
    return ShellOption(
      id: m['id'] as String? ?? '',
      label: m['label'] as String? ?? '',
      type: m['type'] as String? ?? 'system',
    );
  }
}

/// 与原生 shell 通道对接：交互式 PTY shell 的起停与读写，以及一次性命令执行。
///
/// 对应 [MainActivity] 中注册的：
///  - MethodChannel `com.venti1112.edgecube/shell`
///  - EventChannel  `com.venti1112.edgecube/shell_events`
class ShellService {
  static const MethodChannel _method = MethodChannel(
    'com.venti1112.edgecube/shell',
  );
  static const EventChannel _events = EventChannel(
    'com.venti1112.edgecube/shell_events',
  );

  /// 当前可用的 shell 选项列表（含系统 sh 与已导入的 proot rootfs）。
  Future<List<ShellOption>> availableShells() async {
    final list = await _method.invokeMethod<List<dynamic>>('availableShells');
    return list?.cast<Map<dynamic, dynamic>>().map((m) {
          return ShellOption.fromMap(m.cast<String, dynamic>());
        }).toList() ??
        const [];
  }

  /// 交互 shell 是否在运行。
  Future<bool> isRunning() async {
    final running = await _method.invokeMethod<bool>('isRunning');
    return running ?? false;
  }

  /// 启动交互 shell。
  ///
  /// [cwd] 为初始工作目录：
  ///  - 系统 sh：host 路径（空则用默认目录）
  ///  - proot：容器内绝对路径（空则用 /root）
  ///
  /// [shellId] 决定启动哪种 shell：
  ///  - null/"system_sh"：系统 sh（默认）
  ///  - `"proot:<rootfsId>"`：进入指定 rootfs 的 proot 容器
  Future<void> start({String? cwd, String? shellId}) =>
      _method.invokeMethod('start', {'cwd': cwd, 'shellId': shellId});

  /// 向 shell PTY 写入原始按键字节。
  Future<void> writeInput(Uint8List bytes) =>
      _method.invokeMethod('writeInput', {'bytes': bytes});

  /// 向 shell PTY 写入一行命令（自动补换行）。
  Future<void> sendCommand(String line) =>
      _method.invokeMethod('sendCommand', {'line': line});

  /// 同步终端窗口尺寸到 PTY。
  Future<void> resize({
    required int cols,
    required int rows,
    int cellWidth = 0,
    int cellHeight = 0,
  }) => _method.invokeMethod('resize', {
    'cols': cols,
    'rows': rows,
    'cellWidth': cellWidth,
    'cellHeight': cellHeight,
  });

  /// 开关 PTY 回显。
  Future<void> setEcho(bool echo) =>
      _method.invokeMethod('setEcho', {'echo': echo});

  /// 优雅退出（发送 exit）。
  Future<void> stop() => _method.invokeMethod('stop');

  /// 强制结束 shell 进程。
  Future<void> forceStop() => _method.invokeMethod('forceStop');

  /// 清空原生侧原始字节缓冲（与界面清屏同步）。
  Future<void> clearLog() => _method.invokeMethod('clearLog');

  /// 一次性执行命令（`<shell> -c <command>`），返回 `{exitCode, output, cwd, shell}`。
  /// 与交互 shell 互不影响，供 MCP 等程序化调用。
  Future<Map<String, dynamic>> runCommand(String command, {String? cwd}) async {
    final res = await _method.invokeMethod<Map<dynamic, dynamic>>(
      'runCommand',
      {'command': command, 'cwd': cwd},
    );
    return res?.cast<String, dynamic>() ?? const {};
  }

  /// 原生事件流（原始终端字节 / 状态）。
  Stream<ShellEvent> events() {
    return _events.receiveBroadcastStream().map((dynamic e) {
      final map = (e as Map).cast<String, dynamic>();
      switch (map['type']) {
        case 'term':
          return ShellTermEvent((map['bytes'] as Uint8List?) ?? Uint8List(0));
        case 'state':
          return ShellStateEvent(
            status: map['status'] as String?,
            label: map['label'] as String?,
            exitCode: map['exitCode'] as int?,
          );
        default:
          return ShellTermEvent(Uint8List(0));
      }
    });
  }
}

/// 原生回传的 shell 事件。
sealed class ShellEvent {
  const ShellEvent();
}

/// 一段原始终端字节（含 ANSI/控制序列），交给 xterm 渲染。
class ShellTermEvent extends ShellEvent {
  const ShellTermEvent(this.bytes);

  final Uint8List bytes;
}

/// shell 进程状态变化。[status] 为 `null` 表示已退出；非空为 `running`。
class ShellStateEvent extends ShellEvent {
  const ShellStateEvent({required this.status, this.label, this.exitCode});

  /// 进程状态；null 表示已退出。
  final String? status;

  /// 当前生效的 shell 名称（如 "system sh"）。
  final String? label;

  /// 退出码（仅在退出事件携带）。
  final int? exitCode;
}
