import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';

/// EULA 的原文地址，对话框里点它会在外部浏览器打开。
const String kEulaUrl = 'https://aka.ms/MinecraftEULA';

/// 启动前过一遍 EULA。
///
/// * `api.eula(id)`（**判定在 daemon**，文件在服务端机器上）
/// * 已同意 → 直接 `return true`
/// * `showDialog(barrierDismissible: false)`
/// * 标题 `Minecraft EULA`、正文两句、可点的 EULA 链接（文案是固定的那两句）
/// * 「不同意」→ `return false`（**什么都不做**，调用方不启动）
/// * 「同意」→ `api.acceptEula(id)` → `true`
///
/// 调用方（`servers_page.dart` 的启动按钮）这样用：
/// `if (!await ensureEulaAgreed(...)) return;` —— **不同意就当没点过启动**。
///
/// **判断与写入都在 daemon**：V2 的文件在服务端机器上，所以那两个动作是 RPC
/// （内容也由 daemon 定死，前端给不了）—— 与 `instance.config.*` 是同一条分工。
///
/// 链接的颜色用主题色（V2 不硬编码颜色，这是既有约定）。
Future<bool> ensureEulaAgreed(
  BuildContext context,
  InstanceApi api,
  String instanceId,
) async {
  // 1) 先问 daemon：eula.txt 里有没有 eula=true
  final status = await api.eula(instanceId);
  if (status.agreed) return true;

  // 2) 没同意 → 弹框
  if (!context.mounted) return false;
  final agreed = await showDialog<bool>(
    context: context,
    // `barrierDismissible: false`：必须明确选一个，点外面关不掉
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Minecraft EULA'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('启动 Minecraft 服务端前需要同意 Minecraft 最终用户许可协议（EULA）。'),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => launchUrl(
                Uri.parse(kEulaUrl),
                mode: LaunchMode.externalApplication,
              ),
              child: Text(
                kEulaUrl,
                style: TextStyle(
                  color: Theme.of(dialogContext).colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text('点击下方「同意」将向 eula.txt 写入 eula=true，表示你已阅读并同意该协议。'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('不同意'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('同意'),
        ),
      ],
    ),
  );

  // 3) 不同意 = 什么都没发生，不写文件
  if (agreed != true) return false;

  // 4) 同意 → 让 daemon 写 eula.txt，然后放行
  await api.acceptEula(instanceId);
  return true;
}
