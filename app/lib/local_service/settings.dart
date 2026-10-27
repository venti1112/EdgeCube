import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage.dart';

/// 本地服务开关的存储键。
///
/// **与「地址是不是 127.0.0.1」无关**:daemon 可以单独跑在本机,
/// 那只是普通远程配置;只有这里为 true 才表示「由 App 自己拉起本地服务」。
const localServiceEnabledStorageKey = 'local_service_enabled';

/// 启动时读到的开关(默认关闭),main() 中 override。
final initialLocalServiceEnabledProvider = Provider<bool>((ref) => false);

bool loadLocalServiceEnabled(SharedPreferences storage) =>
    storage.getBool(localServiceEnabledStorageKey) ?? false;

/// 本地服务开关的**唯一真源**。
///
/// 打开 = 希望 App 启动时自动拉起本地服务(并尝试连接);
/// 关闭 = 停止本地服务,下次启动也不再自动启动。
final localServiceEnabledProvider =
    NotifierProvider<LocalServiceEnabledNotifier, bool>(
      LocalServiceEnabledNotifier.new,
    );

class LocalServiceEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(initialLocalServiceEnabledProvider);

  Future<void> set(bool value) async {
    if (state == value) return;
    state = value;
    await ref
        .read(storageProvider)
        .setBool(localServiceEnabledStorageKey, value);
  }
}
