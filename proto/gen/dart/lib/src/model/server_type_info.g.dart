// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'server_type_info.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const ServerTypeInfoCategoryEnum _$serverTypeInfoCategoryEnum_vanilla =
    const ServerTypeInfoCategoryEnum._('vanilla');
const ServerTypeInfoCategoryEnum _$serverTypeInfoCategoryEnum_plugin =
    const ServerTypeInfoCategoryEnum._('plugin');
const ServerTypeInfoCategoryEnum _$serverTypeInfoCategoryEnum_mod =
    const ServerTypeInfoCategoryEnum._('mod');
const ServerTypeInfoCategoryEnum _$serverTypeInfoCategoryEnum_proxy =
    const ServerTypeInfoCategoryEnum._('proxy');
const ServerTypeInfoCategoryEnum _$serverTypeInfoCategoryEnum_bedrock =
    const ServerTypeInfoCategoryEnum._('bedrock');

ServerTypeInfoCategoryEnum _$serverTypeInfoCategoryEnumValueOf(String name) {
  switch (name) {
    case 'vanilla':
      return _$serverTypeInfoCategoryEnum_vanilla;
    case 'plugin':
      return _$serverTypeInfoCategoryEnum_plugin;
    case 'mod':
      return _$serverTypeInfoCategoryEnum_mod;
    case 'proxy':
      return _$serverTypeInfoCategoryEnum_proxy;
    case 'bedrock':
      return _$serverTypeInfoCategoryEnum_bedrock;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<ServerTypeInfoCategoryEnum> _$serverTypeInfoCategoryEnumValues =
    BuiltSet<ServerTypeInfoCategoryEnum>(const <ServerTypeInfoCategoryEnum>[
  _$serverTypeInfoCategoryEnum_vanilla,
  _$serverTypeInfoCategoryEnum_plugin,
  _$serverTypeInfoCategoryEnum_mod,
  _$serverTypeInfoCategoryEnum_proxy,
  _$serverTypeInfoCategoryEnum_bedrock,
]);

Serializer<ServerTypeInfoCategoryEnum> _$serverTypeInfoCategoryEnumSerializer =
    _$ServerTypeInfoCategoryEnumSerializer();

class _$ServerTypeInfoCategoryEnumSerializer
    implements PrimitiveSerializer<ServerTypeInfoCategoryEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'vanilla': 'vanilla',
    'plugin': 'plugin',
    'mod': 'mod',
    'proxy': 'proxy',
    'bedrock': 'bedrock',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'vanilla': 'vanilla',
    'plugin': 'plugin',
    'mod': 'mod',
    'proxy': 'proxy',
    'bedrock': 'bedrock',
  };

  @override
  final Iterable<Type> types = const <Type>[ServerTypeInfoCategoryEnum];
  @override
  final String wireName = 'ServerTypeInfoCategoryEnum';

  @override
  Object serialize(Serializers serializers, ServerTypeInfoCategoryEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  ServerTypeInfoCategoryEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      ServerTypeInfoCategoryEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$ServerTypeInfo extends ServerTypeInfo {
  @override
  final String type;
  @override
  final ServerTypeInfoCategoryEnum category;
  @override
  final bool? hasLoader;
  @override
  final String fileName;

  factory _$ServerTypeInfo([void Function(ServerTypeInfoBuilder)? updates]) =>
      (ServerTypeInfoBuilder()..update(updates))._build();

  _$ServerTypeInfo._(
      {required this.type,
      required this.category,
      this.hasLoader,
      required this.fileName})
      : super._();
  @override
  ServerTypeInfo rebuild(void Function(ServerTypeInfoBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ServerTypeInfoBuilder toBuilder() => ServerTypeInfoBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ServerTypeInfo &&
        type == other.type &&
        category == other.category &&
        hasLoader == other.hasLoader &&
        fileName == other.fileName;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, type.hashCode);
    _$hash = $jc(_$hash, category.hashCode);
    _$hash = $jc(_$hash, hasLoader.hashCode);
    _$hash = $jc(_$hash, fileName.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ServerTypeInfo')
          ..add('type', type)
          ..add('category', category)
          ..add('hasLoader', hasLoader)
          ..add('fileName', fileName))
        .toString();
  }
}

class ServerTypeInfoBuilder
    implements Builder<ServerTypeInfo, ServerTypeInfoBuilder> {
  _$ServerTypeInfo? _$v;

  String? _type;
  String? get type => _$this._type;
  set type(String? type) => _$this._type = type;

  ServerTypeInfoCategoryEnum? _category;
  ServerTypeInfoCategoryEnum? get category => _$this._category;
  set category(ServerTypeInfoCategoryEnum? category) =>
      _$this._category = category;

  bool? _hasLoader;
  bool? get hasLoader => _$this._hasLoader;
  set hasLoader(bool? hasLoader) => _$this._hasLoader = hasLoader;

  String? _fileName;
  String? get fileName => _$this._fileName;
  set fileName(String? fileName) => _$this._fileName = fileName;

  ServerTypeInfoBuilder() {
    ServerTypeInfo._defaults(this);
  }

  ServerTypeInfoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _type = $v.type;
      _category = $v.category;
      _hasLoader = $v.hasLoader;
      _fileName = $v.fileName;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ServerTypeInfo other) {
    _$v = other as _$ServerTypeInfo;
  }

  @override
  void update(void Function(ServerTypeInfoBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ServerTypeInfo build() => _build();

  _$ServerTypeInfo _build() {
    final _$result = _$v ??
        _$ServerTypeInfo._(
          type: BuiltValueNullFieldError.checkNotNull(
              type, r'ServerTypeInfo', 'type'),
          category: BuiltValueNullFieldError.checkNotNull(
              category, r'ServerTypeInfo', 'category'),
          hasLoader: hasLoader,
          fileName: BuiltValueNullFieldError.checkNotNull(
              fileName, r'ServerTypeInfo', 'fileName'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
