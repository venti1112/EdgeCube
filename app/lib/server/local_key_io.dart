import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// daemon 数据目录规则与 daemon(config.rs)一致:
/// 优先 `EDGECUBE_HOME`,否则 Windows 取 `%APPDATA%\edgecube`,
/// 其他平台取 `$XDG_DATA_HOME|~/.local/share/edgecube`。
String? _daemonDataDir() {
  final env = Platform.environment;
  final home = env['EDGECUBE_HOME'];
  if (home != null && home.isNotEmpty) return home;
  if (Platform.isWindows) {
    final appData = env['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      return '$appData\\edgecube';
    }
    final profile = env['USERPROFILE'];
    if (profile != null) return '$profile\\AppData\\Roaming\\edgecube';
    return null;
  }
  final xdg = env['XDG_DATA_HOME'];
  if (xdg != null && xdg.isNotEmpty) return '$xdg/edgecube';
  final userHome = env['HOME'];
  if (userHome != null && userHome.isNotEmpty) {
    return '$userHome/.local/share/edgecube';
  }
  return null;
}

/// 读取 daemon 数据目录下的 `local.key`;文件不存在或不可读时返回 null。
Future<String?> loadLocalKey() async {
  final dir = _daemonDataDir();
  if (dir == null) return null;
  final file = File('$dir${Platform.pathSeparator}local.key');
  try {
    return await file.readAsString();
  } on FileSystemException {
    return null;
  }
}

/// local.key 是否存在(启动时用于判断是否自动发现本地 daemon)。
Future<bool> hasLocalKey() => loadLocalKey().then((v) => v != null);

/// 计算免密登录签名:
/// `signature = lowercase(hex(HMAC-SHA256(localKey, challenge)))`
String signLocalChallenge(String localKey, String challenge) {
  final hmac = Hmac(sha256, utf8.encode(localKey));
  return hmac.convert(utf8.encode(challenge)).toString();
}