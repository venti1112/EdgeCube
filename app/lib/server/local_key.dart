// 本机免密凭据读取:平台相关。
// - io(Windows/Linux/Android):读取 daemon 数据目录下的 `local.key`;
// - web:浏览器无法访问本机文件,恒返回 null(只能使用远程服务器)。
export 'local_key_io.dart' if (dart.library.js_interop) 'local_key_web.dart';