/// 设备平台显示名:模块级函数在 io / web 两个平台分别实现(条件导出)。
/// 命名风格对齐用户约定:Web-Edge / Windows-11 / Linux-Debian12 / Android-14。
library;

export 'device_platform_io.dart'
    if (dart.library.js_interop) 'device_platform_web.dart';