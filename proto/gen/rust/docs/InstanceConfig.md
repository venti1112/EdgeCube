# InstanceConfig

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | Option<**uuid::Uuid**> | 服务端生成 | [optional][readonly]
**name** | **String** |  | 
**start_command** | **String** | 命令行字符串(支持引号/转义,解析为参数数组 spawn,不经 shell) | 
**stop_command** | Option<**String**> | 优雅停止命令;^C 表示发送 Ctrl+C | [optional][default to ^C]
**stop_timeout_seconds** | Option<**i32**> | 优雅停止超时,超时升级强杀 | [optional][default to 600]
**working_directory** | **String** | 工作目录(实例 cwd,文件沙箱根) | 
**environment** | Option<**std::collections::HashMap<String, String>**> | 额外环境变量 | [optional]
**input_encoding** | Option<[**models::Encoding**](Encoding.md)> |  | [optional]
**output_encoding** | Option<[**models::Encoding**](Encoding.md)> |  | [optional]
**auto_restart** | Option<**bool**> | 异常/正常退出后自动重启 | [optional][default to false]
**auto_restart_max_times** | Option<**i32**> | 重启次数上限;-1 无限 | [optional][default to -1]
**auto_start_on_boot** | Option<**bool**> | daemon 启动时自动拉起 | [optional][default to false]
**terminal** | Option<[**models::InstanceConfigTerminal**](InstanceConfigTerminal.md)> |  | [optional]
**r#type** | Option<[**models::InstanceType**](InstanceType.md)> |  | [optional]
**created_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional][readonly]
**updated_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional][readonly]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


