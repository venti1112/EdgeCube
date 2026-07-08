class DownloadInfo {
  const DownloadInfo({required this.url, this.sha1, this.sha256});

  final String url;
  final String? sha1;
  final String? sha256;
}
