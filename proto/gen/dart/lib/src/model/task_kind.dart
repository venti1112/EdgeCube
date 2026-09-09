//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'task_kind.g.dart';

class TaskKind extends EnumClass {

  /// 任务类型。实例操作(start/stop/restart/kill)、归档操作(compress/extract)与 导出/导入(export/import)按 instanceId 分组 FIFO 串行,同一实例同 kind 未结束的 任务重复提交将被拒绝(409 task_conflict)。export 打包实例工作目录为归档并写入 exports 目录;import 从实例 cwd 内的归档还原为新实例。core_update 按 POST /instances/{id}/core-update 的请求下载并替换服务端核心 jar。 analyze 为插件/模组元数据解析(后端解析,前端轮询后拉取结果)。 download_single_file 为通用单文件下载(每个任务内部绑定一个 aria2 下载任务 gid, 模组/插件等单文件下载复用):同一实例允许多个排队,按 instanceId 分组 FIFO 串行执行(一个完成再下一个),允许覆盖同名目标文件,前端负责按目标路径去重。 
  @BuiltValueEnumConst(wireName: r'start')
  static const TaskKind start = _$start;
  /// 任务类型。实例操作(start/stop/restart/kill)、归档操作(compress/extract)与 导出/导入(export/import)按 instanceId 分组 FIFO 串行,同一实例同 kind 未结束的 任务重复提交将被拒绝(409 task_conflict)。export 打包实例工作目录为归档并写入 exports 目录;import 从实例 cwd 内的归档还原为新实例。core_update 按 POST /instances/{id}/core-update 的请求下载并替换服务端核心 jar。 analyze 为插件/模组元数据解析(后端解析,前端轮询后拉取结果)。 download_single_file 为通用单文件下载(每个任务内部绑定一个 aria2 下载任务 gid, 模组/插件等单文件下载复用):同一实例允许多个排队,按 instanceId 分组 FIFO 串行执行(一个完成再下一个),允许覆盖同名目标文件,前端负责按目标路径去重。 
  @BuiltValueEnumConst(wireName: r'stop')
  static const TaskKind stop = _$stop;
  /// 任务类型。实例操作(start/stop/restart/kill)、归档操作(compress/extract)与 导出/导入(export/import)按 instanceId 分组 FIFO 串行,同一实例同 kind 未结束的 任务重复提交将被拒绝(409 task_conflict)。export 打包实例工作目录为归档并写入 exports 目录;import 从实例 cwd 内的归档还原为新实例。core_update 按 POST /instances/{id}/core-update 的请求下载并替换服务端核心 jar。 analyze 为插件/模组元数据解析(后端解析,前端轮询后拉取结果)。 download_single_file 为通用单文件下载(每个任务内部绑定一个 aria2 下载任务 gid, 模组/插件等单文件下载复用):同一实例允许多个排队,按 instanceId 分组 FIFO 串行执行(一个完成再下一个),允许覆盖同名目标文件,前端负责按目标路径去重。 
  @BuiltValueEnumConst(wireName: r'restart')
  static const TaskKind restart = _$restart;
  /// 任务类型。实例操作(start/stop/restart/kill)、归档操作(compress/extract)与 导出/导入(export/import)按 instanceId 分组 FIFO 串行,同一实例同 kind 未结束的 任务重复提交将被拒绝(409 task_conflict)。export 打包实例工作目录为归档并写入 exports 目录;import 从实例 cwd 内的归档还原为新实例。core_update 按 POST /instances/{id}/core-update 的请求下载并替换服务端核心 jar。 analyze 为插件/模组元数据解析(后端解析,前端轮询后拉取结果)。 download_single_file 为通用单文件下载(每个任务内部绑定一个 aria2 下载任务 gid, 模组/插件等单文件下载复用):同一实例允许多个排队,按 instanceId 分组 FIFO 串行执行(一个完成再下一个),允许覆盖同名目标文件,前端负责按目标路径去重。 
  @BuiltValueEnumConst(wireName: r'kill')
  static const TaskKind kill = _$kill;
  /// 任务类型。实例操作(start/stop/restart/kill)、归档操作(compress/extract)与 导出/导入(export/import)按 instanceId 分组 FIFO 串行,同一实例同 kind 未结束的 任务重复提交将被拒绝(409 task_conflict)。export 打包实例工作目录为归档并写入 exports 目录;import 从实例 cwd 内的归档还原为新实例。core_update 按 POST /instances/{id}/core-update 的请求下载并替换服务端核心 jar。 analyze 为插件/模组元数据解析(后端解析,前端轮询后拉取结果)。 download_single_file 为通用单文件下载(每个任务内部绑定一个 aria2 下载任务 gid, 模组/插件等单文件下载复用):同一实例允许多个排队,按 instanceId 分组 FIFO 串行执行(一个完成再下一个),允许覆盖同名目标文件,前端负责按目标路径去重。 
  @BuiltValueEnumConst(wireName: r'download')
  static const TaskKind download = _$download;
  /// 任务类型。实例操作(start/stop/restart/kill)、归档操作(compress/extract)与 导出/导入(export/import)按 instanceId 分组 FIFO 串行,同一实例同 kind 未结束的 任务重复提交将被拒绝(409 task_conflict)。export 打包实例工作目录为归档并写入 exports 目录;import 从实例 cwd 内的归档还原为新实例。core_update 按 POST /instances/{id}/core-update 的请求下载并替换服务端核心 jar。 analyze 为插件/模组元数据解析(后端解析,前端轮询后拉取结果)。 download_single_file 为通用单文件下载(每个任务内部绑定一个 aria2 下载任务 gid, 模组/插件等单文件下载复用):同一实例允许多个排队,按 instanceId 分组 FIFO 串行执行(一个完成再下一个),允许覆盖同名目标文件,前端负责按目标路径去重。 
  @BuiltValueEnumConst(wireName: r'export')
  static const TaskKind export_ = _$export_;
  /// 任务类型。实例操作(start/stop/restart/kill)、归档操作(compress/extract)与 导出/导入(export/import)按 instanceId 分组 FIFO 串行,同一实例同 kind 未结束的 任务重复提交将被拒绝(409 task_conflict)。export 打包实例工作目录为归档并写入 exports 目录;import 从实例 cwd 内的归档还原为新实例。core_update 按 POST /instances/{id}/core-update 的请求下载并替换服务端核心 jar。 analyze 为插件/模组元数据解析(后端解析,前端轮询后拉取结果)。 download_single_file 为通用单文件下载(每个任务内部绑定一个 aria2 下载任务 gid, 模组/插件等单文件下载复用):同一实例允许多个排队,按 instanceId 分组 FIFO 串行执行(一个完成再下一个),允许覆盖同名目标文件,前端负责按目标路径去重。 
  @BuiltValueEnumConst(wireName: r'import')
  static const TaskKind import_ = _$import_;
  /// 任务类型。实例操作(start/stop/restart/kill)、归档操作(compress/extract)与 导出/导入(export/import)按 instanceId 分组 FIFO 串行,同一实例同 kind 未结束的 任务重复提交将被拒绝(409 task_conflict)。export 打包实例工作目录为归档并写入 exports 目录;import 从实例 cwd 内的归档还原为新实例。core_update 按 POST /instances/{id}/core-update 的请求下载并替换服务端核心 jar。 analyze 为插件/模组元数据解析(后端解析,前端轮询后拉取结果)。 download_single_file 为通用单文件下载(每个任务内部绑定一个 aria2 下载任务 gid, 模组/插件等单文件下载复用):同一实例允许多个排队,按 instanceId 分组 FIFO 串行执行(一个完成再下一个),允许覆盖同名目标文件,前端负责按目标路径去重。 
  @BuiltValueEnumConst(wireName: r'backup')
  static const TaskKind backup = _$backup;
  /// 任务类型。实例操作(start/stop/restart/kill)、归档操作(compress/extract)与 导出/导入(export/import)按 instanceId 分组 FIFO 串行,同一实例同 kind 未结束的 任务重复提交将被拒绝(409 task_conflict)。export 打包实例工作目录为归档并写入 exports 目录;import 从实例 cwd 内的归档还原为新实例。core_update 按 POST /instances/{id}/core-update 的请求下载并替换服务端核心 jar。 analyze 为插件/模组元数据解析(后端解析,前端轮询后拉取结果)。 download_single_file 为通用单文件下载(每个任务内部绑定一个 aria2 下载任务 gid, 模组/插件等单文件下载复用):同一实例允许多个排队,按 instanceId 分组 FIFO 串行执行(一个完成再下一个),允许覆盖同名目标文件,前端负责按目标路径去重。 
  @BuiltValueEnumConst(wireName: r'compress')
  static const TaskKind compress = _$compress;
  /// 任务类型。实例操作(start/stop/restart/kill)、归档操作(compress/extract)与 导出/导入(export/import)按 instanceId 分组 FIFO 串行,同一实例同 kind 未结束的 任务重复提交将被拒绝(409 task_conflict)。export 打包实例工作目录为归档并写入 exports 目录;import 从实例 cwd 内的归档还原为新实例。core_update 按 POST /instances/{id}/core-update 的请求下载并替换服务端核心 jar。 analyze 为插件/模组元数据解析(后端解析,前端轮询后拉取结果)。 download_single_file 为通用单文件下载(每个任务内部绑定一个 aria2 下载任务 gid, 模组/插件等单文件下载复用):同一实例允许多个排队,按 instanceId 分组 FIFO 串行执行(一个完成再下一个),允许覆盖同名目标文件,前端负责按目标路径去重。 
  @BuiltValueEnumConst(wireName: r'extract')
  static const TaskKind extract = _$extract;
  /// 任务类型。实例操作(start/stop/restart/kill)、归档操作(compress/extract)与 导出/导入(export/import)按 instanceId 分组 FIFO 串行,同一实例同 kind 未结束的 任务重复提交将被拒绝(409 task_conflict)。export 打包实例工作目录为归档并写入 exports 目录;import 从实例 cwd 内的归档还原为新实例。core_update 按 POST /instances/{id}/core-update 的请求下载并替换服务端核心 jar。 analyze 为插件/模组元数据解析(后端解析,前端轮询后拉取结果)。 download_single_file 为通用单文件下载(每个任务内部绑定一个 aria2 下载任务 gid, 模组/插件等单文件下载复用):同一实例允许多个排队,按 instanceId 分组 FIFO 串行执行(一个完成再下一个),允许覆盖同名目标文件,前端负责按目标路径去重。 
  @BuiltValueEnumConst(wireName: r'analyze')
  static const TaskKind analyze = _$analyze;
  /// 任务类型。实例操作(start/stop/restart/kill)、归档操作(compress/extract)与 导出/导入(export/import)按 instanceId 分组 FIFO 串行,同一实例同 kind 未结束的 任务重复提交将被拒绝(409 task_conflict)。export 打包实例工作目录为归档并写入 exports 目录;import 从实例 cwd 内的归档还原为新实例。core_update 按 POST /instances/{id}/core-update 的请求下载并替换服务端核心 jar。 analyze 为插件/模组元数据解析(后端解析,前端轮询后拉取结果)。 download_single_file 为通用单文件下载(每个任务内部绑定一个 aria2 下载任务 gid, 模组/插件等单文件下载复用):同一实例允许多个排队,按 instanceId 分组 FIFO 串行执行(一个完成再下一个),允许覆盖同名目标文件,前端负责按目标路径去重。 
  @BuiltValueEnumConst(wireName: r'download_single_file')
  static const TaskKind downloadSingleFile = _$downloadSingleFile;
  /// 任务类型。实例操作(start/stop/restart/kill)、归档操作(compress/extract)与 导出/导入(export/import)按 instanceId 分组 FIFO 串行,同一实例同 kind 未结束的 任务重复提交将被拒绝(409 task_conflict)。export 打包实例工作目录为归档并写入 exports 目录;import 从实例 cwd 内的归档还原为新实例。core_update 按 POST /instances/{id}/core-update 的请求下载并替换服务端核心 jar。 analyze 为插件/模组元数据解析(后端解析,前端轮询后拉取结果)。 download_single_file 为通用单文件下载(每个任务内部绑定一个 aria2 下载任务 gid, 模组/插件等单文件下载复用):同一实例允许多个排队,按 instanceId 分组 FIFO 串行执行(一个完成再下一个),允许覆盖同名目标文件,前端负责按目标路径去重。 
  @BuiltValueEnumConst(wireName: r'core_update')
  static const TaskKind coreUpdate = _$coreUpdate;

  static Serializer<TaskKind> get serializer => _$taskKindSerializer;

  const TaskKind._(String name): super(name);

  static BuiltSet<TaskKind> get values => _$values;
  static TaskKind valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class TaskKindMixin = Object with _$TaskKindMixin;

