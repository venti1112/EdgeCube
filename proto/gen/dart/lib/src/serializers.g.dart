// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'serializers.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializers _$serializers = (Serializers().toBuilder()
      ..add($FtpConfig.serializer)
      ..add($SshConfig.serializer)
      ..add(BackupJob.serializer)
      ..add(BackupJobLastResultEnum.serializer)
      ..add(BackupTarget.serializer)
      ..add(BackupTargetType.serializer)
      ..add(ChangePasswordRequest.serializer)
      ..add(ChangeUsernameRequest.serializer)
      ..add(ClearFinishedModDownloads200Response.serializer)
      ..add(CommandRequest.serializer)
      ..add(ConfigEntry.serializer)
      ..add(DeviceInfo.serializer)
      ..add(DeviceType.serializer)
      ..add(Encoding.serializer)
      ..add(ErrorResponse.serializer)
      ..add(ExportRequest.serializer)
      ..add(ExportRequestFormatEnum.serializer)
      ..add(FileEntry.serializer)
      ..add(FileListResponse.serializer)
      ..add(FrpStatus.serializer)
      ..add(FsCompressRequest.serializer)
      ..add(FsMoveRequest.serializer)
      ..add(FsPathRequest.serializer)
      ..add(FsWriteRequest.serializer)
      ..add(FtpStatus.serializer)
      ..add(HealthResponse.serializer)
      ..add(HealthResponseDaemonEnum.serializer)
      ..add(HealthResponseInstances.serializer)
      ..add(HealthResponseStatusEnum.serializer)
      ..add(ImportRequest.serializer)
      ..add(InstanceConfig.serializer)
      ..add(InstanceConfigTerminal.serializer)
      ..add(InstanceDetail.serializer)
      ..add(InstanceOverview.serializer)
      ..add(InstancePage.serializer)
      ..add(InstanceStatus.serializer)
      ..add(InstanceSummary.serializer)
      ..add(InstanceType.serializer)
      ..add(JobAccepted.serializer)
      ..add(LocalLoginChallenge.serializer)
      ..add(LocalLoginRequest.serializer)
      ..add(LogLine.serializer)
      ..add(LogResponse.serializer)
      ..add(LoginRequest.serializer)
      ..add(LoginResponse.serializer)
      ..add(ModDownloadRequest.serializer)
      ..add(ModLoader.serializer)
      ..add(ModMetadata.serializer)
      ..add(ModMetadataEntry.serializer)
      ..add(ModMetadataListResponse.serializer)
      ..add(ModrinthDependency.serializer)
      ..add(ModrinthFileHashes.serializer)
      ..add(ModrinthProject.serializer)
      ..add(ModrinthSearchHit.serializer)
      ..add(ModrinthSearchResponse.serializer)
      ..add(ModrinthVersion.serializer)
      ..add(ModrinthVersionFile.serializer)
      ..add(ModrinthVersionFilesRequest.serializer)
      ..add(ModsAnalyzeRequest.serializer)
      ..add(MonitorSnapshot.serializer)
      ..add(MonitorSnapshotDisksInner.serializer)
      ..add(PlayerBanEntry.serializer)
      ..add(PlayerIpBanEntry.serializer)
      ..add(PlayerNamedEntry.serializer)
      ..add(PlayerSnapshot.serializer)
      ..add(PoggitPlugin.serializer)
      ..add(ProxyType.serializer)
      ..add(RenameDeviceRequest.serializer)
      ..add(RunStatus.serializer)
      ..add(RuntimeCatalog.serializer)
      ..add(RuntimeCatalogEntry.serializer)
      ..add(RuntimeInfo.serializer)
      ..add(RuntimeInstallRequest.serializer)
      ..add(RuntimeType.serializer)
      ..add(ServerCoreUpdateCheck.serializer)
      ..add(ServerCoreUpdateCheckSource_Enum.serializer)
      ..add(ServerCoreUpdateRequest.serializer)
      ..add(ServerDownloadInfo.serializer)
      ..add(ServerTypeInfo.serializer)
      ..add(ServerTypeInfoCategoryEnum.serializer)
      ..add(ServerVersion.serializer)
      ..add(SshStatus.serializer)
      ..add(StartFrpcRequest.serializer)
      ..add(Task.serializer)
      ..add(TaskError.serializer)
      ..add(TaskKind.serializer)
      ..add(TaskList.serializer)
      ..add(TaskProgress.serializer)
      ..add(TaskStatus.serializer)
      ..add(TunnelInfo.serializer)
      ..add(TunnelInput.serializer)
      ..add(TunnelProxy.serializer)
      ..add(UploadCompleteRequest.serializer)
      ..add(UploadCompleteResponse.serializer)
      ..add(UploadInitRequest.serializer)
      ..add(UploadProgress.serializer)
      ..add(UploadSession.serializer)
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(FileEntry)]),
          () => ListBuilder<FileEntry>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(InstanceSummary)]),
          () => ListBuilder<InstanceSummary>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(InstanceSummary)]),
          () => ListBuilder<InstanceSummary>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(LogLine)]),
          () => ListBuilder<LogLine>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(ModMetadataEntry)]),
          () => ListBuilder<ModMetadataEntry>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(ModrinthSearchHit)]),
          () => ListBuilder<ModrinthSearchHit>())
      ..addBuilderFactory(
          const FullType(
              BuiltList, const [const FullType(MonitorSnapshotDisksInner)]),
          () => ListBuilder<MonitorSnapshotDisksInner>())
      ..addBuilderFactory(
          const FullType(
              BuiltList, const [const FullType(RuntimeCatalogEntry)]),
          () => ListBuilder<RuntimeCatalogEntry>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(String)]),
          () => ListBuilder<String>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(String)]),
          () => ListBuilder<String>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(String)]),
          () => ListBuilder<String>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(String)]),
          () => ListBuilder<String>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(PlayerNamedEntry)]),
          () => ListBuilder<PlayerNamedEntry>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(PlayerNamedEntry)]),
          () => ListBuilder<PlayerNamedEntry>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(PlayerBanEntry)]),
          () => ListBuilder<PlayerBanEntry>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(PlayerIpBanEntry)]),
          () => ListBuilder<PlayerIpBanEntry>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(String)]),
          () => ListBuilder<String>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(String)]),
          () => ListBuilder<String>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(String)]),
          () => ListBuilder<String>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(String)]),
          () => ListBuilder<String>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(String)]),
          () => ListBuilder<String>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(String)]),
          () => ListBuilder<String>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(String)]),
          () => ListBuilder<String>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(String)]),
          () => ListBuilder<String>())
      ..addBuilderFactory(
          const FullType(
              BuiltList, const [const FullType(ModrinthVersionFile)]),
          () => ListBuilder<ModrinthVersionFile>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(ModrinthDependency)]),
          () => ListBuilder<ModrinthDependency>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(Task)]),
          () => ListBuilder<Task>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(TunnelProxy)]),
          () => ListBuilder<TunnelProxy>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(TunnelProxy)]),
          () => ListBuilder<TunnelProxy>())
      ..addBuilderFactory(
          const FullType(
              BuiltMap, const [const FullType(String), const FullType(String)]),
          () => MapBuilder<String, String>())
      ..addBuilderFactory(
          const FullType(BuiltMap, const [
            const FullType(String),
            const FullType.nullable(JsonObject)
          ]),
          () => MapBuilder<String, JsonObject?>())
      ..addBuilderFactory(
          const FullType(BuiltMap, const [
            const FullType(String),
            const FullType.nullable(JsonObject)
          ]),
          () => MapBuilder<String, JsonObject?>())
      ..addBuilderFactory(
          const FullType(BuiltMap, const [
            const FullType(String),
            const FullType.nullable(JsonObject)
          ]),
          () => MapBuilder<String, JsonObject?>()))
    .build();

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
