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
      ..add(CommandRequest.serializer)
      ..add(ConfigEntry.serializer)
      ..add(DeviceInfo.serializer)
      ..add(Encoding.serializer)
      ..add(ErrorResponse.serializer)
      ..add(ExportRequest.serializer)
      ..add(ExportRequestFormatEnum.serializer)
      ..add(FileEntry.serializer)
      ..add(FileListResponse.serializer)
      ..add(FsCompressRequest.serializer)
      ..add(FsMoveRequest.serializer)
      ..add(FsPathRequest.serializer)
      ..add(FtpStatus.serializer)
      ..add(HealthResponse.serializer)
      ..add(HealthResponseDaemonEnum.serializer)
      ..add(HealthResponseInstances.serializer)
      ..add(HealthResponseStatusEnum.serializer)
      ..add(InstanceConfig.serializer)
      ..add(InstanceConfigTerminal.serializer)
      ..add(InstanceDetail.serializer)
      ..add(InstanceOverview.serializer)
      ..add(InstancePage.serializer)
      ..add(InstanceStatus.serializer)
      ..add(InstanceSummary.serializer)
      ..add(InstanceType.serializer)
      ..add(JobAccepted.serializer)
      ..add(LogLine.serializer)
      ..add(LogResponse.serializer)
      ..add(MonitorSnapshot.serializer)
      ..add(MonitorSnapshotDisksInner.serializer)
      ..add(PairRequest.serializer)
      ..add(PairResponse.serializer)
      ..add(PairingCode.serializer)
      ..add(RunStatus.serializer)
      ..add(RuntimeCatalog.serializer)
      ..add(RuntimeCatalogEntry.serializer)
      ..add(RuntimeInfo.serializer)
      ..add(RuntimeInstallRequest.serializer)
      ..add(RuntimeType.serializer)
      ..add(SshStatus.serializer)
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
          () => MapBuilder<String, JsonObject?>()))
    .build();

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
