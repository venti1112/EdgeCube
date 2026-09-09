//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'server_core_update_check.g.dart';

/// ServerCoreUpdateCheck
///
/// Properties:
/// * [supported] - 该实例是否支持服务端核心更新(当前仅 Paper 系 java 实例)
/// * [source_] - 检测到的更新源(paper = PaperMC 官方 API)
/// * [currentVersion] - 当前服务端核心版本(如 1.21.4);未知时为空串
/// * [currentBuild] - 当前核心构建号(如 214);未知时为空串
/// * [latestVersion] - 最新可用版本(如 1.21.4)
/// * [latestBuild] - 最新构建号(如 214)
/// * [downloadUrl] - 最新版核心 jar 下载地址
/// * [sha256] - 下载文件 sha256(64 位 hex)
/// * [updateAvailable] - 当前是否有可用更新(版本/构建与已装核心不一致)
@BuiltValue()
abstract class ServerCoreUpdateCheck implements Built<ServerCoreUpdateCheck, ServerCoreUpdateCheckBuilder> {
  /// 该实例是否支持服务端核心更新(当前仅 Paper 系 java 实例)
  @BuiltValueField(wireName: r'supported')
  bool get supported;

  /// 检测到的更新源(paper = PaperMC 官方 API)
  @BuiltValueField(wireName: r'source')
  ServerCoreUpdateCheckSource_Enum? get source_;
  // enum source_Enum {  paper,  unknown,  };

  /// 当前服务端核心版本(如 1.21.4);未知时为空串
  @BuiltValueField(wireName: r'currentVersion')
  String? get currentVersion;

  /// 当前核心构建号(如 214);未知时为空串
  @BuiltValueField(wireName: r'currentBuild')
  String? get currentBuild;

  /// 最新可用版本(如 1.21.4)
  @BuiltValueField(wireName: r'latestVersion')
  String? get latestVersion;

  /// 最新构建号(如 214)
  @BuiltValueField(wireName: r'latestBuild')
  String? get latestBuild;

  /// 最新版核心 jar 下载地址
  @BuiltValueField(wireName: r'downloadUrl')
  String? get downloadUrl;

  /// 下载文件 sha256(64 位 hex)
  @BuiltValueField(wireName: r'sha256')
  String? get sha256;

  /// 当前是否有可用更新(版本/构建与已装核心不一致)
  @BuiltValueField(wireName: r'updateAvailable')
  bool? get updateAvailable;

  ServerCoreUpdateCheck._();

  factory ServerCoreUpdateCheck([void updates(ServerCoreUpdateCheckBuilder b)]) = _$ServerCoreUpdateCheck;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ServerCoreUpdateCheckBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ServerCoreUpdateCheck> get serializer => _$ServerCoreUpdateCheckSerializer();
}

class _$ServerCoreUpdateCheckSerializer implements PrimitiveSerializer<ServerCoreUpdateCheck> {
  @override
  final Iterable<Type> types = const [ServerCoreUpdateCheck, _$ServerCoreUpdateCheck];

  @override
  final String wireName = r'ServerCoreUpdateCheck';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ServerCoreUpdateCheck object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'supported';
    yield serializers.serialize(
      object.supported,
      specifiedType: const FullType(bool),
    );
    if (object.source_ != null) {
      yield r'source';
      yield serializers.serialize(
        object.source_,
        specifiedType: const FullType(ServerCoreUpdateCheckSource_Enum),
      );
    }
    if (object.currentVersion != null) {
      yield r'currentVersion';
      yield serializers.serialize(
        object.currentVersion,
        specifiedType: const FullType(String),
      );
    }
    if (object.currentBuild != null) {
      yield r'currentBuild';
      yield serializers.serialize(
        object.currentBuild,
        specifiedType: const FullType(String),
      );
    }
    if (object.latestVersion != null) {
      yield r'latestVersion';
      yield serializers.serialize(
        object.latestVersion,
        specifiedType: const FullType(String),
      );
    }
    if (object.latestBuild != null) {
      yield r'latestBuild';
      yield serializers.serialize(
        object.latestBuild,
        specifiedType: const FullType(String),
      );
    }
    if (object.downloadUrl != null) {
      yield r'downloadUrl';
      yield serializers.serialize(
        object.downloadUrl,
        specifiedType: const FullType(String),
      );
    }
    if (object.sha256 != null) {
      yield r'sha256';
      yield serializers.serialize(
        object.sha256,
        specifiedType: const FullType(String),
      );
    }
    if (object.updateAvailable != null) {
      yield r'updateAvailable';
      yield serializers.serialize(
        object.updateAvailable,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ServerCoreUpdateCheck object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ServerCoreUpdateCheckBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'supported':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.supported = valueDes;
          break;
        case r'source':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(ServerCoreUpdateCheckSource_Enum),
          ) as ServerCoreUpdateCheckSource_Enum?;
          if (valueDes == null) continue;
          result.source_ = valueDes;
          break;
        case r'currentVersion':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.currentVersion = valueDes;
          break;
        case r'currentBuild':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.currentBuild = valueDes;
          break;
        case r'latestVersion':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.latestVersion = valueDes;
          break;
        case r'latestBuild':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.latestBuild = valueDes;
          break;
        case r'downloadUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.downloadUrl = valueDes;
          break;
        case r'sha256':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.sha256 = valueDes;
          break;
        case r'updateAvailable':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.updateAvailable = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ServerCoreUpdateCheck deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ServerCoreUpdateCheckBuilder();
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

class ServerCoreUpdateCheckSource_Enum extends EnumClass {

  /// 检测到的更新源(paper = PaperMC 官方 API)
  @BuiltValueEnumConst(wireName: r'paper')
  static const ServerCoreUpdateCheckSource_Enum paper = _$serverCoreUpdateCheckSourceEnum_paper;
  /// 检测到的更新源(paper = PaperMC 官方 API)
  @BuiltValueEnumConst(wireName: r'unknown')
  static const ServerCoreUpdateCheckSource_Enum unknown = _$serverCoreUpdateCheckSourceEnum_unknown;

  static Serializer<ServerCoreUpdateCheckSource_Enum> get serializer => _$serverCoreUpdateCheckSourceEnumSerializer;

  const ServerCoreUpdateCheckSource_Enum._(String name): super(name);

  static BuiltSet<ServerCoreUpdateCheckSource_Enum> get values => _$serverCoreUpdateCheckSourceEnumValues;
  static ServerCoreUpdateCheckSource_Enum valueOf(String name) => _$serverCoreUpdateCheckSourceEnumValueOf(name);
}

