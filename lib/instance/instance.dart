/// 单个服务器实例的元数据。
///
/// [id] 同时是该实例在磁盘上的文件夹名（随机生成、不可变）；
/// [name] 是用户可编辑的显示名称。
class Instance {
  const Instance({required this.id, required this.name});

  final String id;
  final String name;

  Instance copyWith({String? name}) =>
      Instance(id: id, name: name ?? this.name);

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory Instance.fromJson(Map<String, dynamic> json) => Instance(
        id: json['id'] as String,
        name: json['name'] as String,
      );
}
