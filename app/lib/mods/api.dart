import '../connection/client.dart';
import 'models.dart';

/// 模组 / 插件接口：搜索、版本、已装管理与更新检查**全部由 daemon 出网**。
///
/// 为什么不让 App 自己打 Modrinth：每个客户端各打一遍既慢又各自撞上游
/// 300 次/分钟的限流，而客户端所在网络（尤其移动网络）还不一定通。
/// daemon 则是一处出网、一处缓存（搜索与版本列表在它那边缓存 5 分钟）。
class ModsApi {
  const ModsApi(this._client);

  final DaemonClient _client;

  /// 源 / 项目类型 / 加载器 / 排序表。**筛选器的唯一出处**。
  Future<ModCatalog> catalog() async {
    final result = await _client.callObject('mods.sources');
    return ModCatalog.fromJson(result);
  }

  /// 可选的游戏版本（上游）+ 该项目类型可筛的加载器。
  Future<ModTags> tags({String? projectType}) async {
    final result = await _client.callObject(
      'mods.tags',
      params: {'project_type': ?projectType},
    );
    return ModTags.fromJson(result);
  }

  /// 搜索或只是浏览（`query` 为空时按 sort 排）。
  Future<ModSearchPage> search({
    required String projectType,
    String query = '',
    String? loader,
    String? gameVersion,
    String? sort,
    int offset = 0,
    int limit = 20,
  }) async {
    final params = <String, dynamic>{
      'project_type': projectType,
      'query': query,
      'offset': offset,
      'limit': limit,
    };
    if (loader != null && loader.isNotEmpty) params['loader'] = loader;
    if (gameVersion != null && gameVersion.isNotEmpty) {
      params['game_version'] = gameVersion;
    }
    if (sort != null && sort.isNotEmpty) params['sort'] = sort;

    final result = await _client.callObject('mods.search', params: params);
    return ModSearchPage.fromJson(result);
  }

  /// 一个项目的版本列表（新版本在前）。
  ///
  /// 传 [loader] / [gameVersion] 是让**上游**筛，比拿全量再本地过滤可靠 ——
  /// 上游的版本兼容信息比我们能推断的准。
  Future<List<ModVersion>> versions({
    required String projectId,
    String? loader,
    String? gameVersion,
  }) async {
    final params = <String, dynamic>{'project_id': projectId};
    if (loader != null && loader.isNotEmpty) params['loader'] = loader;
    if (gameVersion != null && gameVersion.isNotEmpty) {
      params['game_version'] = gameVersion;
    }

    final result = await _client.callObject('mods.versions', params: params);
    return [
      if (result['versions'] is List)
        for (final item in result['versions'] as List)
          if (item is Map) ModVersion.fromJson(item.cast<String, dynamic>()),
    ];
  }

  /// 实例里已装的模组与插件（含从 jar 里读到的名字 / 版本）。
  Future<InstalledMods> installed(String instanceId) async {
    final result = await _client.callObject(
      'mods.installed',
      params: {'instance_id': instanceId},
    );
    return InstalledMods.fromJson(result);
  }

  /// 按已装文件的 sha1 批量反查上游最新版本。**只查启用中的文件。**
  ///
  /// 算哈希要整读一遍文件，所以这是用户主动点的动作，不是进页面就跑。
  Future<ModUpdateReport> checkUpdates({
    required String instanceId,
    String? projectType,
    String? loader,
    String? gameVersion,
  }) async {
    final params = <String, dynamic>{'instance_id': instanceId};
    if (projectType != null && projectType.isNotEmpty) {
      params['project_type'] = projectType;
    }
    if (loader != null && loader.isNotEmpty) params['loader'] = loader;
    if (gameVersion != null && gameVersion.isNotEmpty) {
      params['game_version'] = gameVersion;
    }

    final result = await _client.callObject('mods.check_updates', params: params);
    return ModUpdateReport.fromJson(result);
  }

  /// 按已装文件的 sha1 对回上游项目 —— **列表左侧的图标靠它**。
  ///
  /// 与 [checkUpdates] 分成两个调用是有意的：这个要「这个哈希属于哪个项目」（准），
  /// 那个要「这个项目现在最新是哪个版本」（新）。哈希在 daemon 那边有缓存，
  /// 所以两次调用只会算一遍。
  Future<ModMatchReport> matchProjects({
    required String instanceId,
    String? projectType,
  }) async {
    final result = await _client.callObject(
      'mods.match_projects',
      params: {
        'instance_id': instanceId,
        'project_type': ?projectType,
      },
    );
    return ModMatchReport.fromJson(result);
  }

  /// 启用 / 禁用（改名为 `.disabled`）。幂等。
  ///
  /// 返回改名后的文件名 —— 调用方拿它更新列表，不必重扫一遍。
  Future<String> setEnabled({
    required String instanceId,
    required String projectType,
    required String fileName,
    required bool enabled,
  }) async {
    final result = await _client.callObject(
      'mods.set_enabled',
      params: {
        'instance_id': instanceId,
        'project_type': projectType,
        'file_name': fileName,
        'enabled': enabled,
      },
    );
    return result['file_name'] as String? ?? fileName;
  }

  /// 删除一个已装文件。
  Future<void> remove({
    required String instanceId,
    required String projectType,
    required String fileName,
  }) async {
    await _client.callObject(
      'mods.remove',
      params: {
        'instance_id': instanceId,
        'project_type': projectType,
        'file_name': fileName,
      },
    );
  }
}

/// 把模组模块的异常翻成给用户看的一句话。
///
/// 关键是分清四类：**你选错了**（换一个就好）、**上游没有**（可能是项目被删）、
/// **网络 / 上游挂了**（可以重试）、**daemon 该升级了**（上游改了接口）。
/// 按 `code` 分支，不要匹配 message。
String describeModsError(Object error) {
  if (error is DaemonException) {
    return switch (error.code) {
      'mods_type_not_found' => '这个项目类型不支持（daemon 版本可能不一致）',
      'mods_source_not_found' => '这个下载源不支持（daemon 版本可能不一致）',
      'mods_not_found' => '找不到这个项目或文件（可能已被上游下架）',
      'mods_version_not_found' => '这个版本拿不到，换一个试试',
      'mods_loader_unsupported' => error.message,
      'mods_no_file' => '这个版本没有可下载的文件，换一个版本试试',
      'mods_target_exists' => '这个文件已经在实例目录里了，先删掉它再装',
      'mods_not_a_file' => '这个路径不是一个文件，没法删除',
      'mods_io_error' => '读写实例目录失败（${error.message}）',
      'mods_instance_not_found' => '找不到这个实例（它可能已经被删了）',
      'mods_upstream_error' => '连不上 Modrinth（${error.message}），检查一下网络再重试',
      'mods_parse_error' => 'Modrinth 改了接口，需要升级 daemon：${error.message}',
      'mods_unavailable' => '模组模块还没就绪（daemon 可能正在启动或关闭）',
      _ => error.message,
    };
  }
  return '$error';
}
