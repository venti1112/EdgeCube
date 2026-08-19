// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'encoding.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const Encoding _$utf8 = const Encoding._('utf8');
const Encoding _$gbk = const Encoding._('gbk');
const Encoding _$big5 = const Encoding._('big5');
const Encoding _$shiftJis = const Encoding._('shiftJis');
const Encoding _$euckr = const Encoding._('euckr');
const Encoding _$gb18030 = const Encoding._('gb18030');
const Encoding _$utf16 = const Encoding._('utf16');

Encoding _$valueOf(String name) {
  switch (name) {
    case 'utf8':
      return _$utf8;
    case 'gbk':
      return _$gbk;
    case 'big5':
      return _$big5;
    case 'shiftJis':
      return _$shiftJis;
    case 'euckr':
      return _$euckr;
    case 'gb18030':
      return _$gb18030;
    case 'utf16':
      return _$utf16;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<Encoding> _$values = BuiltSet<Encoding>(const <Encoding>[
  _$utf8,
  _$gbk,
  _$big5,
  _$shiftJis,
  _$euckr,
  _$gb18030,
  _$utf16,
]);

class _$EncodingMeta {
  const _$EncodingMeta();
  Encoding get utf8 => _$utf8;
  Encoding get gbk => _$gbk;
  Encoding get big5 => _$big5;
  Encoding get shiftJis => _$shiftJis;
  Encoding get euckr => _$euckr;
  Encoding get gb18030 => _$gb18030;
  Encoding get utf16 => _$utf16;
  Encoding valueOf(String name) => _$valueOf(name);
  BuiltSet<Encoding> get values => _$values;
}

abstract class _$EncodingMixin {
  // ignore: non_constant_identifier_names
  _$EncodingMeta get Encoding => const _$EncodingMeta();
}

Serializer<Encoding> _$encodingSerializer = _$EncodingSerializer();

class _$EncodingSerializer implements PrimitiveSerializer<Encoding> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'utf8': 'utf-8',
    'gbk': 'gbk',
    'big5': 'big5',
    'shiftJis': 'shift_jis',
    'euckr': 'euckr',
    'gb18030': 'gb18030',
    'utf16': 'utf-16',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'utf-8': 'utf8',
    'gbk': 'gbk',
    'big5': 'big5',
    'shift_jis': 'shiftJis',
    'euckr': 'euckr',
    'gb18030': 'gb18030',
    'utf-16': 'utf16',
  };

  @override
  final Iterable<Type> types = const <Type>[Encoding];
  @override
  final String wireName = 'Encoding';

  @override
  Object serialize(Serializers serializers, Encoding object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  Encoding deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      Encoding.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
