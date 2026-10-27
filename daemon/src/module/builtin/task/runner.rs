//! 任务执行器：把一份 [`FlowDef`] 跑起来，并全程记账、推事件。
//!
//! # 为什么每个任务一个 Engine
//!
//! szal 的进度事件（`StepProgress`）与生命周期事件（`WorkflowEvent`）都
//! **只带步骤级标识**，没有「哪次执行」的概念——多个任务共享一个 Engine
//! 时，事件分不清归属。所以这里每次提交都新建一个 Engine，把任务 id 用
//! 闭包捕获进 handler / progress sink / event sink，事件天然就带着归属。
//! Engine 本身只是配置加几个 `Arc`，按任务建的开销可以忽略。
//!
//! # 状态从哪来
//!
//! 步骤的**中间态**（running / skipped / rolled_back）靠 event sink 增量
//! 维护——失败后引擎还要跑回滚，那几秒的中间可见性有价值；**终态**以
//! `FlowResult` 为权威，结束时整体覆盖一遍（output / attempts /
//! duration_ms 这些事件里没有的字段也一起补齐）。
//!
//! # 取消
//!
//! szal 的取消只在**步骤之间**生效（正在执行的步骤会跑完）。等待类步骤
//! （比如「提交下载并等它结束」）要自己 `select!` 取消令牌。取消不会触发
//! 回滚——skipped 不算失败；用户主动放弃，已完成的部分留给他自己决定，
//! 这与「失败必须收拾干净」是两种不同的语义。

use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};

use serde_json::{Value, json};
use szal::bus::{EventType, WorkflowEvent};
use szal::engine::{Engine, EngineConfig, StepProgress, handler_fn_with_progress, rollback_fn};
use szal::flow::FlowDef;
use szal::step::StepStatus as SzalStatus;
use tokio::sync::Semaphore;
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

use super::flows::{FlowRegistry, StepEnv};
use super::model::{StepState, StepStatus, TaskConfig, TaskRecord, TaskState, task_view};
use crate::error::{RpcError, RpcResult};
use crate::state::AppState;
use crate::util::now_ms;

/// 事件主题（`task.state` / `task.progress`），载荷都是完整任务对象。
pub const TOPIC_STATE: &str = "task.state";
pub const TOPIC_PROGRESS: &str = "task.progress";

pub const CODE_FLOW_NOT_FOUND: &str = "task_flow_not_found";
pub const CODE_NOT_FOUND: &str = "task_not_found";
pub const CODE_INVALID_PARAMS: &str = "task_invalid_params";
pub const CODE_ENGINE_ERROR: &str = "task_engine_error";

/// 任务执行器（模块内一份）。
pub struct TaskRunner {
    app: AppState,
    cfg: TaskConfig,
    /// 工作流注册表。submit / 执行流的分发都用这一份，不查进程内全局——
    /// 单测直接 `TaskRunner::new(..., registry)` 注入即可，不必动 `SHARED`。
    flows: Arc<FlowRegistry>,
    /// 任务表：id → 记录。外层锁只护表结构；记录各自的更新走记录自己的锁，
    /// 事件 sink（同步闭包）与执行流（异步）不会互相顶住。
    tasks: Mutex<BTreeMap<String, Arc<Mutex<TaskRecord>>>>,
    /// 并发闸门。排队（queued）就是「还没拿到 permit」。
    semaphore: Arc<Semaphore>,
}

impl TaskRunner {
    pub fn new(app: AppState, cfg: TaskConfig, flows: Arc<FlowRegistry>) -> Self {
        let permits = cfg.clamped_max_concurrent();
        Self {
            app,
            cfg,
            flows,
            tasks: Mutex::new(BTreeMap::new()),
            semaphore: Arc::new(Semaphore::new(permits)),
        }
    }

    /// 提交一个任务：校验、记账、spawn 执行流。返回提交时刻的任务快照
    /// （通常已是 `running`，并发满时是 `queued`）。
    pub fn submit(self: &Arc<Self>, flow_name: &str, params: Value) -> RpcResult<Value> {
        let registry = self.flows.clone();
        let template = registry.flow(flow_name).ok_or_else(|| {
            RpcError::new(
                CODE_FLOW_NOT_FOUND,
                format!("工作流 `{flow_name}` 未注册（`task.flows` 可查清单）"),
            )
        })?;

        // 参数只接受对象（或 null 当空对象）。数组/标量当参数用八成是调用方
        // 拼错了，提前拦下比传进去让 build 莫名其妙地炸好。
        let params = match params {
            Value::Null => json!({}),
            Value::Object(map) => Value::Object(map),
            other => {
                return Err(RpcError::new(
                    CODE_INVALID_PARAMS,
                    format!("`params` 必须是对象，收到 {other}"),
                ));
            }
        };

        // build 与预检都在进队前完成：坏任务不该拿到 id。
        let flow_def = (template.build)(&params).map_err(|e| {
            RpcError::new(
                CODE_INVALID_PARAMS,
                format!("参数不被工作流 `{flow_name}` 接受: {e}"),
            )
        })?;
        flow_def
            .validate()
            .map_err(|e| RpcError::new(CODE_INVALID_PARAMS, format!("工作流定义不合法: {e}")))?;

        let mut steps = Vec::with_capacity(flow_def.steps.len());
        for step in &flow_def.steps {
            // 我们约定所有步骤都必须带 step_type（szal 允许 None），不带就
            // 没法分发到注册表。
            let step_type = step.step_type.clone().ok_or_else(|| {
                RpcError::new(
                    CODE_INVALID_PARAMS,
                    format!("工作流 `{flow_name}` 的步骤 `{}` 没写 step_type", step.name),
                )
            })?;
            let spec = registry.step(&step_type).ok_or_else(|| {
                RpcError::new(
                    CODE_INVALID_PARAMS,
                    format!("步骤类型 `{step_type}` 未注册（步骤 `{}`）", step.name),
                )
            })?;
            if step.rollbackable && spec.rollback.is_none() {
                return Err(RpcError::new(
                    CODE_INVALID_PARAMS,
                    format!(
                        "步骤 `{}` 标了可回滚，但 `{step_type}` 没注册回滚实现",
                        step.name
                    ),
                ));
            }
            steps.push(StepState {
                step_id: step.id.to_string(),
                name: step.name.clone(),
                title: spec.title.clone(),
                step_type,
                status: StepStatus::Pending,
                progress: None,
                output: None,
                error: None,
                attempts: 0,
                duration_ms: 0,
            });
        }

        let id = Uuid::new_v4().to_string();
        let token = CancellationToken::new();
        let record = TaskRecord {
            token: token.clone(),
            ..TaskRecord::new(
                id.clone(),
                flow_name.to_string(),
                template.title.clone(),
                params,
                steps,
            )
        };

        {
            let mut tasks = self.tasks.lock().unwrap_or_else(|e| e.into_inner());
            self.prune_history_locked(&mut tasks);
            tasks.insert(id.clone(), Arc::new(Mutex::new(record)));
        }
        self.publish_state(&id);

        // spawn 执行流：拿 permit → running → 跑引擎 → 终态。
        let runner = self.clone();
        tokio::spawn(runner.execute(id.clone(), flow_def, token));
        self.view(&id)
            .ok_or_else(|| RpcError::new(CODE_ENGINE_ERROR, "任务刚提交就找不到了"))
    }

    /// 单个任务的执行流（在独立 tokio 任务里跑）。
    async fn execute(self: Arc<Self>, id: String, flow_def: FlowDef, token: CancellationToken) {
        // 排队：并发额度满了就在这里等。等待期间被取消的话，拿到 permit
        // 后第一件事就是收尾。
        let _permit = match self.semaphore.clone().acquire_owned().await {
            Ok(permit) => permit,
            Err(_) => return, // semaphore 已关闭（只在 drop 时发生），无从收尾
        };

        {
            let Some(record) = self.task(&id) else { return };
            let mut rec = record.lock().unwrap_or_else(|e| e.into_inner());
            if token.is_cancelled() {
                rec.state = TaskState::Cancelled;
                rec.finished_at_ms = Some(now_ms());
                let view = task_view(&rec);
                drop(rec);
                let _ = self.app.bus.publish_from(Some("task"), TOPIC_STATE, view);
                return;
            }
            rec.state = TaskState::Running;
            rec.started_at_ms = Some(now_ms());
        }
        self.publish_state(&id);

        // 步骤间共享的产出表：成功的 output 由下面的分发层写进来。
        let env = StepEnv {
            task_id: id.clone(),
            app: self.app.clone(),
            outputs: Arc::new(tokio::sync::RwLock::new(serde_json::Map::new())),
            cancel: token.clone(),
            scratch: Arc::new(std::sync::Mutex::new(std::collections::HashMap::new())),
        };

        // 注意：`env`（连同 scratch）在整个执行流里活着 —— 引擎与它持有的步骤
        // 闭包都握着它的一份 clone，下面 `run_with_cancellation` 返回、`engine`
        // 析构之后引用才归零。于是步骤放进 scratch 的 RAII guard 会在**这个任务
        // 真正结束时**才 drop（含取消、失败），不需要额外的收尾钩子。
        let engine = self.build_engine(&id, env);
        let result = engine.run_with_cancellation(&flow_def, token.clone()).await;
        self.finalize(&id, result, token);
    }

    /// 每任务一个 Engine（理由见模块注释）。handler / 回滚按 `step_type`
    /// 分发到注册表；成功的 output 顺手写进共享产出表。
    ///
    /// 接收者是 `&Arc<Self>`：两个 sink 闭包都要捕获执行器的强引用
    /// （`'static`），`&self` 拿不出 `Arc`。
    fn build_engine(self: &Arc<Self>, id: &str, env: StepEnv) -> Engine {
        let registry = self.flows.clone();

        // 进度 sink：更新步骤的 progress 字段 + 推 `task.progress`。
        // 上报频率由步骤实现自己控制（下载步骤按扫描间隔、约 500ms 一帧）。
        let runner = self.clone();
        let progress_sink: Arc<dyn Fn(StepProgress) + Send + Sync> = {
            let id = id.to_string();
            Arc::new(move |p: StepProgress| {
                if let Some(record) = runner.task(&id) {
                    let mut rec = record.lock().unwrap_or_else(|e| e.into_inner());
                    if let Some(step) = rec.steps.iter_mut().find(|s| s.step_id == p.step_id) {
                        step.progress = Some(p.data);
                    }
                    let view = task_view(&rec);
                    drop(rec);
                    let _ = runner
                        .app
                        .bus
                        .publish_from(Some("task"), TOPIC_PROGRESS, view);
                }
            })
        };

        // 步骤分发：查注册表 → 执行 → output 入共享表。
        let dispatch_registry = registry.clone();
        let dispatch_env = env.clone();
        let handler = handler_fn_with_progress(
            progress_sink.clone(),
            move |step: szal::step::StepDef, progress| {
                let registry = dispatch_registry.clone();
                let env = dispatch_env.clone();
                async move {
                    let step_type = step.step_type.clone().unwrap_or_default();
                    let Some(spec) = registry.step(&step_type) else {
                        return Err(format!("未注册的步骤类型 `{step_type}`"));
                    };
                    let name = step.name.clone();
                    let output = (spec.run)(step, progress, env.clone()).await?;
                    env.outputs.write().await.insert(name, output.clone());
                    Ok(output)
                }
            },
        );

        // 回滚分发：同样按 step_type 查表。
        let rollback_registry = registry.clone();
        let rollback_env = env.clone();
        let rollback = rollback_fn(move |step: szal::step::StepDef| {
            let registry = rollback_registry.clone();
            let env = rollback_env.clone();
            async move {
                let step_type = step.step_type.clone().unwrap_or_default();
                let Some(spec) = registry.step(&step_type) else {
                    return Err(format!("未注册的步骤类型 `{step_type}`"));
                };
                let Some(rollback) = spec.rollback else {
                    return Err(format!(
                        "步骤 `{}` 标了可回滚，但 `{step_type}` 没注册回滚实现",
                        step.name
                    ));
                };
                (rollback)(step, env).await
            }
        });

        // 生命周期事件 sink：维护步骤中间态 + 推 `task.state`。
        // Flow* 级事件不处理——flow 的状态由我们自己记账。
        let event_runner = self.clone();
        let event_id = id.to_string();
        let event_sink: Arc<dyn Fn(WorkflowEvent) + Send + Sync> = Arc::new(move |ev| {
            handle_workflow_event(&event_runner, &event_id, &ev);
        });

        Engine::new(
            EngineConfig {
                progress_sink: Some(progress_sink),
                ..EngineConfig::default()
            },
            handler,
        )
        .with_rollback_handler(rollback)
        .with_event_sink(event_sink)
    }

    /// 终态落账：`FlowResult` 是权威，整体覆盖步骤；rolled_back 标志位与
    /// 事件维护的步骤态合并。
    fn finalize(
        &self,
        id: &str,
        result: szal::Result<szal::engine::FlowResult>,
        token: CancellationToken,
    ) {
        let Some(record) = self.task(id) else { return };
        let mut rec = record.lock().unwrap_or_else(|e| e.into_inner());

        let flow_result = match result {
            Ok(r) => r,
            Err(e) => {
                // 引擎级错误（理论上预检后不该发生）：记为失败，别丢任务。
                rec.state = TaskState::Failed;
                rec.error = Some(json!({ "step": null, "message": e.to_string() }));
                rec.finished_at_ms = Some(now_ms());
                let view = task_view(&rec);
                drop(rec);
                let _ = self.app.bus.publish_from(Some("task"), TOPIC_STATE, view);
                return;
            }
        };

        rec.state = if flow_result.success {
            TaskState::Completed
        } else if token.is_cancelled() {
            TaskState::Cancelled
        } else {
            TaskState::Failed
        };

        // 步骤终态覆盖。output / attempts / duration_ms 只在 FlowResult 里有。
        for result_step in &flow_result.steps {
            let Some(step) = rec
                .steps
                .iter_mut()
                .find(|s| s.step_id == result_step.step_id.to_string())
            else {
                continue;
            };
            // 事件已标成 rolled_back 的保持不变（引擎的 StepResult 里回滚
            // 不是一种状态，是叠加事实）。
            if step.status == StepStatus::RolledBack {
                step.output = Some(result_step.output.clone());
                continue;
            }
            // 取消时还在 Failed 的步骤降级成 Skipped——用户主动放弃，
            // 把它显示成失败会误导。
            if token.is_cancelled() && result_step.status == SzalStatus::Failed {
                step.status = StepStatus::Skipped;
                step.error = Some("cancelled".into());
                step.attempts = result_step.attempts;
                step.duration_ms = result_step.duration_ms;
                continue;
            }
            step.status = map_step_status(result_step.status);
            step.output = if result_step.status == SzalStatus::Completed {
                Some(result_step.output.clone())
            } else {
                None
            };
            step.error = result_step.error.clone();
            step.attempts = result_step.attempts;
            step.duration_ms = result_step.duration_ms;
        }

        // 失败信息：第一个失败的步骤（含步骤名，前端直接展示）。
        if rec.state == TaskState::Failed {
            rec.error = flow_result
                .steps
                .iter()
                .find(|s| s.status == SzalStatus::Failed)
                .map(|s| {
                    let name = rec
                        .steps
                        .iter()
                        .find(|x| x.step_id == s.step_id.to_string())
                        .map(|x| x.name.clone())
                        .unwrap_or_default();
                    json!({ "step": name, "message": s.error.clone().unwrap_or_default() })
                });
        } else {
            rec.error = None;
        }

        rec.rolled_back = flow_result.rolled_back;
        rec.current_step = None;
        rec.finished_at_ms = Some(now_ms());
        rec.total_duration_ms = Some(flow_result.total_duration_ms);

        let view = task_view(&rec);
        drop(rec);
        let _ = self.app.bus.publish_from(Some("task"), TOPIC_STATE, view);
    }

    // ---- 查询 ---------------------------------------------------------------

    /// 按任务 id 取任务对象的线上形状。
    pub fn view(&self, id: &str) -> Option<Value> {
        let record = self.task(id)?;
        let rec = record.lock().unwrap_or_else(|e| e.into_inner());
        Some(task_view(&rec))
    }

    /// 全部任务（最新提交在前）。
    pub fn list(&self) -> Vec<Value> {
        let tasks = self.tasks.lock().unwrap_or_else(|e| e.into_inner());
        let mut items: Vec<(u64, Value)> = tasks
            .values()
            .map(|record| {
                let rec = record.lock().unwrap_or_else(|e| e.into_inner());
                (rec.created_at_ms, task_view(&rec))
            })
            .collect();
        items.sort_by_key(|(ts, _)| std::cmp::Reverse(*ts));
        items.into_iter().map(|(_, v)| v).collect()
    }

    /// 取消一个任务（幂等）：已终态的什么都不做，原样返回当前快照。
    pub fn cancel(&self, id: &str) -> RpcResult<Value> {
        let record = self
            .task(id)
            .ok_or_else(|| RpcError::new(CODE_NOT_FOUND, format!("任务 `{id}` 不存在")))?;
        let rec = record.lock().unwrap_or_else(|e| e.into_inner());
        if !rec.state.is_terminal() {
            // 取消令牌一按，执行流会在当前步骤结束后收尾成 cancelled。
            rec.token.cancel();
        }
        Ok(task_view(&rec))
    }

    /// 模块停止：把所有在途任务都取消（步骤间生效），不等它们收尾——
    /// 优雅关闭留给进程的取消令牌整体把关。
    pub fn cancel_all(&self) {
        let tasks = self.tasks.lock().unwrap_or_else(|e| e.into_inner());
        for record in tasks.values() {
            let rec = record.lock().unwrap_or_else(|e| e.into_inner());
            if !rec.state.is_terminal() {
                rec.token.cancel();
            }
        }
    }

    // ---- 内部 ---------------------------------------------------------------

    fn task(&self, id: &str) -> Option<Arc<Mutex<TaskRecord>>> {
        self.tasks
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .get(id)
            .cloned()
    }

    /// 推一次 `task.state`（完整任务对象）。
    fn publish_state(&self, id: &str) {
        if let Some(view) = self.view(id) {
            let _ = self.app.bus.publish_from(Some("task"), TOPIC_STATE, view);
        }
    }

    /// 已终态任务超出保留上限时删最老的。调用方持有表锁。
    fn prune_history_locked(&self, tasks: &mut BTreeMap<String, Arc<Mutex<TaskRecord>>>) {
        let limit = self.cfg.clamped_history_limit();
        let mut finished: Vec<(u64, String)> = tasks
            .iter()
            .filter_map(|(id, record)| {
                let rec = record.lock().unwrap_or_else(|e| e.into_inner());
                rec.state
                    .is_terminal()
                    .then_some((rec.created_at_ms, id.clone()))
            })
            .collect();
        if finished.len() <= limit {
            return;
        }
        // 最老的先删；created_at_ms 理论上唯一（毫秒粒度 + 提交串行），
        // 撞了就按 id 稳定排序，删谁都不算错。
        finished.sort();
        let excess = finished.len() - limit;
        for (_, id) in finished.into_iter().take(excess) {
            tasks.remove(&id);
        }
    }
}

/// 生命周期事件 → 步骤中间态 + `task.state` 推送。
fn handle_workflow_event(runner: &Arc<TaskRunner>, id: &str, ev: &WorkflowEvent) {
    let Some((step_name, step_id)) = ev.step_name.as_ref().zip(ev.step_id.as_ref()) else {
        return;
    };
    let Some(record) = runner.task(id) else {
        return;
    };
    {
        let mut rec = record.lock().unwrap_or_else(|e| e.into_inner());
        let Some(step) = rec.steps.iter_mut().find(|s| s.step_id == *step_id) else {
            return;
        };
        match ev.event_type {
            EventType::StepStarted => {
                step.status = StepStatus::Running;
                rec.current_step = Some(step_name.clone());
            }
            EventType::StepCompleted => {
                step.status = StepStatus::Completed;
                step.attempts = ev.attempt.unwrap_or(1);
                step.duration_ms = ev.duration_ms.unwrap_or(0);
            }
            EventType::StepFailed => {
                step.status = StepStatus::Failed;
                step.error = ev.error.clone();
                step.attempts = ev.attempt.unwrap_or(1);
                step.duration_ms = ev.duration_ms.unwrap_or(0);
            }
            EventType::StepSkipped => {
                step.status = StepStatus::Skipped;
                step.error = ev.error.clone();
            }
            EventType::StepRollback => {
                step.status = StepStatus::RolledBack;
            }
            // StepRetry / Flow* / StepTimeout 不改状态：重试还在跑，
            // flow 级状态由执行器记账，StepTimeout 实际通过 StepFailed 上报。
            _ => {}
        }
    }
    if let Some(view) = runner.view(id) {
        let _ = runner.app.bus.publish_from(Some("task"), TOPIC_STATE, view);
    }
}

/// szal 步骤状态 → 线上步骤状态。
fn map_step_status(status: SzalStatus) -> StepStatus {
    match status {
        SzalStatus::Pending => StepStatus::Pending,
        SzalStatus::Running => StepStatus::Running,
        SzalStatus::Completed => StepStatus::Completed,
        SzalStatus::Failed => StepStatus::Failed,
        SzalStatus::Skipped => StepStatus::Skipped,
        // FlowResult 里不会出现（回滚是我们叠加的状态），防御性映射。
        SzalStatus::RolledBack => StepStatus::RolledBack,
        _ => StepStatus::Pending,
    }
}

#[cfg(test)]
mod tests {
    use super::super::flows::{
        FlowRegistry, FlowStepInfo, FlowTemplate, StepSpec, TIMEOUT_UNLIMITED,
    };
    use super::*;
    use crate::config::Config;
    use crate::module::registry::ModuleRegistry;
    use std::path::Path;
    use szal::flow::{FlowDef, FlowMode};
    use szal::step::StepDef;
    use uuid::Uuid;

    fn test_app() -> AppState {
        let registry = Arc::new(ModuleRegistry::build(vec![], &Config::default()).unwrap());
        AppState::new(Config::default(), None, registry, CancellationToken::new())
    }

    fn test_runner() -> (Arc<TaskRunner>, Arc<FlowRegistry>) {
        let app = test_app();
        let flows = Arc::new(FlowRegistry::new());
        let runner = Arc::new(TaskRunner::new(app, TaskConfig::default(), flows.clone()));
        (runner, flows)
    }

    /// 成功步骤：output 回显 step.config。
    fn ok_step() -> StepSpec {
        StepSpec {
            title: "成功".into(),
            run: Arc::new(|step, _p, _env| {
                Box::pin(async move { Ok(step.config.clone().unwrap_or(Value::Null)) })
            }),
            rollback: None,
        }
    }

    /// 失败步骤：永远返回错误。
    fn fail_step() -> StepSpec {
        StepSpec {
            title: "失败".into(),
            run: Arc::new(|_s, _p, _e| Box::pin(async move { Err("故意失败".into()) })),
            rollback: None,
        }
    }

    /// 建目录步骤（可回滚）：config.dir 指定路径，run 建目录，rollback 删目录。
    fn mkdir_step() -> StepSpec {
        StepSpec {
            title: "建目录".into(),
            run: Arc::new(|step, _p, _env| {
                Box::pin(async move {
                    let dir = step
                        .config
                        .as_ref()
                        .and_then(|c| c.get("dir"))
                        .and_then(|v| v.as_str())
                        .ok_or("缺 dir 配置")?;
                    tokio::fs::create_dir_all(dir)
                        .await
                        .map_err(|e| e.to_string())?;
                    Ok(json!({ "dir": dir }))
                })
            }),
            rollback: Some(Arc::new(|step, _env| {
                Box::pin(async move {
                    if let Some(dir) = step
                        .config
                        .as_ref()
                        .and_then(|c| c.get("dir"))
                        .and_then(|v| v.as_str())
                    {
                        let _ = tokio::fs::remove_dir_all(dir).await;
                    }
                    Ok(())
                })
            })),
        }
    }

    /// 读共享产出的步骤：把 `env.output("a")` 原样回显，验证步骤间数据传递。
    fn echo_shared_step() -> StepSpec {
        StepSpec {
            title: "读共享".into(),
            run: Arc::new(|_s, _p, env| {
                Box::pin(async move {
                    env.output("a")
                        .await
                        .ok_or_else(|| "没拿到 a 的产出".to_string())
                })
            }),
            rollback: None,
        }
    }

    /// 长睡步骤：内部 `select!` 取消令牌，好让取消立即生效。
    fn sleep_step() -> StepSpec {
        StepSpec {
            title: "长睡".into(),
            run: Arc::new(|_s, _p, env| {
                Box::pin(async move {
                    tokio::select! {
                        _ = tokio::time::sleep(std::time::Duration::from_secs(30)) => {
                            Ok(json!({"done": true}))
                        }
                        _ = env.cancel.cancelled() => {
                            Err("cancelled".into())
                        }
                    }
                })
            }),
            rollback: None,
        }
    }

    fn single_flow(step_type: &str) -> FlowTemplate {
        let step_type = step_type.to_string();
        FlowTemplate {
            title: "单步".into(),
            steps: vec![FlowStepInfo {
                name: "a".into(),
                title: "甲".into(),
                step_type: step_type.clone(),
            }],
            build: Arc::new(move |_| {
                let mut flow = FlowDef::new("test", FlowMode::Sequential);
                flow.add_step(
                    StepDef::new("a")
                        .with_step_type(step_type.clone())
                        .with_timeout(TIMEOUT_UNLIMITED),
                );
                Ok(flow)
            }),
        }
    }

    /// 轮询任务直到终态（最多 5s）。
    async fn wait_terminal(runner: &TaskRunner, id: &str) -> Value {
        for _ in 0..250 {
            if let Some(v) = runner.view(id)
                && let Some(state) = v["state"].as_str()
                && matches!(state, "completed" | "failed" | "cancelled")
            {
                return v;
            }
            tokio::time::sleep(std::time::Duration::from_millis(20)).await;
        }
        panic!("任务 {id} 未在 5s 内到达终态");
    }

    #[tokio::test]
    async fn submit_runs_single_step_to_completion() {
        let (runner, flows) = test_runner();
        flows.register_step("test.ok", ok_step()).unwrap();
        flows
            .register_flow("test.single", single_flow("test.ok"))
            .unwrap();

        let view = runner.submit("test.single", json!({})).unwrap();
        let id = view["id"].as_str().unwrap().to_string();
        let final_view = wait_terminal(&runner, &id).await;

        assert_eq!(final_view["state"], json!("completed"));
        assert_eq!(final_view["steps"][0]["status"], json!("completed"));
        assert_eq!(final_view["steps"][0]["attempts"], json!(1));
        assert!(final_view["finished_at_ms"].as_u64().is_some());
    }

    #[tokio::test]
    async fn step_outputs_are_shared_between_steps() {
        let (runner, flows) = test_runner();
        flows.register_step("test.ok", ok_step()).unwrap();
        flows
            .register_step("test.echo_shared", echo_shared_step())
            .unwrap();
        flows
            .register_flow(
                "test.shared",
                FlowTemplate {
                    title: "共享产出".into(),
                    steps: vec![
                        FlowStepInfo {
                            name: "a".into(),
                            title: "甲".into(),
                            step_type: "test.ok".into(),
                        },
                        FlowStepInfo {
                            name: "b".into(),
                            title: "乙".into(),
                            step_type: "test.echo_shared".into(),
                        },
                    ],
                    build: Arc::new(|_| {
                        let mut flow = FlowDef::new("test", FlowMode::Sequential);
                        flow.add_step(
                            StepDef::new("a")
                                .with_step_type("test.ok")
                                .with_config(json!({"instance_id": "xyz123"}))
                                .with_timeout(TIMEOUT_UNLIMITED),
                        );
                        flow.add_step(
                            StepDef::new("b")
                                .with_step_type("test.echo_shared")
                                .with_timeout(TIMEOUT_UNLIMITED),
                        );
                        Ok(flow)
                    }),
                },
            )
            .unwrap();

        let view = runner.submit("test.shared", json!({})).unwrap();
        let id = view["id"].as_str().unwrap().to_string();
        let final_view = wait_terminal(&runner, &id).await;

        assert_eq!(final_view["state"], json!("completed"));
        // 第一步 output 是它的 config；第二步 output 复用了第一步的产出
        assert_eq!(
            final_view["steps"][0]["output"]["instance_id"],
            json!("xyz123")
        );
        assert_eq!(
            final_view["steps"][1]["output"]["instance_id"],
            json!("xyz123")
        );
    }

    #[tokio::test]
    async fn failure_triggers_rollback_deleting_artifact() {
        let (runner, flows) = test_runner();
        let sub = std::env::temp_dir().join(format!("ec-task-test-{}", Uuid::new_v4()));
        let sub_str = sub.to_string_lossy().into_owned();
        flows.register_step("test.mkdir", mkdir_step()).unwrap();
        flows.register_step("test.fail", fail_step()).unwrap();
        flows
            .register_flow(
                "test.rollback",
                FlowTemplate {
                    title: "回滚测试".into(),
                    steps: vec![
                        FlowStepInfo {
                            name: "create".into(),
                            title: "建".into(),
                            step_type: "test.mkdir".into(),
                        },
                        FlowStepInfo {
                            name: "deploy".into(),
                            title: "部".into(),
                            step_type: "test.fail".into(),
                        },
                    ],
                    build: {
                        let dir = sub_str.clone();
                        Arc::new(move |_| {
                            let mut flow =
                                FlowDef::new("test", FlowMode::Sequential).with_rollback();
                            flow.add_step(
                                StepDef::new("create")
                                    .with_step_type("test.mkdir")
                                    .with_config(json!({ "dir": dir }))
                                    .with_rollback()
                                    .with_timeout(TIMEOUT_UNLIMITED),
                            );
                            flow.add_step(
                                StepDef::new("deploy")
                                    .with_step_type("test.fail")
                                    .with_timeout(TIMEOUT_UNLIMITED),
                            );
                            Ok(flow)
                        })
                    },
                },
            )
            .unwrap();

        let view = runner.submit("test.rollback", json!({})).unwrap();
        let id = view["id"].as_str().unwrap().to_string();
        let final_view = wait_terminal(&runner, &id).await;

        assert_eq!(final_view["state"], json!("failed"));
        assert_eq!(final_view["rolled_back"], json!(true));
        // 失败步骤本身
        assert_eq!(final_view["steps"][1]["status"], json!("failed"));
        // create 步骤确实跑过且建了目录（output 里有它建的路径）
        assert_eq!(final_view["steps"][0]["output"]["dir"], json!(sub_str));
        // 回滚之后目录应已被删（回滚是异步的，给一点时间）
        for _ in 0..50 {
            if !Path::new(&sub_str).exists() {
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(20)).await;
        }
        assert!(
            !Path::new(&sub_str).exists(),
            "回滚应删除 create 步骤建的目录"
        );
    }

    #[tokio::test]
    async fn cancels_running_task_to_cancelled() {
        let (runner, flows) = test_runner();
        flows.register_step("test.sleep", sleep_step()).unwrap();
        flows
            .register_flow("test.long", single_flow("test.sleep"))
            .unwrap();

        let view = runner.submit("test.long", json!({})).unwrap();
        let id = view["id"].as_str().unwrap().to_string();
        // 等到 running
        for _ in 0..100 {
            if let Some(v) = runner.view(&id)
                && v["state"] == json!("running")
            {
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(10)).await;
        }
        runner.cancel(&id).unwrap();
        let final_view = wait_terminal(&runner, &id).await;

        assert_eq!(final_view["state"], json!("cancelled"));
        // 协作取消：步骤降级成 skipped
        assert_eq!(final_view["steps"][0]["status"], json!("skipped"));
    }

    #[test]
    fn rejects_unregistered_step_type() {
        let (runner, flows) = test_runner();
        flows
            .register_flow(
                "test.bogus",
                FlowTemplate {
                    title: "引用未注册步骤".into(),
                    steps: vec![FlowStepInfo {
                        name: "a".into(),
                        title: "甲".into(),
                        step_type: "test.never_registered".into(),
                    }],
                    build: Arc::new(|_| {
                        let mut flow = FlowDef::new("test", FlowMode::Sequential);
                        flow.add_step(
                            StepDef::new("a")
                                .with_step_type("test.never_registered")
                                .with_timeout(TIMEOUT_UNLIMITED),
                        );
                        Ok(flow)
                    }),
                },
            )
            .unwrap();

        let err = runner.submit("test.bogus", json!({})).unwrap_err();
        assert_eq!(err.code, CODE_INVALID_PARAMS);
        assert!(err.message.contains("未注册"));
    }

    #[test]
    fn rejects_rollbackable_step_without_rollback_impl() {
        let (runner, flows) = test_runner();
        flows.register_step("test.ok", ok_step()).unwrap(); // 没注册 rollback
        flows
            .register_flow(
                "test.bad_rollback",
                FlowTemplate {
                    title: "标回滚但无实现".into(),
                    steps: vec![FlowStepInfo {
                        name: "a".into(),
                        title: "甲".into(),
                        step_type: "test.ok".into(),
                    }],
                    build: Arc::new(|_| {
                        let mut flow = FlowDef::new("test", FlowMode::Sequential);
                        flow.add_step(
                            StepDef::new("a")
                                .with_step_type("test.ok")
                                .with_rollback()
                                .with_timeout(TIMEOUT_UNLIMITED),
                        );
                        Ok(flow)
                    }),
                },
            )
            .unwrap();

        let err = runner.submit("test.bad_rollback", json!({})).unwrap_err();
        assert_eq!(err.code, CODE_INVALID_PARAMS);
        assert!(err.message.contains("没注册回滚实现"));
    }

    #[test]
    fn rejects_missing_flow() {
        let (runner, _flows) = test_runner();
        let err = runner.submit("test.does_not_exist", json!({})).unwrap_err();
        assert_eq!(err.code, CODE_FLOW_NOT_FOUND);
    }

    #[test]
    fn rejects_non_object_params() {
        let (runner, flows) = test_runner();
        flows.register_step("test.ok", ok_step()).unwrap();
        flows
            .register_flow("test.single", single_flow("test.ok"))
            .unwrap();
        let err = runner.submit("test.single", json!(["array"])).unwrap_err();
        assert_eq!(err.code, CODE_INVALID_PARAMS);
    }
}
