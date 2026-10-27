/// Web 端没有本机文件系统可读；CPU 与内存由浏览器 API 提供，
/// 见 `about.dart` 的 web 分支。
int? localCpuCores() => null;

String? localHostname() => null;

int? localMemoryMb() => null;
