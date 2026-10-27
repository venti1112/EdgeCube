//! task 模块的模型：模块配置、内部任务记录、线上（WS/HTTP）形状。
//!
//! 线上命名一律 snake_case（项目全局约定）。任务对象对齐 download 模块的
//! 「快照 + 事件带完整对象」模式：`task.get` / `task.list` / `task.state` /
//! `task.progress` 四处的载荷是同一个形状，前端一套模型通吃。

use serde::Deserialize;
use serde_json::{Value, json};
use tokio_util::sync::CancellationToken;

use crate::util::now_ms;

/// [modules.config.task]
#[derive(Debug, Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct TaskConfig {
    /// 同时执行的任务数上限，超出的排队（queued）。
    /// clamp 到 [1, 64]——任务是用户显式操作，排队比报 busy 友好；
    /// 但也不能无上限，任务各自持有 Engine 与后台执行流。
    pub max_concurrent_tasks: u64,
    /// 已结束任务保留条数，超过就删最老的（在跑的不受影响）。
    /// clamp 到 [10, 1000]。
    pub history_limit: u64,
}

impl TaskConfig {
    pub fn clamped_max_concurrent(&self) -> usize {
        self.max_concurrent_tasks.clamp(1, 64) as usize
    }

    pub fn clamped_history_limit(&self) -> usize {
        self.history_limit.clamp(10, 1000) as usize
    }
}

/// 任务状态（线上取值）。
///
/// szal 的 `WorkflowState` 更细（Paused / RollingBack / RolledBack），但那些
/// 是引擎内部的过程态——回滚对我们只是一个 `rolled_back` 布尔位，暂停这轮
/// 没有入口。线上状态保持最小集合，前端好画。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TaskState {
    Queued,
    Running,
    Completed,
    Failed,
    Cancelled,
}

impl TaskState {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Queued => "queued",
            Self::Running => "running",
            Self::Completed => "completed",
            Self::Failed => "failed",
            Self::Cancelled => "cancelled",
        }
    }

    pub fn is_terminal(&self) -> bool {
        matches!(self, Self::Completed | Self::Failed | Self::Cancelled)
    }
}

/// 单个步骤的记账（内部）。线上形状由 [`step_view`] 给出。
#[derive(Debug, Clone)]
pub struct StepState {
    /// szal 的步骤 id（Uuid 字符串）。引擎的事件只带这个，按它定位步骤。
    pub step_id: String,
    pub name: String,
    /// 展示标题（注册步骤时给的）。
    pub title: String,
    pub step_type: String,
    pub status: StepStatus,
    /// 最近一次 `ProgressReporter.report` 的数据（如下载百分比），
    /// 步骤实现自己控制上报频率。
    pub progress: Option<Value>,
    /// 步骤成功的 output（终态后才有；失败为 `None`）。
    pub output: Option<Value>,
    pub error: Option<String>,
    pub attempts: u32,
    pub duration_ms: u64,
}

/// 步骤状态（线上取值）。与 szal 的 `StepStatus` 一一对应，多一个
/// `rolled_back`——引擎回滚时步骤本身仍是 Completed，回滚是叠加事实。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StepStatus {
    Pending,
    Running,
    Completed,
    Failed,
    Skipped,
    RolledBack,
}

impl StepStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::Running => "running",
            Self::Completed => "completed",
            Self::Failed => "failed",
            Self::Skipped => "skipped",
            Self::RolledBack => "rolled_back",
        }
    }
}

/// 一条任务的记账（内部）。
pub struct TaskRecord {
    pub id: String,
    /// 工作流模板名（如 `instance-provision`）。
    pub flow: String,
    pub title: String,
    /// 调用方给的原始参数，原样回显。
    pub params: Value,
    pub state: TaskState,
    /// 正在执行的步骤名（running 时有值）。
    pub current_step: Option<String>,
    pub steps: Vec<StepState>,
    /// 失败信息：`{"step": 步骤名, "message": 原因}`。
    pub error: Option<Value>,
    /// 失败后是否把已完成步骤回滚干净了。
    pub rolled_back: bool,
    pub created_at_ms: u64,
    pub started_at_ms: Option<u64>,
    pub finished_at_ms: Option<u64>,
    pub total_duration_ms: Option<u64>,
    /// 取消令牌。`task.cancel` 与模块 `stop()` 都从这里取消。
    pub token: CancellationToken,
}

impl TaskRecord {
    /// 按模板的步骤声明初始化（全部 pending）。
    pub fn new(
        id: String,
        flow: String,
        title: String,
        params: Value,
        steps: Vec<StepState>,
    ) -> Self {
        Self {
            id,
            flow,
            title,
            params,
            state: TaskState::Queued,
            current_step: None,
            steps,
            error: None,
            rolled_back: false,
            created_at_ms: now_ms(),
            started_at_ms: None,
            finished_at_ms: None,
            total_duration_ms: None,
            token: CancellationToken::new(),
        }
    }
}

/// 步骤的线上形状。
fn step_view(step: &StepState) -> Value {
    json!({
        "id": step.step_id,
        "name": step.name,
        "title": step.title,
        "step_type": step.step_type,
        "status": step.status.as_str(),
        "progress": step.progress,
        "output": step.output,
        "error": step.error,
        "attempts": step.attempts,
        "duration_ms": step.duration_ms,
    })
}

/// 任务的线上形状。快照接口（`task.get` / `task.list`）与事件
/// （`task.state` / `task.progress`）共用。
pub fn task_view(record: &TaskRecord) -> Value {
    json!({
        "id": record.id,
        "flow": record.flow,
        "title": record.title,
        "params": record.params,
        "state": record.state.as_str(),
        "current_step": record.current_step,
        "steps": record.steps.iter().map(step_view).collect::<Vec<_>>(),
        "error": record.error,
        "rolled_back": record.rolled_back,
        "created_at_ms": record.created_at_ms,
        "started_at_ms": record.started_at_ms,
        "finished_at_ms": record.finished_at_ms,
        "total_duration_ms": record.total_duration_ms,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_record() -> TaskRecord {
        let steps = vec![StepState {
            step_id: "00000000-0000-0000-0000-000000000001".into(),
            name: "create".into(),
            title: "创建实例".into(),
            step_type: "instance.create".into(),
            status: StepStatus::Completed,
            progress: Some(json!({"percent": 100})),
            output: Some(json!({"instance_id": "abc123"})),
            error: None,
            attempts: 1,
            duration_ms: 42,
        }];
        TaskRecord::new(
            "3f2b1c4d-0000-0000-0000-000000000000".into(),
            "instance-provision".into(),
            "创建实例并下载服务端".into(),
            json!({"name": "测试服"}),
            steps,
        )
    }

    /// 线上形状是前端契约，用测试钉住：字段名全 snake_case、
    /// 步骤对象带 progress/output、任务对象带 current_step/rolled_back。
    #[test]
    fn task_view_wire_shape() {
        let view = task_view(&sample_record());
        assert_eq!(view["state"], json!("queued"));
        assert_eq!(view["flow"], json!("instance-provision"));
        assert_eq!(view["steps"][0]["step_type"], json!("instance.create"));
        assert_eq!(view["steps"][0]["progress"]["percent"], json!(100));
        assert_eq!(view["steps"][0]["output"]["instance_id"], json!("abc123"));
        assert_eq!(view["current_step"], json!(null));
        assert_eq!(view["rolled_back"], json!(false));
        // 时间戳字段缺省是 null 而不是缺席，前端不用判 hasOwnProperty
        assert_eq!(view["started_at_ms"], json!(null));
        assert_eq!(view["finished_at_ms"], json!(null));
    }

    #[test]
    fn config_clamps() {
        let cfg = TaskConfig {
            max_concurrent_tasks: 0,
            history_limit: 99999,
        };
        assert_eq!(cfg.clamped_max_concurrent(), 1);
        assert_eq!(cfg.clamped_history_limit(), 1000);
        let defaults = TaskConfig::default();
        assert_eq!(defaults.clamped_max_concurrent(), 1);
    }
}
