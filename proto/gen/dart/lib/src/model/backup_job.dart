//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'backup_job.g.dart';

/// BackupJob
///
/// Properties:
/// * [id] 
/// * [name] 
/// * [instanceId] - 备份哪个实例
/// * [scheduleCron] - 定时表达式(如 \"0 4 * * *\");null 为仅手动
/// * [targetIds] - 备份目标;空为仅本地
/// * [enabled] 
/// * [maxKeep] - 保留最近 N 份
/// * [includeDirs] - 相对 cwd 的附加目录;空为整个工作目录
/// * [lastRunAt] 
/// * [lastResult] 
@BuiltValue()
abstract class BackupJob implements Built<BackupJob, BackupJobBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'name')
  String get name;

  /// 备份哪个实例
  @BuiltValueField(wireName: r'instanceId')
  String get instanceId;

  /// 定时表达式(如 \"0 4 * * *\");null 为仅手动
  @BuiltValueField(wireName: r'scheduleCron')
  String? get scheduleCron;

  /// 备份目标;空为仅本地
  @BuiltValueField(wireName: r'targetIds')
  BuiltList<String>? get targetIds;

  @BuiltValueField(wireName: r'enabled')
  bool? get enabled;

  /// 保留最近 N 份
  @BuiltValueField(wireName: r'maxKeep')
  int? get maxKeep;

  /// 相对 cwd 的附加目录;空为整个工作目录
  @BuiltValueField(wireName: r'includeDirs')
  BuiltList<String>? get includeDirs;

  @BuiltValueField(wireName: r'lastRunAt')
  DateTime? get lastRunAt;

  @BuiltValueField(wireName: r'lastResult')
  BackupJobLastResultEnum? get lastResult;
  // enum lastResultEnum {  success,  failed,  running,  };

  BackupJob._();

  factory BackupJob([void updates(BackupJobBuilder b)]) = _$BackupJob;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BackupJobBuilder b) => b
      ..enabled = true
      ..maxKeep = 10;

  @BuiltValueSerializer(custom: true)
  static Serializer<BackupJob> get serializer => _$BackupJobSerializer();
}

class _$BackupJobSerializer implements PrimitiveSerializer<BackupJob> {
  @override
  final Iterable<Type> types = const [BackupJob, _$BackupJob];

  @override
  final String wireName = r'BackupJob';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BackupJob object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    yield r'instanceId';
    yield serializers.serialize(
      object.instanceId,
      specifiedType: const FullType(String),
    );
    if (object.scheduleCron != null) {
      yield r'scheduleCron';
      yield serializers.serialize(
        object.scheduleCron,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.targetIds != null) {
      yield r'targetIds';
      yield serializers.serialize(
        object.targetIds,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
    if (object.enabled != null) {
      yield r'enabled';
      yield serializers.serialize(
        object.enabled,
        specifiedType: const FullType(bool),
      );
    }
    if (object.maxKeep != null) {
      yield r'maxKeep';
      yield serializers.serialize(
        object.maxKeep,
        specifiedType: const FullType(int),
      );
    }
    if (object.includeDirs != null) {
      yield r'includeDirs';
      yield serializers.serialize(
        object.includeDirs,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
    if (object.lastRunAt != null) {
      yield r'lastRunAt';
      yield serializers.serialize(
        object.lastRunAt,
        specifiedType: const FullType.nullable(DateTime),
      );
    }
    if (object.lastResult != null) {
      yield r'lastResult';
      yield serializers.serialize(
        object.lastResult,
        specifiedType: const FullType.nullable(BackupJobLastResultEnum),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    BackupJob object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BackupJobBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'instanceId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.instanceId = valueDes;
          break;
        case r'scheduleCron':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.scheduleCron = valueDes;
          break;
        case r'targetIds':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(String)]),
          ) as BuiltList<String>?;
          if (valueDes == null) continue;
          result.targetIds.replace(valueDes);
          break;
        case r'enabled':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.enabled = valueDes;
          break;
        case r'maxKeep':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.maxKeep = valueDes;
          break;
        case r'includeDirs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(String)]),
          ) as BuiltList<String>?;
          if (valueDes == null) continue;
          result.includeDirs.replace(valueDes);
          break;
        case r'lastRunAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(DateTime),
          ) as DateTime?;
          if (valueDes == null) continue;
          result.lastRunAt = valueDes;
          break;
        case r'lastResult':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BackupJobLastResultEnum),
          ) as BackupJobLastResultEnum?;
          if (valueDes == null) continue;
          result.lastResult = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  BackupJob deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BackupJobBuilder();
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

class BackupJobLastResultEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'success')
  static const BackupJobLastResultEnum success = _$backupJobLastResultEnum_success;
  @BuiltValueEnumConst(wireName: r'failed')
  static const BackupJobLastResultEnum failed = _$backupJobLastResultEnum_failed;
  @BuiltValueEnumConst(wireName: r'running')
  static const BackupJobLastResultEnum running = _$backupJobLastResultEnum_running;

  static Serializer<BackupJobLastResultEnum> get serializer => _$backupJobLastResultEnumSerializer;

  const BackupJobLastResultEnum._(String name): super(name);

  static BuiltSet<BackupJobLastResultEnum> get values => _$backupJobLastResultEnumValues;
  static BackupJobLastResultEnum valueOf(String name) => _$backupJobLastResultEnumValueOf(name);
}

