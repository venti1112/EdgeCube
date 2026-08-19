//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'encoding.g.dart';

class Encoding extends EnumClass {

  @BuiltValueEnumConst(wireName: r'utf-8')
  static const Encoding utf8 = _$utf8;
  @BuiltValueEnumConst(wireName: r'gbk')
  static const Encoding gbk = _$gbk;
  @BuiltValueEnumConst(wireName: r'big5')
  static const Encoding big5 = _$big5;
  @BuiltValueEnumConst(wireName: r'shift_jis')
  static const Encoding shiftJis = _$shiftJis;
  @BuiltValueEnumConst(wireName: r'euckr')
  static const Encoding euckr = _$euckr;
  @BuiltValueEnumConst(wireName: r'gb18030')
  static const Encoding gb18030 = _$gb18030;
  @BuiltValueEnumConst(wireName: r'utf-16')
  static const Encoding utf16 = _$utf16;

  static Serializer<Encoding> get serializer => _$encodingSerializer;

  const Encoding._(String name): super(name);

  static BuiltSet<Encoding> get values => _$values;
  static Encoding valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class EncodingMixin = Object with _$EncodingMixin;

