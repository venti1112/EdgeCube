/// 服务端配置的字段表模型。
///
/// # 分工：daemon 认文件，这里认字段
///
/// 「这个实例用的是哪种配置」由 daemon 判断（`instance.config.get` 回 `kind`），
/// 因为依据是**磁盘上的文件**；而「每种配置有哪些字段、叫什么、用什么控件」
/// 是**展示**的事，留在前端（字段表见 `sections.dart`）。
///
/// 所以这一层没有任何 I/O：只描述「怎么把一份文本画成表单」。
///
/// # 为什么 Java 与 PocketMine 是两个 kind
///
/// 两者共用 `server.properties` 这个文件名，但字段的**取值集合**不同
/// （布尔值 Java 写 `true`/`false`、PocketMine 写 `on`/`off`；gamemode 一个
/// 小写一个全大写），所以要两张不同的字段表。daemon 看文件内容给出 `java` /
/// `pmmp` 两个不同的 kind，前端各选一张。
/// `ConfigSection` 要拿 `IconData`，所以这里引一下 material_ui
/// （仓库规定：不 import `package:flutter/material.dart`）。
library;

import 'package:material_ui/material_ui.dart';

/// 字段用什么控件。
enum ConfigFieldKind {
  /// 单行文本。
  text,

  /// 数字（只允许数字与负号）。
  number,

  /// 开关。
  toggle,

  /// 下拉。
  dropdown,
}

/// 布尔值在文件里写成什么。
///
/// Java / PNX 是 `true` / `false`，PocketMine 是 `on` / `off`。
enum BoolFormat {
  trueFalse,
  onOff;

  /// 把开关的布尔值写回文件时用的字符串。
  String encode(bool value) => switch (this) {
    BoolFormat.trueFalse => value.toString(),
    BoolFormat.onOff => value ? 'on' : 'off',
  };

  /// 从文件里的字符串读回布尔值；两种写法都认（**读宽容、写按格式** ——
  /// 用户手上那份文件可能是改过写法的）。
  static bool? decode(String? raw) => switch (raw?.toLowerCase()) {
    'true' || 'on' => true,
    'false' || 'off' => false,
    _ => null,
  };
}

/// 一个字段的定义。
class ConfigFieldDef {
  const ConfigFieldDef({
    required this.key,
    required this.label,
    this.subtitle,
    required this.kind,
    this.options,
    this.min,
    this.max,
    this.boolFormat = BoolFormat.trueFalse,
  });

  /// 文件里的键。
  ///
  /// `server.properties` 是裸键（`motd`）；`pnx.yml` / `server-settings.yml` 是
  /// **点分路径**（`settings.motd`）。
  final String key;

  /// 显示名。
  final String label;

  /// 副标题 / 输入框下方那一行说明。
  final String? subtitle;

  final ConfigFieldKind kind;

  /// 下拉的「文件里的值 → 显示文案」。值是原样写回文件的东西，不能拿文案当键。
  final Map<String, String>? options;

  /// 数字的合法区间（仅用于提示与输入过滤，不拦保存 —— 合不合法服务端自己判断）。
  final int? min;
  final int? max;

  final BoolFormat boolFormat;
}

/// 一组字段（画成一张卡）。
class ConfigSection {
  const ConfigSection({
    required this.title,
    required this.icon,
    required this.fields,
  });

  final String title;
  final IconData icon;
  final List<ConfigFieldDef> fields;
}
