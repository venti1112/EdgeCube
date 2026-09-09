//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_import

import 'package:one_of_serializer/any_of_serializer.dart';
import 'package:one_of_serializer/one_of_serializer.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:built_value/standard_json_plugin.dart';
import 'package:built_value/iso_8601_date_time_serializer.dart';
import 'package:edgecube_api_client/src/date_serializer.dart';
import 'package:edgecube_api_client/src/model/date.dart';

import 'package:edgecube_api_client/src/model/backup_job.dart';
import 'package:edgecube_api_client/src/model/backup_target.dart';
import 'package:edgecube_api_client/src/model/backup_target_type.dart';
import 'package:edgecube_api_client/src/model/change_password_request.dart';
import 'package:edgecube_api_client/src/model/change_username_request.dart';
import 'package:edgecube_api_client/src/model/clear_finished_mod_downloads200_response.dart';
import 'package:edgecube_api_client/src/model/command_request.dart';
import 'package:edgecube_api_client/src/model/config_entry.dart';
import 'package:edgecube_api_client/src/model/device_info.dart';
import 'package:edgecube_api_client/src/model/device_type.dart';
import 'package:edgecube_api_client/src/model/encoding.dart';
import 'package:edgecube_api_client/src/model/error_response.dart';
import 'package:edgecube_api_client/src/model/export_request.dart';
import 'package:edgecube_api_client/src/model/file_entry.dart';
import 'package:edgecube_api_client/src/model/file_list_response.dart';
import 'package:edgecube_api_client/src/model/frp_status.dart';
import 'package:edgecube_api_client/src/model/fs_compress_request.dart';
import 'package:edgecube_api_client/src/model/fs_move_request.dart';
import 'package:edgecube_api_client/src/model/fs_path_request.dart';
import 'package:edgecube_api_client/src/model/fs_write_request.dart';
import 'package:edgecube_api_client/src/model/ftp_config.dart';
import 'package:edgecube_api_client/src/model/ftp_status.dart';
import 'package:edgecube_api_client/src/model/health_response.dart';
import 'package:edgecube_api_client/src/model/health_response_instances.dart';
import 'package:edgecube_api_client/src/model/import_request.dart';
import 'package:edgecube_api_client/src/model/instance_config.dart';
import 'package:edgecube_api_client/src/model/instance_config_terminal.dart';
import 'package:edgecube_api_client/src/model/instance_detail.dart';
import 'package:edgecube_api_client/src/model/instance_overview.dart';
import 'package:edgecube_api_client/src/model/instance_page.dart';
import 'package:edgecube_api_client/src/model/instance_status.dart';
import 'package:edgecube_api_client/src/model/instance_summary.dart';
import 'package:edgecube_api_client/src/model/instance_type.dart';
import 'package:edgecube_api_client/src/model/job_accepted.dart';
import 'package:edgecube_api_client/src/model/local_login_challenge.dart';
import 'package:edgecube_api_client/src/model/local_login_request.dart';
import 'package:edgecube_api_client/src/model/log_line.dart';
import 'package:edgecube_api_client/src/model/log_response.dart';
import 'package:edgecube_api_client/src/model/login_request.dart';
import 'package:edgecube_api_client/src/model/login_response.dart';
import 'package:edgecube_api_client/src/model/mod_download_request.dart';
import 'package:edgecube_api_client/src/model/mod_loader.dart';
import 'package:edgecube_api_client/src/model/mod_metadata.dart';
import 'package:edgecube_api_client/src/model/mod_metadata_entry.dart';
import 'package:edgecube_api_client/src/model/mod_metadata_list_response.dart';
import 'package:edgecube_api_client/src/model/modrinth_dependency.dart';
import 'package:edgecube_api_client/src/model/modrinth_file_hashes.dart';
import 'package:edgecube_api_client/src/model/modrinth_project.dart';
import 'package:edgecube_api_client/src/model/modrinth_search_hit.dart';
import 'package:edgecube_api_client/src/model/modrinth_search_response.dart';
import 'package:edgecube_api_client/src/model/modrinth_version.dart';
import 'package:edgecube_api_client/src/model/modrinth_version_file.dart';
import 'package:edgecube_api_client/src/model/modrinth_version_files_request.dart';
import 'package:edgecube_api_client/src/model/mods_analyze_request.dart';
import 'package:edgecube_api_client/src/model/monitor_snapshot.dart';
import 'package:edgecube_api_client/src/model/monitor_snapshot_disks_inner.dart';
import 'package:edgecube_api_client/src/model/player_ban_entry.dart';
import 'package:edgecube_api_client/src/model/player_ip_ban_entry.dart';
import 'package:edgecube_api_client/src/model/player_named_entry.dart';
import 'package:edgecube_api_client/src/model/player_snapshot.dart';
import 'package:edgecube_api_client/src/model/poggit_plugin.dart';
import 'package:edgecube_api_client/src/model/proxy_type.dart';
import 'package:edgecube_api_client/src/model/rename_device_request.dart';
import 'package:edgecube_api_client/src/model/run_status.dart';
import 'package:edgecube_api_client/src/model/runtime_catalog.dart';
import 'package:edgecube_api_client/src/model/runtime_catalog_entry.dart';
import 'package:edgecube_api_client/src/model/runtime_info.dart';
import 'package:edgecube_api_client/src/model/runtime_install_request.dart';
import 'package:edgecube_api_client/src/model/runtime_type.dart';
import 'package:edgecube_api_client/src/model/server_core_update_check.dart';
import 'package:edgecube_api_client/src/model/server_core_update_request.dart';
import 'package:edgecube_api_client/src/model/server_download_info.dart';
import 'package:edgecube_api_client/src/model/server_type_info.dart';
import 'package:edgecube_api_client/src/model/server_version.dart';
import 'package:edgecube_api_client/src/model/ssh_config.dart';
import 'package:edgecube_api_client/src/model/ssh_status.dart';
import 'package:edgecube_api_client/src/model/start_frpc_request.dart';
import 'package:edgecube_api_client/src/model/task.dart';
import 'package:edgecube_api_client/src/model/task_error.dart';
import 'package:edgecube_api_client/src/model/task_kind.dart';
import 'package:edgecube_api_client/src/model/task_list.dart';
import 'package:edgecube_api_client/src/model/task_progress.dart';
import 'package:edgecube_api_client/src/model/task_status.dart';
import 'package:edgecube_api_client/src/model/tunnel_info.dart';
import 'package:edgecube_api_client/src/model/tunnel_input.dart';
import 'package:edgecube_api_client/src/model/tunnel_proxy.dart';
import 'package:edgecube_api_client/src/model/upload_complete_request.dart';
import 'package:edgecube_api_client/src/model/upload_complete_response.dart';
import 'package:edgecube_api_client/src/model/upload_init_request.dart';
import 'package:edgecube_api_client/src/model/upload_progress.dart';
import 'package:edgecube_api_client/src/model/upload_session.dart';

part 'serializers.g.dart';

@SerializersFor([
  BackupJob,
  BackupTarget,
  BackupTargetType,
  ChangePasswordRequest,
  ChangeUsernameRequest,
  ClearFinishedModDownloads200Response,
  CommandRequest,
  ConfigEntry,
  DeviceInfo,
  DeviceType,
  Encoding,
  ErrorResponse,
  ExportRequest,
  FileEntry,
  FileListResponse,
  FrpStatus,
  FsCompressRequest,
  FsMoveRequest,
  FsPathRequest,
  FsWriteRequest,
  FtpConfig,$FtpConfig,
  FtpStatus,
  HealthResponse,
  HealthResponseInstances,
  ImportRequest,
  InstanceConfig,
  InstanceConfigTerminal,
  InstanceDetail,
  InstanceOverview,
  InstancePage,
  InstanceStatus,
  InstanceSummary,
  InstanceType,
  JobAccepted,
  LocalLoginChallenge,
  LocalLoginRequest,
  LogLine,
  LogResponse,
  LoginRequest,
  LoginResponse,
  ModDownloadRequest,
  ModLoader,
  ModMetadata,
  ModMetadataEntry,
  ModMetadataListResponse,
  ModrinthDependency,
  ModrinthFileHashes,
  ModrinthProject,
  ModrinthSearchHit,
  ModrinthSearchResponse,
  ModrinthVersion,
  ModrinthVersionFile,
  ModrinthVersionFilesRequest,
  ModsAnalyzeRequest,
  MonitorSnapshot,
  MonitorSnapshotDisksInner,
  PlayerBanEntry,
  PlayerIpBanEntry,
  PlayerNamedEntry,
  PlayerSnapshot,
  PoggitPlugin,
  ProxyType,
  RenameDeviceRequest,
  RunStatus,
  RuntimeCatalog,
  RuntimeCatalogEntry,
  RuntimeInfo,
  RuntimeInstallRequest,
  RuntimeType,
  ServerCoreUpdateCheck,
  ServerCoreUpdateRequest,
  ServerDownloadInfo,
  ServerTypeInfo,
  ServerVersion,
  SshConfig,$SshConfig,
  SshStatus,
  StartFrpcRequest,
  Task,
  TaskError,
  TaskKind,
  TaskList,
  TaskProgress,
  TaskStatus,
  TunnelInfo,
  TunnelInput,
  TunnelProxy,
  UploadCompleteRequest,
  UploadCompleteResponse,
  UploadInitRequest,
  UploadProgress,
  UploadSession,
])
Serializers serializers = (_$serializers.toBuilder()
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(RuntimeInfo)]),
        () => ListBuilder<RuntimeInfo>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltMap, [FullType(String), FullType(String)]),
        () => MapBuilder<String, String>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(LogLine)]),
        () => ListBuilder<LogLine>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(PlayerNamedEntry)]),
        () => ListBuilder<PlayerNamedEntry>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltMap, [FullType(String), FullType(ModrinthVersion)]),
        () => MapBuilder<String, ModrinthVersion>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(DeviceInfo)]),
        () => ListBuilder<DeviceInfo>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(FileEntry)]),
        () => ListBuilder<FileEntry>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(ModrinthDependency)]),
        () => ListBuilder<ModrinthDependency>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(PlayerIpBanEntry)]),
        () => ListBuilder<PlayerIpBanEntry>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(PoggitPlugin)]),
        () => ListBuilder<PoggitPlugin>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(BackupTarget)]),
        () => ListBuilder<BackupTarget>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(TunnelInfo)]),
        () => ListBuilder<TunnelInfo>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(ModrinthProject)]),
        () => ListBuilder<ModrinthProject>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(Task)]),
        () => ListBuilder<Task>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(TunnelProxy)]),
        () => ListBuilder<TunnelProxy>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(BackupJob)]),
        () => ListBuilder<BackupJob>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(ModMetadataEntry)]),
        () => ListBuilder<ModMetadataEntry>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(MonitorSnapshotDisksInner)]),
        () => ListBuilder<MonitorSnapshotDisksInner>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(RuntimeCatalogEntry)]),
        () => ListBuilder<RuntimeCatalogEntry>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(PlayerBanEntry)]),
        () => ListBuilder<PlayerBanEntry>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(ServerTypeInfo)]),
        () => ListBuilder<ServerTypeInfo>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(InstanceSummary)]),
        () => ListBuilder<InstanceSummary>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltMap, [FullType(String), FullType.nullable(JsonObject)]),
        () => MapBuilder<String, JsonObject?>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(ModrinthVersionFile)]),
        () => ListBuilder<ModrinthVersionFile>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(String)]),
        () => ListBuilder<String>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(ServerVersion)]),
        () => ListBuilder<ServerVersion>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(ModrinthSearchHit)]),
        () => ListBuilder<ModrinthSearchHit>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(ModrinthVersion)]),
        () => ListBuilder<ModrinthVersion>(),
      )
      ..add(FtpConfig.serializer)
      ..add(SshConfig.serializer)
      ..add(const OneOfSerializer())
      ..add(const AnyOfSerializer())
      ..add(const DateSerializer())
      ..add(Iso8601DateTimeSerializer())
    ).build();

Serializers standardSerializers =
    (serializers.toBuilder()..addPlugin(StandardJsonPlugin())).build();
