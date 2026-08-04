import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:path/path.dart' as p;

import '../i18n/i18n_service.dart';
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
    description: tr('mcp.tool.getServerStatus'),
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
    description: tr('mcp.tool.getSystemInfo'),
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
    description: tr('mcp.tool.getDeviceInfo'),
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
    description: tr('mcp.tool.listInstances'),
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
    description: tr('mcp.tool.getSelectedInstance'),
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
        'runtimeEnvId': sel.runtimeEnvId,
        'serverFile': sel.serverFile,
        'customJvmArgs': sel.customJvmArgs,
        'compatMode': sel.compatMode,
      });
    },
  );

  mcp.registerTool(
    'get_console_log',
    description: tr('mcp.tool.getConsoleLog'),
    inputSchema: JsonSchema.object(
      properties: {
        'lines': JsonSchema.integer(
          description: tr('mcp.tool.getConsoleLog.lines'),
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
    description: tr('mcp.tool.listOnlinePlayers'),
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
    description: tr('mcp.tool.startServer'),
    annotations: const ToolAnnotations(destructiveHint: false),
    callback: (args, extra) async {
      if (server.status != ServerStatus.stopped) {
        return _err(tr('mcp.err.serverBusy', {'status': server.status.name}));
      }
      final instance = instances.selected;
      if (instance == null) return _err(tr('mcp.err.noSelectedInstance'));
      return _startInstance(server, instances, instance);
    },
  );

  mcp.registerTool(
    'stop_server',
    description: tr('mcp.tool.stopServer'),
    annotations: const ToolAnnotations(idempotentHint: true),
    callback: (args, extra) async {
      if (!server.isRunning) {
        return _err(
          tr('mcp.err.serverNotRunning', {'status': server.status.name}),
        );
      }
      await server.stop();
      return _ok({'stopping': true, 'status': server.status.name});
    },
  );

  mcp.registerTool(
    'force_stop_server',
    description: tr('mcp.tool.forceStopServer'),
    annotations: const ToolAnnotations(idempotentHint: true),
    callback: (args, extra) async {
      if (server.status == ServerStatus.stopped) {
        return _err(tr('mcp.err.serverNotRunningShort'));
      }
      await server.forceStop();
      return _ok({'forceStopping': true});
    },
  );

  mcp.registerTool(
    'send_command',
    description: tr('mcp.tool.sendCommand'),
    inputSchema: JsonSchema.object(
      properties: {
        'command': JsonSchema.string(
          description: tr('mcp.tool.sendCommand.command'),
        ),
      },
      required: ['command'],
    ),
    annotations: const ToolAnnotations(
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final command = (args['command'] as String?)?.trim() ?? '';
      if (command.isEmpty) return _err(tr('mcp.err.commandEmpty'));
      if (server.status != ServerStatus.starting &&
          server.status != ServerStatus.running &&
          server.status != ServerStatus.stopping) {
        return _err(
          tr('mcp.err.cannotSendCommand', {'status': server.status.name}),
        );
      }
      await server.sendCommand(command);
      return _ok({'sent': command});
    },
  );

  mcp.registerTool(
    'select_instance',
    description: tr('mcp.tool.selectInstance'),
    inputSchema: JsonSchema.object(
      properties: {
        'instanceId': JsonSchema.string(
          description: tr('mcp.tool.selectInstance.instanceId'),
        ),
      },
      required: ['instanceId'],
    ),
    annotations: const ToolAnnotations(
      destructiveHint: false,
      openWorldHint: false,
    ),
    callback: (args, extra) async {
      final id = (args['instanceId'] as String?)?.trim() ?? '';
      if (id.isEmpty) return _err(tr('mcp.err.instanceIdEmpty'));
      if (!instances.instances.any((s) => s.id == id)) {
        return _err(tr('mcp.err.instanceNotFound', {'id': id}));
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
    description: tr('mcp.tool.runShell'),
    inputSchema: JsonSchema.object(
      properties: {
        'command': JsonSchema.string(
          description: tr('mcp.tool.runShell.command'),
        ),
        'cwd': JsonSchema.string(description: tr('mcp.tool.runShell.cwd')),
      },
      required: ['command'],
    ),
    annotations: const ToolAnnotations(openWorldHint: false),
    callback: (args, extra) async {
      final command = (args['command'] as String?)?.trim() ?? '';
      if (command.isEmpty) return _err(tr('mcp.err.commandEmpty'));
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
    description: tr('mcp.tool.shellCd'),
    inputSchema: JsonSchema.object(
      properties: {
        'path': JsonSchema.string(description: tr('mcp.tool.shellCd.path')),
      },
      required: ['path'],
    ),
    annotations: const ToolAnnotations(openWorldHint: false),
    callback: (args, extra) async {
      final path = (args['path'] as String?)?.trim() ?? '';
      if (path.isEmpty) return _err(tr('mcp.err.pathEmpty'));
      // 用 `cd && pwd` 校验目录可进入并解析为绝对路径。
      final result = await shell.runCommand(
        'cd "$path" && pwd',
        cwd: session.cwd,
      );
      final exitCode = result['exitCode'] as int? ?? -1;
      final output = (result['output'] as String? ?? '').trim();
      if (exitCode != 0 || output.isEmpty) {
        return _err(tr('mcp.err.cannotEnterDirectory', {'path': path}));
      }
      session.cwd = output;
      return _ok({'cwd': session.cwd});
    },
  );

  mcp.registerTool(
    'shell_pwd',
    description: tr('mcp.tool.shellPwd'),
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
    description: tr('mcp.tool.whichShell'),
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
    if (phpRuntimes.isEmpty) return _err(tr('mcp.err.phpArchUnsupported'));
    final phar = _pickFile(instance.serverFile, phars);
    if (phar == null) {
      return _err(tr('mcp.err.pharNotFound'));
    }
    await server.start(
      instanceId: instance.id,
      instanceName: instance.name,
      workingDir: dir.path,
      runtimeId: phpRuntimes.first,
      runtime: kRuntimePhp,
      runtimeArgs: const [],
      programArgs: [phar, '--no-wizard'],
      compatMode: instance.compatMode,
      autoRestartOnExit: instance.autoRestartOnExit,
    );
    return _ok({
      'started': true,
      'runtime': 'php',
      'file': phar,
      'status': server.status.name,
    });
  }

  // Java：用 JRE 执行选中的 .jar。
  final jar = _pickFile(instance.serverFile, jars);
  if (jar == null) {
    return _err(tr('mcp.err.jarNotFound'));
  }
  final versions = await server.availableJreIds();
  if (versions.isEmpty) {
    return _err(tr('mcp.err.noJavaRuntime'));
  }
  var runtimeId = instance.runtimeEnvId ?? 'jre21';
  if (!versions.contains(runtimeId)) {
    runtimeId = versions.contains('jre21') ? 'jre21' : versions.first;
  }
  final mem = instance.maxMemory ?? 2048;
  final jvmArgs = <String>[
    if (mem > 0) '-Xmx${mem}M',
    ..._parseCustomJvmArgs(instance.customJvmArgs),
  ];
  if (!await _ensureEula(dir.path)) {
    return _err(tr('mcp.err.eulaNotAgreed'));
  }
  await server.start(
    instanceId: instance.id,
    instanceName: instance.name,
    workingDir: dir.path,
    runtimeId: runtimeId,
    runtime: kRuntimeJava,
    runtimeArgs: jvmArgs,
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

/// 检查 eula.txt 中 eula=true 是否已设置。
///
/// MCP 工具无 BuildContext，无法弹窗；仅在 EULA 尚未同意时返回 `false`，
/// 由调用方提示用户先在应用内手动同意。
Future<bool> _ensureEula(String workingDir) async {
  final eulaFile = File(p.join(workingDir, 'eula.txt'));
  if (await eulaFile.exists()) {
    final content = await eulaFile.readAsString();
    if (RegExp(r'eula\s*=\s*true', caseSensitive: false).hasMatch(content)) {
      return true;
    }
  }
  return false;
}
