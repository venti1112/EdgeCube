import 'dart:io';

/// 本机(os/iot)平台名:取操作系统 + 标识 + 主版本,如 Windows-11、Linux-Debian12、
/// Android-14、macOS-14;识别失败时退化为平台前缀。
String devicePlatformName() {
  switch (Platform.operatingSystem) {
    case 'windows':
      return _windowsName();
    case 'android':
      return _androidName();
    case 'linux':
      return _linuxName();
    case 'macos':
      final m = RegExp(r'(\d+)\.(\d+)')
          .firstMatch(Platform.operatingSystemVersion);
      return m == null ? 'macOS' : 'macOS-${m.group(1)}';
    default:
      return 'Device';
  }
}

/// 本机设备类别(openapi DeviceType):手机 → mobile,其余桌面/其他 → desktop。
String deviceTypeName() {
  switch (Platform.operatingSystem) {
    case 'android':
    case 'ios':
      return 'mobile';
    default:
      return 'desktop';
  }
}

/// "Windows 10.0.26100" → 构建号 26100 ≥ 22000 判为 Windows 11。
String _windowsName() {
  final m = RegExp(r'(\d+)\.(\d+)\.(\d+)')
      .firstMatch(Platform.operatingSystemVersion);
  final build = int.tryParse(m?.group(3) ?? '');
  if (build != null && build >= 22000) return 'Windows-11';
  return 'Windows-10';
}

/// 形如 "Android 14 (VanillaIceCream)..." → Android-14。
String _androidName() {
  final m =
      RegExp(r'Android[^\d]*(\d+)').firstMatch(Platform.operatingSystemVersion);
  return m == null ? 'Android' : 'Android-${m.group(1)}';
}

/// 读 /etc/os-release 的 ID 与 VERSION_ID,如 debian/12 → Linux-Debian12。
/// WSL / 桌面发行版均适用;读取失败退化为 Linux。
String _linuxName() {
  String? id;
  String? versionId;
  try {
    final file = File('/etc/os-release');
    if (!file.existsSync()) return 'Linux';
    for (final line in file.readAsLinesSync()) {
      if (line.startsWith('ID=')) {
        id = line.substring(3).replaceAll('"', '').trim();
      } else if (line.startsWith('VERSION_ID=')) {
        versionId =
            line.substring(11).replaceAll('"', '').trim();
      }
    }
  } catch (_) {
    return 'Linux';
  }
  if (id == null || id.isEmpty) return 'Linux';
  final cap = id[0].toUpperCase() + id.substring(1);
  if (versionId == null || versionId.isEmpty) return 'Linux-$cap';
  return 'Linux-$cap$versionId';
}