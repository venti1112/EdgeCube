/// 单个服务器实例的元数据。
///
/// [id] 同时是该实例在磁盘上的文件夹名（随机生成、不可变）；
/// [name] 是用户可编辑的显示名称；
/// [maxMemory]、[javaVersion]、[selectedJar] 为启动配置；
/// [customJvmArgs] 为用户自定义的 JVM 参数（以空白符/换行分隔，原样附加在内置参数之后）。
class Instance {
  const Instance({
    required this.id,
    required this.name,
    this.maxMemory,
    this.javaVersion,
    this.selectedJar,
    this.customJvmArgs,
  });

  final String id;
  final String name;
  final int? maxMemory;
  final String? javaVersion;
  final String? selectedJar;
  final String? customJvmArgs;

  Instance copyWith({
    String? name,
    int? maxMemory,
    String? javaVersion,
    String? selectedJar,
    String? customJvmArgs,
    bool clearMaxMemory = false,
    bool clearJavaVersion = false,
    bool clearSelectedJar = false,
    bool clearCustomJvmArgs = false,
  }) =>
      Instance(
        id: id,
        name: name ?? this.name,
        maxMemory: clearMaxMemory ? null : (maxMemory ?? this.maxMemory),
        javaVersion: clearJavaVersion ? null : (javaVersion ?? this.javaVersion),
        selectedJar: clearSelectedJar ? null : (selectedJar ?? this.selectedJar),
        customJvmArgs:
            clearCustomJvmArgs ? null : (customJvmArgs ?? this.customJvmArgs),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (maxMemory != null) 'maxMemory': maxMemory,
        if (javaVersion != null) 'javaVersion': javaVersion,
        if (selectedJar != null) 'selectedJar': selectedJar,
        if (customJvmArgs != null) 'customJvmArgs': customJvmArgs,
      };

  factory Instance.fromJson(Map<String, dynamic> json) => Instance(
        id: json['id'] as String,
        name: json['name'] as String,
        maxMemory: json['maxMemory'] as int?,
        javaVersion: json['javaVersion'] as String?,
        selectedJar: json['selectedJar'] as String?,
        customJvmArgs: json['customJvmArgs'] as String?,
      );
}
