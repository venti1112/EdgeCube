import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 「单项设置全局 Provider」的公共骨架。
///
/// 一个设置模块的结构固定为两部分:
///
///  * **聚合状态 `S`** —— 唯一真源,负责校验(clamp)与落盘,读写规则只写一份;
///  * **单项 Provider** —— 只是门面,`build()` 从聚合状态里 `select` 出自己那一项,
///    `set(v)` 转发给聚合 Notifier。
///
/// 于是既能「一项一个全局 Provider」地细粒度订阅(改 A 不会重建 B 的控件),
/// 又不会出现两份真源。注意:**不要给每项单独开一个存储 key**,
/// 多 key 读-改-写会互相覆盖;一个 key 存整份 JSON 才有一致性。
///
/// 子类只需要声明聚合 Provider 从哪来([aggregate]),再实现
/// [selectValue] / [applyValue] 两个方法。
abstract class SettingNotifierBase<S, T, N extends Notifier<S>>
    extends Notifier<T> {
  /// 聚合状态 Provider(唯一真源)。
  NotifierProvider<N, S> get aggregate;

  /// 从聚合状态里取出本项的值。
  T selectValue(S state);

  /// 把本项的新值交给聚合状态,由它负责 clamp 与落盘。
  Future<void> applyValue(N notifier, T value);

  @override
  T build() => ref.watch(aggregate.select(selectValue));

  /// 写入本项设置。
  Future<void> set(T value) => applyValue(ref.read(aggregate.notifier), value);
}
