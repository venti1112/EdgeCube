//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:edgecube_api_client/src/model/instance_type.dart';
import 'package:built_collection/built_collection.dart';
import 'package:edgecube_api_client/src/model/instance_config_terminal.dart';
import 'package:edgecube_api_client/src/model/encoding.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'instance_config.g.dart';

/// 实例配置。创建时仅 name 必填:startCommand 可为空串(空实例,创建后再导入服务端配置), workingDirectory 缺省由 daemon 分配 {dataDir}/files/{id}。 
///
/// Properties:
/// * [id] - 服务端生成
/// * [name] 
/// * [startCommand] - 命令行字符串(支持引号/转义,解析为参数数组 spawn,不经 shell);空串表示尚未配置启动命令
/// * [stopCommand] - 优雅停止命令;^C 表示发送 Ctrl+C
/// * [stopTimeoutSeconds] - 优雅停止超时,超时升级强杀
/// * [workingDirectory] - 工作目录(实例 cwd,文件沙箱根);创建/更新时缺省由 daemon 维护为实例专属目录,不随实例删除
/// * [environment] - 额外环境变量
/// * [inputEncoding] 
/// * [outputEncoding] 
/// * [autoRestart] - 异常/正常退出后自动重启
/// * [autoRestartMaxTimes] - 重启次数上限;-1 无限
/// * [autoStartOnBoot] - daemon 启动时自动拉起
/// * [terminal] 
/// * [type] 
/// * [runtimeId] - 引用已安装运行时(runtimes 的 RuntimeInfo.id,如 java 指定 JRE 版本)。 为空表示未指定,启动命令中的可执行文件需自行可用。 
/// * [downloadUrl] - 创建实例时的服务端下载链接(http/https)。仅在创建时生效: daemon 收到后自动发起下载任务(下载到实例工作目录),下载完成前实例暂不可启动。 更新实例时忽略本字段。 
/// * [fileName] - 下载目标文件名(仅与 downloadUrl 配合,创建时生效)。缺省由 daemon 从 URL 末段推导(如 https://.../paper-1.21.1-198.jar → paper-1.21.1-198.jar); 建议取 /catalog/download-info 返回的 fileName。 
/// * [checksum] - 下载校验值,格式 \"sha1:<hex>\" 或 \"sha256:<hex>\"(aria2 风格,不填则不做校验)。 仅与 downloadUrl 配合使用,下载完成后按算法强校验,不一致视为失败。 
/// * [downloadTaskId] - 创建实例触发的下载任务 id(只读)。创建后经 `GET /tasks/{jobId}` 查询下载进度;下载完成后保留,便于追溯。 
/// * [createdAt] 
/// * [updatedAt] 
@BuiltValue()
abstract class InstanceConfig implements Built<InstanceConfig, InstanceConfigBuilder> {
  /// 服务端生成
  @BuiltValueField(wireName: r'id')
  String? get id;

  @BuiltValueField(wireName: r'name')
  String get name;

  /// 命令行字符串(支持引号/转义,解析为参数数组 spawn,不经 shell);空串表示尚未配置启动命令
  @BuiltValueField(wireName: r'startCommand')
  String? get startCommand;

  /// 优雅停止命令;^C 表示发送 Ctrl+C
  @BuiltValueField(wireName: r'stopCommand')
  String? get stopCommand;

  /// 优雅停止超时,超时升级强杀
  @BuiltValueField(wireName: r'stopTimeoutSeconds')
  int? get stopTimeoutSeconds;

  /// 工作目录(实例 cwd,文件沙箱根);创建/更新时缺省由 daemon 维护为实例专属目录,不随实例删除
  @BuiltValueField(wireName: r'workingDirectory')
  String? get workingDirectory;

  /// 额外环境变量
  @BuiltValueField(wireName: r'environment')
  BuiltMap<String, String>? get environment;

  @BuiltValueField(wireName: r'inputEncoding')
  Encoding? get inputEncoding;
  // enum inputEncodingEnum {  utf-8,  gbk,  big5,  shift_jis,  euckr,  gb18030,  utf-16,  };

  @BuiltValueField(wireName: r'outputEncoding')
  Encoding? get outputEncoding;
  // enum outputEncodingEnum {  utf-8,  gbk,  big5,  shift_jis,  euckr,  gb18030,  utf-16,  };

  /// 异常/正常退出后自动重启
  @BuiltValueField(wireName: r'autoRestart')
  bool? get autoRestart;

  /// 重启次数上限;-1 无限
  @BuiltValueField(wireName: r'autoRestartMaxTimes')
  int? get autoRestartMaxTimes;

  /// daemon 启动时自动拉起
  @BuiltValueField(wireName: r'autoStartOnBoot')
  bool? get autoStartOnBoot;

  @BuiltValueField(wireName: r'terminal')
  InstanceConfigTerminal? get terminal;

  @BuiltValueField(wireName: r'type')
  InstanceType? get type;
  // enum typeEnum {  minecraft-java,  minecraft-bedrock,  pocketmine,  generic,  };

  /// 引用已安装运行时(runtimes 的 RuntimeInfo.id,如 java 指定 JRE 版本)。 为空表示未指定,启动命令中的可执行文件需自行可用。 
  @BuiltValueField(wireName: r'runtimeId')
  String? get runtimeId;

  /// 创建实例时的服务端下载链接(http/https)。仅在创建时生效: daemon 收到后自动发起下载任务(下载到实例工作目录),下载完成前实例暂不可启动。 更新实例时忽略本字段。 
  @BuiltValueField(wireName: r'downloadUrl')
  String? get downloadUrl;

  /// 下载目标文件名(仅与 downloadUrl 配合,创建时生效)。缺省由 daemon 从 URL 末段推导(如 https://.../paper-1.21.1-198.jar → paper-1.21.1-198.jar); 建议取 /catalog/download-info 返回的 fileName。 
  @BuiltValueField(wireName: r'fileName')
  String? get fileName;

  /// 下载校验值,格式 \"sha1:<hex>\" 或 \"sha256:<hex>\"(aria2 风格,不填则不做校验)。 仅与 downloadUrl 配合使用,下载完成后按算法强校验,不一致视为失败。 
  @BuiltValueField(wireName: r'checksum')
  String? get checksum;

  /// 创建实例触发的下载任务 id(只读)。创建后经 `GET /tasks/{jobId}` 查询下载进度;下载完成后保留,便于追溯。 
  @BuiltValueField(wireName: r'downloadTaskId')
  String? get downloadTaskId;

  @BuiltValueField(wireName: r'createdAt')
  DateTime? get createdAt;

  @BuiltValueField(wireName: r'updatedAt')
  DateTime? get updatedAt;

  InstanceConfig._();

  factory InstanceConfig([void updates(InstanceConfigBuilder b)]) = _$InstanceConfig;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(InstanceConfigBuilder b) => b
      ..startCommand = ''
      ..stopCommand = '^C'
      ..stopTimeoutSeconds = 600
      ..autoRestart = false
      ..autoRestartMaxTimes = -1
      ..autoStartOnBoot = false;

  @BuiltValueSerializer(custom: true)
  static Serializer<InstanceConfig> get serializer => _$InstanceConfigSerializer();
}

class _$InstanceConfigSerializer implements PrimitiveSerializer<InstanceConfig> {
  @override
  final Iterable<Type> types = const [InstanceConfig, _$InstanceConfig];

  @override
  final String wireName = r'InstanceConfig';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    InstanceConfig object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.id != null) {
      yield r'id';
      yield serializers.serialize(
        object.id,
        specifiedType: const FullType(String),
      );
    }
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    if (object.startCommand != null) {
      yield r'startCommand';
      yield serializers.serialize(
        object.startCommand,
        specifiedType: const FullType(String),
      );
    }
    if (object.stopCommand != null) {
      yield r'stopCommand';
      yield serializers.serialize(
        object.stopCommand,
        specifiedType: const FullType(String),
      );
    }
    if (object.stopTimeoutSeconds != null) {
      yield r'stopTimeoutSeconds';
      yield serializers.serialize(
        object.stopTimeoutSeconds,
        specifiedType: const FullType(int),
      );
    }
    if (object.workingDirectory != null) {
      yield r'workingDirectory';
      yield serializers.serialize(
        object.workingDirectory,
        specifiedType: const FullType(String),
      );
    }
    if (object.environment != null) {
      yield r'environment';
      yield serializers.serialize(
        object.environment,
        specifiedType: const FullType(BuiltMap, [FullType(String), FullType(String)]),
      );
    }
    if (object.inputEncoding != null) {
      yield r'inputEncoding';
      yield serializers.serialize(
        object.inputEncoding,
        specifiedType: const FullType(Encoding),
      );
    }
    if (object.outputEncoding != null) {
      yield r'outputEncoding';
      yield serializers.serialize(
        object.outputEncoding,
        specifiedType: const FullType(Encoding),
      );
    }
    if (object.autoRestart != null) {
      yield r'autoRestart';
      yield serializers.serialize(
        object.autoRestart,
        specifiedType: const FullType(bool),
      );
    }
    if (object.autoRestartMaxTimes != null) {
      yield r'autoRestartMaxTimes';
      yield serializers.serialize(
        object.autoRestartMaxTimes,
        specifiedType: const FullType(int),
      );
    }
    if (object.autoStartOnBoot != null) {
      yield r'autoStartOnBoot';
      yield serializers.serialize(
        object.autoStartOnBoot,
        specifiedType: const FullType(bool),
      );
    }
    if (object.terminal != null) {
      yield r'terminal';
      yield serializers.serialize(
        object.terminal,
        specifiedType: const FullType(InstanceConfigTerminal),
      );
    }
    if (object.type != null) {
      yield r'type';
      yield serializers.serialize(
        object.type,
        specifiedType: const FullType(InstanceType),
      );
    }
    if (object.runtimeId != null) {
      yield r'runtimeId';
      yield serializers.serialize(
        object.runtimeId,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.downloadUrl != null) {
      yield r'downloadUrl';
      yield serializers.serialize(
        object.downloadUrl,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.fileName != null) {
      yield r'fileName';
      yield serializers.serialize(
        object.fileName,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.checksum != null) {
      yield r'checksum';
      yield serializers.serialize(
        object.checksum,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.downloadTaskId != null) {
      yield r'downloadTaskId';
      yield serializers.serialize(
        object.downloadTaskId,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.createdAt != null) {
      yield r'createdAt';
      yield serializers.serialize(
        object.createdAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.updatedAt != null) {
      yield r'updatedAt';
      yield serializers.serialize(
        object.updatedAt,
        specifiedType: const FullType(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    InstanceConfig object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required InstanceConfigBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.id = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'startCommand':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.startCommand = valueDes;
          break;
        case r'stopCommand':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.stopCommand = valueDes;
          break;
        case r'stopTimeoutSeconds':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.stopTimeoutSeconds = valueDes;
          break;
        case r'workingDirectory':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.workingDirectory = valueDes;
          break;
        case r'environment':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltMap, [FullType(String), FullType(String)]),
          ) as BuiltMap<String, String>?;
          if (valueDes == null) continue;
          result.environment.replace(valueDes);
          break;
        case r'inputEncoding':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(Encoding),
          ) as Encoding?;
          if (valueDes == null) continue;
          result.inputEncoding = valueDes;
          break;
        case r'outputEncoding':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(Encoding),
          ) as Encoding?;
          if (valueDes == null) continue;
          result.outputEncoding = valueDes;
          break;
        case r'autoRestart':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.autoRestart = valueDes;
          break;
        case r'autoRestartMaxTimes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.autoRestartMaxTimes = valueDes;
          break;
        case r'autoStartOnBoot':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.autoStartOnBoot = valueDes;
          break;
        case r'terminal':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(InstanceConfigTerminal),
          ) as InstanceConfigTerminal?;
          if (valueDes == null) continue;
          result.terminal.replace(valueDes);
          break;
        case r'type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(InstanceType),
          ) as InstanceType?;
          if (valueDes == null) continue;
          result.type = valueDes;
          break;
        case r'runtimeId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.runtimeId = valueDes;
          break;
        case r'downloadUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.downloadUrl = valueDes;
          break;
        case r'fileName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.fileName = valueDes;
          break;
        case r'checksum':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.checksum = valueDes;
          break;
        case r'downloadTaskId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.downloadTaskId = valueDes;
          break;
        case r'createdAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(DateTime),
          ) as DateTime?;
          if (valueDes == null) continue;
          result.createdAt = valueDes;
          break;
        case r'updatedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(DateTime),
          ) as DateTime?;
          if (valueDes == null) continue;
          result.updatedAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  InstanceConfig deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = InstanceConfigBuilder();
    final serializedList = (serialized as Iterable<Object?>).toList();
    final unhandled = <Object?>[];
    _deserializeProperties(
      serializers,
      serialized,
      specifiedType: specifiedType,
      serializedList: serializedList,
      unhandled: unhandled,
      result: result,
    );
    return result.build();
  }
}

