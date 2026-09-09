import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Web 平台名:读取浏览器 UA,如 Web-Edge / Web-Chrome / Web-Safari。
String devicePlatformName() {
  final ua = ((globalContext['navigator'] as JSObject?)?
              ['userAgent'] as JSString?)
          ?.toDart ??
      '';
  if (ua.contains('Edg/')) return 'Web-Edge';
  if (ua.contains('Firefox/')) return 'Web-Firefox';
  if (ua.contains('SamsungBrowser')) return 'Web-Samsung';
  if (ua.contains('OPR/') || ua.contains('Opera/')) return 'Web-Opera';
  if (ua.contains('Chrome/') || ua.contains('CriOS/')) return 'Web-Chrome';
  if (ua.contains('Safari/')) return 'Web-Safari';
  return 'Web';
}

/// Web 端设备类别固定为浏览器(openapi DeviceType web)。
String deviceTypeName() => 'web';