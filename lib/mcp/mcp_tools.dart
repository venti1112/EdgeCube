import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:path/path.dart' as p;

import '../instance/instance.dart';
import '../instance/instance_controller.dart';
import '../server/server_controller.dart';
import '../server/system_monitor_controller.dart';
import '../server/system_monitor_service.dart';
import '../shell/shell_service.dart';

/// MCP 服务器版本（仅作为协议元数据展示）。
const String _kMcpServerVersion = '1.0.0';

/// MCP shell 工具的会话状态：持久的当前工作目录，供 shell_cd / run_shell 跨调用共享。
class McpShellSession {
  String? cwd;
}

/// 构造一个注册好全部工具的 [McpServer]，供 [StreamableMcpServer] 按会话创建。
///
/// 读取类工具始终注册；控制类工具（启动/停止服务端、发送命令、切换实例）仅在
/// [allowControl] 为 true 时注册；Shell 命令执行工具仅在 [allowShell] 为 true 时注册
/// （高风险，独立开关）——开关关闭时 AI 端 `tools/list` 直接看不到这些工具，最直观安全。
///
/// 所有工具回调运行在主 isolate，调用控制器（其内部经 MethodChannel 与原生通信）
/// 是安全的。
McpServer buildMcpServer({
  required ServerController server,
  required InstanceController instances,
  required SystemMonitorController monitor,
  required ShellService shell,
  required McpShellSession shellSession,
  required bool allowControl,
  required bool allowShell,
}) {
  final mcp = McpServer(
    const Implementation(name: 'edgecube', version: _kMcpServerVersion),
  );

  _registerReadTools(
    mcp,
    server: server,
    instances: instances,
    monitor: monitor,
  );
  if (allowControl) {
    _registerControlTools(mcp, server: server, instances: instances);
  }
  if (allowShell) {
    _registerShellTools(mcp, shell: shell, session: shellSession);
  }

  return mcp;
}

// ——————————————————————————————————————————————————————————
// 工具结果辅助
// ——————————————————————————————————————————————————————————

/// 把任意可 JSON 序列化的数据包装为成功结果。
CallToolResult _ok(Object data) =>
    CallToolResult.fromContent([TextContent(text: jsonEncode(data))]);

/// 返回错误结果（isError=true）。
CallToolResult _err(String message) =>
    CallToolResult(content: [TextContent(text: message)], isError: true);

// ——————————————————————————————————————————————————————————
// 读取类工具（始终可用）
// ——————————————————————————————————————————————————————————

void _registerReadTools(
  McpServer mcp, {
  required ServerController server,
  required InstanceController instances,
  required SystemMonitorController monitor,
}) {
  const readOnly = ToolAnnotations(readOnlyHint: true, openWorldHint: false);

  mcp.registerTool(
    'get_server_status',
    description: '获取服务端进程的运行状态、运行中的实例与在线玩家概况。',
    annotations: readOnly,
    callback: (args, extra) async => _ok({
      'status': server.status.name,
      'isRunning': server.isRunning,
      'isBusy': server.isBusy,
      'runningInstanceId': server.runningInstanceId,
      'runningInstanceName': server.runningInstanceName,
      'lastExitCode': server.lastExitCode,
      'onlinePlayerCount': server.onlinePlayers.length,
      'onlinePlayers': server.onlinePlayers.toList(),
    }),
  );

  mcp.registerTool(
    'get_system_info',
    description:
        '获取设备的内存（MB）与 CPU 使用率，以及服务端子进程内存。'
        'cpuUsage 为 -1 表示尚未采样到。',
    annotations: readOnly,
    callback: (args, extra) async {
      final info = monitor.info;
      return _ok({
        'totalMemMb': info.totalMemMb,
        'usedMemMb': info.usedMemMb,
        'availMemMb': info.availMemMb,
        'usedMemPercent': double.parse(info.usedMemPercent.toStringAsFixed(1)),
        'cpuUsage': info.cpuUsage,
        'serverMemMb': info.serverMemMb,
      });
    },
  );

  mcp.registerTool(
    'get_device_info',
    description: '获取设备硬件信息：SoC、CPU 架构、制造商、型号、安卓版本与安全补丁。',
    annotations: readOnly,
    callback: (args, extra) async {
      final deviceInfo = await SystemMonitorService().getDeviceInfo();
      return _ok({
        'socModel': deviceInfo.socModel,
        'architecture': deviceInfo.architecture,
        'manufacturer': deviceInfo.manufacturer,
        'model': deviceInfo.model,
        'androidVersion': deviceInfo.androidVersion,
        'securityPatch': deviceInfo.securityPatch,
      });
    },
  );

  mcp.registerTool(
    'list_instances',
    description: '列出全部服务器实例，并标注哪个被选中、哪个正在运行。',
    annotations: readOnly,
    callback: (args, extra) async {
      final selectedId = instances.selected?.id;
      return _ok({
        'instances': [
          for (final inst in instances.instances)
            {
              'id': inst.id,
              'name': inst.name,
              'selected': inst.id == selectedId,
              'running': server.runningInstanceId == inst.id,
            },
        ],
      });
    },
  );

  mcp.registerTool(
    'get_selected_instance',
    description: '获取当前选中实例的详细配置（运行环境、内存、Java 版本、服务端文件、兼容模式）。',
    annotations: readOnly,
    callback: (args, extra) async {
      final sel = instances.selected;
      if (sel == null) return _ok({'selected': null});
      return _ok({
        'id': sel.id,
        'name': sel.name,
        'runtime': sel.runtime,
        'isPhp': sel.isPhp,
        'maxMemory': sel.maxMemory,
        'javaVersion': sel.javaVersion,
        'selectedJar': sel.selectedJar,
        'customJvmArgs': sel.customJvmArgs,
        'compatMode': sel.compatMode,
      });
    },
  );

  mcp.registerTool(
    'get_console_log',
    description: '获取服务端控制台日志的末尾若干行（已去除 ANSI 转义）。',
    inputSchema: JsonSchema.object(
      properties: {
        'lines': JsonSchema.integer(
          description: '返回末尾多少行，默认 100，范围 1–1000。',
          defaultValue: 100,
        ),
      },
    ),
    annotations: readOnly,
    callback: (args, extra) async {
      final requested = (args['lines'] as num?)?.toInt() ?? 100;
      final n = requested.clamp(1, 1000).toInt();
      final log = server.log;
      final start = log.length > n ? log.length - n : 0;
      return _ok({
        'totalLines': log.length,
        'returnedLines': log.length - start,
        'lines': log.sublist(start),
      });
    },
  );

  mcp.registerTool(
    'list_online_players',
    description: '列出当前在线玩家（从服务端日志解析）。',
    annotations: readOnly,
    callback: (args, extra) async => _ok({
      'count': server.onlinePlayers.length,
      'players': server.onlinePlayers.toList(),
    }),
  );
}

// ——————————————————————————————————————————————————————————
// 控制类工具（仅当 allowControl 时注册）
// ——————————————————————————————————————————————————————————

void _registerControlTools(
  McpServer mcp, {
  required ServerController server,
  required InstanceController instances,
}) {
  mcp.registerTool(
    'start_server',
    description:
        '启动当前选中实例的服务端。自动扫描实例目录下的 .jar/.phar、'
        '按实例配置组装启动参数，Java 版会自动写入 eula=true。',
    annotations: const ToolAnnotations(destructiveHint: false),
    callback: (args, extra) async {
      if (server.status != ServerStatus.stopped) {
        return _err('服务端已在运行或忙碌中（当前状态：${server.status.name}）');
      }
      final instance = instances.selected;
      if (instance == null) return _err('没有选中的实例，无法启动');
      return _startInstance(server, instances, instance);
    },
  );

  mcp.registerTool(
    'stop_server',
    description: '优雅停止服务端（向其发送 stop 命令）。',
    annotations: const ToolAnnotations(idempotentHint: true),
    callback: (args, extra) async {
      if (!server.isRunning) {
        return _err('服务端未在运行（当前状态：${server.status.name}）');
      }
      await server.stop();
      return _ok({'stopping': true, 'status': server.status.name});
    },
  );

  mcp.registerTool(
    'force_stop_server',
    description: '强制结束服务端进程（可能丢失数据，仅在优雅停止无效时使用）。',
    annotations: const ToolAnnotations(idempotentHint: true),
    callback: (args, extra) async {
      if (server.status == ServerStatus.stopped) {
        return _err('服务端未在运行');
      }
      await server.forceStop();
      return _ok({'forceStopping': true});
    },
  );

  mcp.registerTool(
    'send_command',
    description:
        '向正在运行的服务端发送一行控制台命令。'
        '示例：list、say <消息>、op <玩家>、deop <玩家>、'
        'whitelist add <玩家>、ban <玩家>、kick <玩家>、time set day。',
    inputSchema: JsonSchema.object(
      properties: {
        'command': JsonSchema.string(description: '要发送的控制台命令（不含前导斜杠）。'),
      },
      required: ['command'],
    ),
    annotations: const ToolAnnotations(
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final command = (args['command'] as String?)?.trim() ?? '';
      if (command.isEmpty) return _err('command 不能为空');
      if (server.status != ServerStatus.starting &&
          server.status != ServerStatus.running &&
          server.status != ServerStatus.stopping) {
        return _err('服务端未在运行，无法发送命令（当前状态：${server.status.name}）');
      }
      await server.sendCommand(command);
      return _ok({'sent': command});
    },
  );

  mcp.registerTool(
    'select_instance',
    description: '切换当前选中的实例（见 list_instances 的 id）。不影响已在运行的服务端。',
    inputSchema: JsonSchema.object(
      properties: {'instanceId': JsonSchema.string(description: '目标实例的 id。')},
      required: ['instanceId'],
    ),
    annotations: const ToolAnnotations(
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final id = (args['instanceId'] as String?)?.trim() ?? '';
      if (id.isEmpty) return _err('instanceId 不能为空');
      if (!instances.instances.any((s) => s.id == id)) {
        return _err('实例不存在：$id');
      }
      await instances.select(id);
      return _ok({'selected': id, 'name': instances.selected?.name});
    },
  );
}

// ——————————————————————————————————————————————————————————
// Shell 命令执行工具（仅当 allowShell 时注册，高风险：任意命令执行）
// ——————————————————————————————————————————————————————————

void _registerShellTools(
  McpServer mcp, {
  required ShellService shell,
  required McpShellSession session,
}) {
  mcp.registerTool(
    'run_shell',
    description:
        '在设备上执行一条 shell 命令（<shell> -c），返回退出码与合并的 stdout/stderr。'
        '缺省在会话当前目录执行（见 shell_cd/shell_pwd），也可用 cwd 参数覆盖。'
        '注意：单纯的 cd 不跨调用持久，切换目录请用 shell_cd，或在命令内用 "cd x && ..."。',
    inputSchema: JsonSchema.object(
      properties: {
        'command': JsonSchema.string(description: '要执行的 shell 命令。'),
        'cwd': JsonSchema.string(description: '可选：本次执行的工作目录（绝对路径）。'),
      },
      required: ['command'],
    ),
    annotations: const ToolAnnotations(openWorldHint: false),
    callback: (args, extra) async {
      final command = (args['command'] as String?)?.trim() ?? '';
      if (command.isEmpty) return _err('command 不能为空');
      final cwdArg = (args['cwd'] as String?)?.trim();
      final result = await shell.runCommand(
        command,
        cwd: (cwdArg != null && cwdArg.isNotEmpty) ? cwdArg : session.cwd,
      );
      return _ok({
        'exitCode': result['exitCode'],
        'output': result['output'],
        'cwd': result['cwd'],
        'shell': result['shell'],
      });
    },
  );

  mcp.registerTool(
    'shell_cd',
    description: '切换 MCP shell 会话的当前工作目录（持久，影响后续 run_shell）。支持相对路径。',
    inputSchema: JsonSchema.object(
      properties: {'path': JsonSchema.string(description: '目标目录（绝对或相对当前目录）。')},
      required: ['path'],
    ),
    annotations: const ToolAnnotations(openWorldHint: false),
    callback: (args, extra) async {
      final path = (args['path'] as String?)?.trim() ?? '';
      if (path.isEmpty) return _err('path 不能为空');
      // 用 `cd && pwd` 校验目录可进入并解析为绝对路径。
      final result = await shell.runCommand('cd "$path" && pwd', cwd: session.cwd);
      final exitCode = result['exitCode'] as int? ?? -1;
      final output = (result['output'] as String? ?? '').trim();
      if (exitCode != 0 || output.isEmpty) return _err('无法进入目录：$path');
      session.cwd = output;
      return _ok({'cwd': session.cwd});
    },
  );

  mcp.registerTool(
    'shell_pwd',
    description: '返回 MCP shell 会话的当前工作目录。',
    annotations: const ToolAnnotations(
      readOnlyHint: true,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      if (session.cwd != null) return _ok({'cwd': session.cwd});
      final result = await shell.runCommand('pwd', cwd: null);
      final output = (result['output'] as String? ?? '').trim();
      if (output.isNotEmpty) session.cwd = output;
      return _ok({'cwd': session.cwd ?? output});
    },
  );

  mcp.registerTool(
    'which_shell',
    description: '返回当前可用的 shell 列表（按优先级，第一个为生效的）。',
    annotations: const ToolAnnotations(
      readOnlyHint: true,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final shells = await shell.availableShells();
      return _ok({
        'available': shells,
        'active': shells.isNotEmpty ? shells.first : null,
      });
    },
  );
}

// ——————————————————————————————————————————————————————————
// start_server 的内部实现（复刻 server_page.dart 的扫描/启动逻辑）
// ——————————————————————————————————————————————————————————

Future<CallToolResult> _startInstance(
  ServerController server,
  InstanceController instances,
  Instance instance,
) async {
  final dir = await instances.directoryFor(instance);
  final jars = <String>[];
  final phars = <String>[];
  if (await dir.exists()) {
    await for (final entry in dir.list(followLinks: false)) {
      if (entry is! File) continue;
      final lower = entry.path.toLowerCase();
      if (lower.endsWith('.jar')) {
        jars.add(p.basename(entry.path));
      } else if (lower.endsWith('.phar')) {
        phars.add(p.basename(entry.path));
      }
    }
  }

  // PHP（PocketMine）：用 PHP 运行时执行选中的 .phar。
  if (instance.isPhp) {
    final phpRuntimes = await server.availablePhpIds();
    if (phpRuntimes.isEmpty) return _err('当前设备架构不支持 PHP 运行环境');
    final phar = _pickFile(instance.selectedJar, phars);
    if (phar == null) {
      return _err('未在实例目录找到 .phar，请先放入 PocketMine 的 phar 文件');
    }
    await server.start(
      instanceId: instance.id,
      instanceName: instance.name,
      workingDir: dir.path,
      runtimeId: phpRuntimes.first,
      runtime: kRuntimePhp,
      jvmArgs: const [],
      programArgs: [phar],
      compatMode: instance.compatMode,
    );
    return _ok({
      'started': true,
      'runtime': 'php',
      'file': phar,
      'status': server.status.name,
    });
  }

  // Java：用 JRE 执行选中的 .jar。
  final jar = _pickFile(instance.selectedJar, jars);
  if (jar == null) {
    return _err('未在实例目录找到 .jar，请先放入服务端 jar 文件');
  }
  final versions = await server.availableJreIds();
  if (versions.isEmpty) {
    return _err('未安装任何 Java 运行环境，请先在「管理 → 运行环境」导入 JRE');
  }
  var runtimeId = instance.javaVersion ?? 'jre21';
  if (!versions.contains(runtimeId)) {
    runtimeId = versions.contains('jre21') ? 'jre21' : versions.first;
  }
  final mem = instance.maxMemory ?? 2048;
  final jvmArgs = <String>[
    if (mem > 0) '-Xmx${mem}M',
    ..._parseCustomJvmArgs(instance.customJvmArgs),
  ];
  await _ensureEula(dir.path);
  await server.start(
    instanceId: instance.id,
    instanceName: instance.name,
    workingDir: dir.path,
    runtimeId: runtimeId,
    runtime: kRuntimeJava,
    jvmArgs: jvmArgs,
    programArgs: ['-jar', jar, 'nogui'],
    compatMode: instance.compatMode,
  );
  return _ok({
    'started': true,
    'runtime': 'java',
    'file': jar,
    'runtimeId': runtimeId,
    'jvmArgs': jvmArgs,
    'status': server.status.name,
  });
}

/// 优先使用已配置的服务端文件（须存在于目录中），否则回退到首个找到的文件。
String? _pickFile(String? preferred, List<String> files) {
  if (preferred != null && files.contains(preferred)) return preferred;
  return files.isNotEmpty ? files.first : null;
}

/// 解析自定义 JVM 参数文本（每行或空格分隔）为参数列表。
List<String> _parseCustomJvmArgs(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  return raw.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
}

/// 启动前自动检查并写入 eula.txt，确保 eula=true。
Future<void> _ensureEula(String workingDir) async {
  final eulaFile = File(p.join(workingDir, 'eula.txt'));
  var needWrite = false;
  if (await eulaFile.exists()) {
    final content = await eulaFile.readAsString();
    if (!RegExp(r'eula\s*=\s*true', caseSensitive: false).hasMatch(content)) {
      needWrite = true;
    }
  } else {
    needWrite = true;
  }
  if (needWrite) {
    await eulaFile.writeAsString(
      '#By changing the setting below to TRUE you are indicating your agreement to our EULA (https://aka.ms/MinecraftEULA).\n'
      'eula=true\n',
    );
  }
}
