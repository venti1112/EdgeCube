import 'dart:io';

import 'package:flutter/services.dart';

/// 桌面小组件展示选项（与原生 KeepAlivePrefs.WidgetDisplayOptions 对齐）。
class WidgetDisplayOptions {
  const WidgetDisplayOptions({
    this.showInstance = true,
    this.showPlayers = true,
    this.showAddress = true,
    this.showStats = false,
    this.showButtons = true,
  });

  final bool showInstance;
  final bool showPlayers;
  final bool showAddress;
  final bool showStats;
  final bool showButtons;

  WidgetDisplayOptions copyWith({
    bool? showInstance,
    bool? showPlayers,
    bool? showAddress,
    bool? showStats,
    bool? showButtons,
  }) => WidgetDisplayOptions(
    showInstance: showInstance ?? this.showInstance,
    showPlayers: showPlayers ?? this.showPlayers,
    showAddress: showAddress ?? this.showAddress,
    showStats: showStats ?? this.showStats,
    showButtons: showButtons ?? this.showButtons,
  );

  Map<String, bool> toMap() => {
    'showInstance': showInstance,
    'showPlayers': showPlayers,
    'showAddress': showAddress,
    'showStats': showStats,
    'showButtons': showButtons,
  };

  factory WidgetDisplayOptions.fromMap(Map<dynamic, dynamic> map) =>
      WidgetDisplayOptions(
        showInstance: map['showInstance'] as bool? ?? true,
        showPlayers: map['showPlayers'] as bool? ?? true,
        showAddress: map['showAddress'] as bool? ?? true,
        showStats: map['showStats'] as bool? ?? false,
        showButtons: map['showButtons'] as bool? ?? true,
      );
}

/// 桌面小组件外观：背景/文字颜色（ARGB，alpha 忽略）与各自不透明度（0..100）。
/// 与原生 KeepAlivePrefs.WidgetAppearance 对齐。
class WidgetAppearance {
  const WidgetAppearance({
    this.bgColor = 0xFF303030,
    this.bgOpacity = 100,
    this.textColor = 0xFFFFFFFF,
    this.textOpacity = 100,
  });

  final int bgColor;
  final int bgOpacity;
  final int textColor;
  final int textOpacity;

  WidgetAppearance copyWith({
    int? bgColor,
    int? bgOpacity,
    int? textColor,
    int? textOpacity,
  }) => WidgetAppearance(
    bgColor: bgColor ?? this.bgColor,
    bgOpacity: bgOpacity ?? this.bgOpacity,
    textColor: textColor ?? this.textColor,
    textOpacity: textOpacity ?? this.textOpacity,
  );

  Map<String, int> toMap() => {
    'bgColor': bgColor,
    'bgOpacity': bgOpacity,
    'textColor': textColor,
    'textOpacity': textOpacity,
  };

  factory WidgetAppearance.fromMap(Map<dynamic, dynamic> map) =>
      WidgetAppearance(
        bgColor: map['bgColor'] as int? ?? 0xFF303030,
        bgOpacity: map['bgOpacity'] as int? ?? 100,
        textColor: map['textColor'] as int? ?? 0xFFFFFFFF,
        textOpacity: map['textOpacity'] as int? ?? 100,
      );
}

/// 桌面小组件的原生通道封装。
///
/// 对接 `com.venti1112.edgecube/widget` 通道（见
/// [com.venti1112.edgecube.channels.WidgetChannel]）。非 Android 平台所有方法
/// 均静默空实现，使调用方无需判断平台。
///
/// 由 [ServerController] 在状态变化时（节流后）经 [pushStatus] 把
/// (status, instanceName) 推到原生；原生再把状态写入 KeepAlivePrefs 快照并
/// 触发 AppWidgetManager.updateAppWidget 使小组件即时刷新。
class WidgetService {
  WidgetService._();

  static const MethodChannel _channel =
      MethodChannel('com.venti1112.edgecube/widget');

  /// Android 8+ 返回 true（支持 requestPinAppWidget）；其它平台恒 false。
  static Future<bool> isSupported() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// 小组件总开关是否启用（receiver enabled 状态判定）。
  static Future<bool> isEnabled() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isEnabled') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// 启用/禁用桌面小组件。开启时同时通过 PackageManager 启用 receiver 并刷新，
  /// 关闭时禁用 receiver 使其不再出现在系统的小组件选择器中。
  static Future<void> setEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('setEnabled', {'enabled': enabled});
    } on PlatformException {
      // 忽略：用户可在系统层手动添加/移除。
    }
  }

  /// 读取展示选项。
  static Future<WidgetDisplayOptions> getDisplayOptions() async {
    if (!Platform.isAndroid) return const WidgetDisplayOptions();
    try {
      final map =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('getDisplayOptions');
      if (map == null) return const WidgetDisplayOptions();
      return WidgetDisplayOptions.fromMap(map);
    } on PlatformException {
      return const WidgetDisplayOptions();
    }
  }

  /// 保存展示选项；正在显示的小组件会立即刷新。
  static Future<void> setDisplayOptions(WidgetDisplayOptions options) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setDisplayOptions', {
        'options': options.toMap(),
      });
    } on PlatformException {
      // ignore
    }
  }

  /// 读取小组件外观（背景/文字颜色与不透明度）。
  static Future<WidgetAppearance> getAppearance() async {
    if (!Platform.isAndroid) return const WidgetAppearance();
    try {
      final map =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('getAppearance');
      if (map == null) return const WidgetAppearance();
      return WidgetAppearance.fromMap(map);
    } on PlatformException {
      return const WidgetAppearance();
    }
  }

  /// 保存小组件外观；已添加的小组件会立即以新外观刷新。
  static Future<void> setAppearance(WidgetAppearance appearance) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setAppearance', {
        'appearance': appearance.toMap(),
      });
    } on PlatformException {
      // ignore
    }
  }

  /// 把玩家数推到原生侧（ServerController 在每次玩家加入/离开或 list 命令后调用）。
  static Future<void> setPlayerCount(int count) async {
    if (!Platform.isAndroid) return;
    if (count < 0) count = 0;
    try {
      await _channel.invokeMethod<void>('setPlayerCount', {'count': count});
    } on PlatformException {
      // ignore
    }
  }

  /// 把公网地址推到原生侧（UPnP/STUN/DDNS 映射成功或失效时调用）。
  /// 传 null 表示当前无公网地址。
  static Future<void> setPublicAddress(String? address) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setPublicAddress', {'address': address});
    } on PlatformException {
      // ignore
    }
  }

  /// 把内网 IPv4 地址推到原生侧（服务端启动后检测一次；Wi-Fi 切换等场景
  /// 会随公网地址刷新路径重新上报）。无公网地址时小组件用它兜底显示连接入口。
  static Future<void> setLocalAddress(String? address) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setLocalAddress', {'address': address});
    } on PlatformException {
      // ignore
    }
  }

  /// 把服务端监听端口推到原生侧（启动时从配置文件读取后调用）。
  static Future<void> setServerPort(int port) async {
    if (!Platform.isAndroid) return;
    if (port <= 0) return;
    try {
      await _channel.invokeMethod<void>('setServerPort', {'port': port});
    } on PlatformException {
      // ignore
    }
  }

  /// 推送最近一次状态/实例名（ServerController 节流后调用）。
  /// [status] 可为：'stopped'/'preparing'/'starting'/'running'/'stopping'，
  /// 与 [ServerStatus] 对应。
  static Future<void> pushStatus({
    required String status,
    required String? instanceName,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('pushStatus', {
        'status': status,
        'instanceName': instanceName ?? '',
      });
    } on PlatformException {
      // ignore
    }
  }

  /// 触发一次小组件刷新（无需附带数据）。
  static Future<void> requestUpdate() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('requestUpdate');
    } on PlatformException {
      // ignore
    }
  }

  /// 请求系统把小组件钉到桌面（Android 8+ 的 requestPinAppWidget）。
  /// 返回 true 表示系统接受了请求；用户仍可在系统弹窗中取消。
  static Future<bool> requestPinWidget() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('requestPinWidget') ?? false;
    } on PlatformException {
      return false;
    }
  }
}
