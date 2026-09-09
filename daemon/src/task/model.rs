//! 任务模型(对齐 openapi.yaml §Task*)。

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// 任务状态机(契约 TaskStatus)。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TaskStatus {
    Queued,
    Running,
    Succeeded,
    Failed,
    Cancelled,
}

impl TaskStatus {
    /// 是否已终结(不再变化)。
    pub fn is_terminal(self) -> bool {
        matches!(
            self,
            TaskStatus::Succeeded | TaskStatus::Failed | TaskStatus::Cancelled
        )
    }

    /// 是否仍在受理中(可取消)。
    pub fn is_active(self) -> bool {
        matches!(self, TaskStatus::Queued | TaskStatus::Running)
    }
}

/// 任务类型(契约 TaskKind)。
///
/// 实例操作(start/stop/restart/kill)与归档操作(compress/extract)按
/// instanceId 分组 FIFO 串行,同一实例同 kind 未结束的任务重复提交将被拒绝
/// (task_conflict)。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TaskKind {
    Start,
    Stop,
    Restart,
    Kill,
    Download,
    Export,
    /// 从导出归档还原为新实例(archivePath 位于某实例 cwd 内;kind 挂到目标实例)。
    Import,
    Backup,
    Compress,
    Extract,
    /// 服务端核心更新(下载新 jar 替换旧 jar,校验 sha256)。
    CoreUpdate,
    /// 插件/模组元数据解析(实例目录扫描,后端解析后前端拉取结果)。
    Analyze,
    /// 通用单文件下载(绑定一个 aria2 下载任务 ID)。
    ///
    /// 与其它 kind 不同:同一实例允许同时排队多个(download_single_file 任务
    /// 按 instanceId 分组 FIFO 串行执行,一个完成再下一个,等价 V1 下载队列)。
    DownloadSingleFile,
}

/// 进度快照(契约 TaskProgress)。
#[derive(Debug, Clone, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TaskProgress {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub received_bytes: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub total_bytes: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub speed_bytes_per_sec: Option<u64>,
    /// 预计还需时间(秒,= (total - received) / speed;速度未知或为 0 时为 null)。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub eta_seconds: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub percent: Option<f32>,
}

impl TaskProgress {
    pub fn received(total: u64, received: u64) -> Self {
        TaskProgress {
            received_bytes: Some(received),
            total_bytes: Some(total),
            percent: Some(received as f32 / total.max(1) as f32),
            speed_bytes_per_sec: None,
            eta_seconds: None,
        }
    }
}

/// 任务失败原因(契约 Task.error)。
#[derive(Debug, Clone, Serialize)]
pub struct TaskError {
    pub code: String,
    pub message: String,
}

impl TaskError {
    pub fn new(code: &str, message: impl Into<String>) -> Self {
        TaskError {
            code: code.into(),
            message: message.into(),
        }
    }
}

/// 任务实体(契约 Task)。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Task {
    pub id: Uuid,
    pub kind: TaskKind,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub instance_id: Option<Uuid>,
    /// 用户可读的展示标题(如 "模组名 v1.2");无时为 null。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub display_name: Option<String>,
    pub status: TaskStatus,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub phase: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub progress: Option<TaskProgress>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<TaskError>,
    pub created_at: DateTime<Utc>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub started_at: Option<DateTime<Utc>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub finished_at: Option<DateTime<Utc>>,
}

/// 任务列表(契约 TaskList)。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TaskList {
    pub items: Vec<Task>,
    pub total: u64,
}

/// WS `task/progress` 帧负载(ws.md §4.3)。
#[derive(Debug, Clone)]
pub struct TaskEvent {
    pub task_id: Uuid,
    pub kind: TaskKind,
    pub instance_id: Option<Uuid>,
    pub display_name: Option<String>,
    pub status: TaskStatus,
    pub phase: Option<String>,
    pub progress: Option<TaskProgress>,
    pub error: Option<TaskError>,
}

impl From<&Task> for TaskEvent {
    fn from(t: &Task) -> Self {
        TaskEvent {
            task_id: t.id,
            kind: t.kind,
            instance_id: t.instance_id,
            display_name: t.display_name.clone(),
            status: t.status,
            phase: t.phase.clone(),
            progress: t.progress.clone(),
            error: t.error.clone(),
        }
    }
}

/// 执行体失败原因(提交方返回,映射为 Task.error)。
#[derive(Debug, Clone)]
pub struct TaskFailure {
    pub code: String,
    pub message: String,
}

impl TaskFailure {
    pub fn new(code: &str, message: impl Into<String>) -> Self {
        TaskFailure {
            code: code.into(),
            message: message.into(),
        }
    }
}