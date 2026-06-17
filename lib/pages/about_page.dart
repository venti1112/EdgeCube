import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// 「关于」页面：展示应用版本、简介、开源许可等信息。
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '';
  String _buildNumber = '';

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _version = info.version;
      _buildNumber = info.buildNumber;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        children: [
          const SizedBox(height: 32),

          // ── 应用图标 ──
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.asset(
                'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
                width: 96,
                height: 96,
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── 应用名称 ──
          Center(
            child: Text(
              'EdgeCube',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const SizedBox(height: 6),

          // ── 版本号 ──
          Center(
            child: Text(
              _version.isEmpty
                  ? '加载中…'
                  : '版本 $_version (Build $_buildNumber)',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),

          const SizedBox(height: 28),

          // ── 简介 ──
          Center(
            child: Text(
              '在 Android 设备上运行 Minecraft 服务器',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),

          const SizedBox(height: 32),

          // ── GitHub ──
          _sectionHeader(theme, '开源仓库'),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('GitHub'),
            subtitle: const Text('github.com/venti1112/EdgeCube'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => launchUrl(
              Uri.parse('https://github.com/venti1112/EdgeCube'),
              mode: LaunchMode.externalApplication,
            ),
          ),

          const Divider(),

          // ── 开源许可 ──
          _sectionHeader(theme, '开源许可'),
          ListTile(
            leading: const Icon(Icons.balance),
            title: const Text('GNU General Public License v3.0'),
            subtitle: const Text('EdgeCube 是自由软件，遵循 GPL-3.0 开源协议'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const _LicenseViewerPage(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('第三方依赖开源协议'),
            subtitle: const Text('查看本项目使用的第三方库许可'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'EdgeCube',
              applicationVersion:
                  _version.isEmpty ? '' : '$_version (Build $_buildNumber)',
              applicationIcon: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
                    width: 64,
                    height: 64,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── 底部版权 ──
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                '© 2026 venti1112\n基于 GPL-3.0 协议开源',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.6,
                ),
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sectionHeader(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// 内嵌 GPL-3.0 协议全文查看页。
class _LicenseViewerPage extends StatefulWidget {
  const _LicenseViewerPage();

  @override
  State<_LicenseViewerPage> createState() => _LicenseViewerPageState();
}

class _LicenseViewerPageState extends State<_LicenseViewerPage> {
  String _text = '加载中…';

  @override
  void initState() {
    super.initState();
    rootBundle.loadString('LICENSE').then((t) {
      if (mounted) setState(() => _text = t);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GNU General Public License v3.0')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          _text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                height: 1.5,
              ),
        ),
      ),
    );
  }
}
