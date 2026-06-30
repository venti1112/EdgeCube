import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n/i18n_service.dart';
import '../i18n/locale_scope.dart';
import '../online/update_service.dart';
import '../widgets/update_dialog.dart';

/// 「关于」页面：展示应用版本、简介、开源许可等信息。
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '';
  String _buildNumber = '';
  bool _checking = false;

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

  /// 手动检查更新。检查失败时提示出错；无更新时提示已是最新。
  Future<void> _checkUpdates() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final info = await UpdateService.checkForUpdates();
      if (info == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('about.checkUpdateFailed'))),
        );
        return;
      }
      final hasUpdate = await UpdateService.hasUpdate(info);
      if (!mounted) return;
      if (hasUpdate) {
        _showUpdateDialog(info);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('about.alreadyLatest'))),
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  /// 展示更新提示对话框，用户确认后下载并安装。
  void _showUpdateDialog(UpdateInfo info) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => UpdateDialog(info: info),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('about.title'))),
      body: ListView(
        children: [
          const SizedBox(height: 32),

          // ── 应用图标 ──
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.asset(
                'assets/images/app_logo.png',
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
                  ? context.tr('common.loading')
                  : context.tr('about.version', {
                      'version': _version,
                      'build': _buildNumber,
                    }),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ── 检查更新 ──
          Center(
            child: OutlinedButton.icon(
              onPressed: _checking ? null : _checkUpdates,
              icon: _checking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.system_update, size: 18),
              label: Text(
                _checking
                    ? context.tr('about.checking')
                    : context.tr('about.checkUpdate'),
              ),
            ),
          ),

          const SizedBox(height: 28),

          // ── 简介 ──
          Center(
            child: Text(
              context.tr('about.description'),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),

          const SizedBox(height: 32),

          // ── GitHub ──
          _sectionHeader(theme, context.tr('about.openSourceRepo')),
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

          // ── 用户协议 ──
          _sectionHeader(theme, context.tr('about.userAgreementSection')),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(context.tr('about.userAgreement')),
            subtitle: Text(context.tr('about.userAgreementDesc')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const _UserAgreementViewerPage(),
                ),
              );
            },
          ),

          // ── 开源许可 ──
          _sectionHeader(theme, context.tr('about.openSourceLicense')),
          ListTile(
            leading: const Icon(Icons.balance),
            title: const Text('GNU General Public License v3.0'),
            subtitle: Text(context.tr('about.gplNotice')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const _LicenseViewerPage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(context.tr('about.thirdPartyLicenses')),
            subtitle: Text(context.tr('about.thirdPartyLicensesDesc')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'EdgeCube',
              applicationVersion: _version.isEmpty
                  ? ''
                  : '$_version (Build $_buildNumber)',
              applicationIcon: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    'assets/images/app_logo.png',
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
                context.tr('about.copyright'),
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
  String _text = tr('common.loading');

  @override
  void initState() {
    super.initState();
    rootBundle.loadString('assets/markdown/licenses_gpl_3.0.md').then((t) {
      if (mounted) setState(() => _text = t);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GNU General Public License v3.0')),
      body: Markdown(
        data: _text,
        selectable: true,
        padding: const EdgeInsets.all(16),
        onTapLink: (text, href, title) {
          if (href != null) {
            launchUrl(
              Uri.parse(href),
              mode: LaunchMode.externalApplication,
            );
          }
        },
      ),
    );
  }
}

/// 内嵌用户协议全文查看页。
class _UserAgreementViewerPage extends StatefulWidget {
  const _UserAgreementViewerPage();

  @override
  State<_UserAgreementViewerPage> createState() =>
      _UserAgreementViewerPageState();
}

class _UserAgreementViewerPageState extends State<_UserAgreementViewerPage> {
  String _text = tr('common.loading');

  @override
  void initState() {
    super.initState();
    rootBundle.loadString('assets/markdown/user_agreement.md').then((t) {
      if (mounted) setState(() => _text = t);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('userAgreement.title'))),
      body: Markdown(
        data: _text,
        selectable: true,
        padding: const EdgeInsets.all(16),
        onTapLink: (text, href, title) {
          if (href != null) {
            launchUrl(
              Uri.parse(href),
              mode: LaunchMode.externalApplication,
            );
          }
        },
      ),
    );
  }
}
