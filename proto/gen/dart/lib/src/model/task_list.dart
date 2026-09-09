//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:edgecube_api_client/src/model/task.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'task_list.g.dart';

/// TaskList
///
/// Properties:
/// * [items] 
/// * [total] - 过滤后的任务总数
@BuiltValue()
abstract class TaskList implements Built<TaskList, TaskListBuilder> {
  @BuiltValueField(wireName: r'items')
  BuiltList<Task> get items;

  /// 过滤后的任务总数
  @BuiltValueField(wireName: r'total')
  int get total;

  TaskList._();

  factory TaskList([void updates(TaskListBuilder b)]) = _$TaskList;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(TaskListBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<TaskList> get serializer => _$TaskListSerializer();
}

class _$TaskListSerializer implements PrimitiveSerializer<TaskList> {
  @override
  final Iterable<Type> types = const [TaskList, _$TaskList];

  @override
  final String wireName = r'TaskList';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    TaskList object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'items';
    yield serializers.serialize(
      object.items,
      specifiedType: const FullType(BuiltList, [FullType(Task)]),
    );
    yield r'total';
    yield serializers.serialize(
      object.total,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    TaskList object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required TaskListBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'items':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(Task)]),
          ) as BuiltList<Task>;
          result.items.replace(valueDes);
          break;
        case r'total':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.total = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  TaskList deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = TaskListBuilder();
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

