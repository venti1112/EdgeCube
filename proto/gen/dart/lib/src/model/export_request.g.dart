// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'export_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const ExportRequestFormatEnum _$exportRequestFormatEnum_zip =
    const ExportRequestFormatEnum._('zip');
const ExportRequestFormatEnum _$exportRequestFormatEnum_tarPeriodGz =
    const ExportRequestFormatEnum._('tarPeriodGz');

ExportRequestFormatEnum _$exportRequestFormatEnumValueOf(String name) {
  switch (name) {
    case 'zip':
      return _$exportRequestFormatEnum_zip;
    case 'tarPeriodGz':
      return _$exportRequestFormatEnum_tarPeriodGz;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<ExportRequestFormatEnum> _$exportRequestFormatEnumValues =
    BuiltSet<ExportRequestFormatEnum>(const <ExportRequestFormatEnum>[
  _$exportRequestFormatEnum_zip,
  _$exportRequestFormatEnum_tarPeriodGz,
]);

Serializer<ExportRequestFormatEnum> _$exportRequestFormatEnumSerializer =
    _$ExportRequestFormatEnumSerializer();

class _$ExportRequestFormatEnumSerializer
    implements PrimitiveSerializer<ExportRequestFormatEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'zip': 'zip',
    'tarPeriodGz': 'tar.gz',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'zip': 'zip',
    'tar.gz': 'tarPeriodGz',
  };

  @override
  final Iterable<Type> types = const <Type>[ExportRequestFormatEnum];
  @override
  final String wireName = 'ExportRequestFormatEnum';

  @override
  Object serialize(Serializers serializers, ExportRequestFormatEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  ExportRequestFormatEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      ExportRequestFormatEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$ExportRequest extends ExportRequest {
  @override
  final ExportRequestFormatEnum? format;
  @override
  final bool? includeLogs;

  factory _$ExportRequest([void Function(ExportRequestBuilder)? updates]) =>
      (ExportRequestBuilder()..update(updates))._build();

  _$ExportRequest._({this.format, this.includeLogs}) : super._();
  @override
  ExportRequest rebuild(void Function(ExportRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ExportRequestBuilder toBuilder() => ExportRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ExportRequest &&
        format == other.format &&
        includeLogs == other.includeLogs;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, format.hashCode);
    _$hash = $jc(_$hash, includeLogs.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ExportRequest')
          ..add('format', format)
          ..add('includeLogs', includeLogs))
        .toString();
  }
}

class ExportRequestBuilder
    implements Builder<ExportRequest, ExportRequestBuilder> {
  _$ExportRequest? _$v;

  ExportRequestFormatEnum? _format;
  ExportRequestFormatEnum? get format => _$this._format;
  set format(ExportRequestFormatEnum? format) => _$this._format = format;

  bool? _includeLogs;
  bool? get includeLogs => _$this._includeLogs;
  set includeLogs(bool? includeLogs) => _$this._includeLogs = includeLogs;

  ExportRequestBuilder() {
    ExportRequest._defaults(this);
  }

  ExportRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _format = $v.format;
      _includeLogs = $v.includeLogs;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ExportRequest other) {
    _$v = other as _$ExportRequest;
  }

  @override
  void update(void Function(ExportRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ExportRequest build() => _build();

  _$ExportRequest _build() {
    final _$result = _$v ??
        _$ExportRequest._(
          format: format,
          includeLogs: includeLogs,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
