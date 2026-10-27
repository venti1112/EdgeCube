/// 客户端本机目录的平台分派：IO 上真遍历目录，Web 上不支持「导入文件夹」。
///
/// 「导入」的数据流是「本机 → App → daemon（HTTP 上传）」：daemon 是远端进程，
/// 客户端本机的路径对它没有意义，所以本机这一半全在 App 里做。
library;

export 'client_files_io.dart'
    if (dart.library.js_interop) 'client_files_web.dart';

export 'local_folder.dart';
