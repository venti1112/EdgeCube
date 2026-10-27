//! 任务系统模块：基于 szal 的工作流引擎，把多步操作编排成一个任务。
//!
//! 模块本身**不含业务 knowledge** —— 它是「执行与可观测性」的底座。
//! 具体的工作流由各自业务模块在 `start()` 里注册进来：
//!
//! * `instance-provision`（实例创建 → 下载服务端）见 `instance::provision`；
//! * `runtime-install`（下载 → 解压运行环境）见 `runtime::install`。
//!
//! 两个模块各注册自己的步骤；`mcserver` 把「解析下载计划」也做成一个步骤
//! 供前者复用。注册表挂在 `AppState.services` 上（见 [`crate::services`]），
//! **每个 `AppState` 一份**，所以集成测试里多个 harness 互不干扰。
//!
//! 对外四条 WS 方法 + 一个清单接口、两条事件主题、HTTP 镜像。线上形状
//! 与生命周期见 [`runner`] 模块的注释。
//!
//! 设计取舍见 `daemon/README.md` 的「任务系统模块」一节。

pub mod flows;
pub mod model;
pub mod runner;

use std::sync::{Arc, OnceLock};

use axum::Router;
use axum::extract::State;
use axum::response::Response;
use axum::routing::{get, post};
use serde_json::{Value, json};

use self::model::TaskConfig;
use self::runner::{CODE_NOT_FOUND, TaskRunner};
use crate::error::{Result, RpcError};
use crate::module::{Module, ModuleDescriptor, ModuleEnv, Registration};
use crate::server::http::api_result;
use crate::state::AppState;

/// 模块自己的运行态。**每个 `TaskModule` 实例一份**（照 `instance` 模块的
/// `InstanceState` 来），不用进程级 `OnceLock`：一个进程里跑多个 `TaskModule`
/// （集成测试每个 harness 一份）时，各自的任务表、执行器、并发闸门互不串门。
///
/// 执行器要 `AppState` 才能建，那要到 `start()` 才有——所以这里用 `OnceLock`
/// 做一次性填充；WS / HTTP 闭包在 `register()` 就拿着一份 `Arc<TaskState>`
/// 进来了，调用时再 `get()`。
#[derive(Default)]
pub struct TaskState {
    runner: OnceLock<Arc<TaskRunner>>,
}

impl TaskState {
    /// 取执行器；`start()` 之前（或没起来）为 `None`。
    pub fn runner(&self) -> Option<Arc<TaskRunner>> {
        self.runner.get().cloned()
    }
}

pub struct TaskModule {
    state: Arc<TaskState>,
}

impl Default for TaskModule {
    fn default() -> Self {
        Self::new()
    }
}

impl TaskModule {
    pub fn new() -> Self {
        Self {
            state: Arc::new(TaskState::default()),
        }
    }
}

/// WS 方法与 HTTP 路由共用的「执行器没就绪」错误。
fn no_runner() -> RpcError {
    RpcError::unavailable("任务执行器未就绪（task 模块没起来）")
}

/// 任务系统在这次启动里是否启用。
///
/// 业务模块在 `start()` 里注册步骤前先问一句：task 被 `modules.disabled` 关掉时
/// 注册表没人读，注册进去只是白占内存（也会让日志里多一条没意义的注册记录）。
pub fn enabled(app: &AppState) -> bool {
    app.config.modules.is_enabled("task")
}

#[async_trait::async_trait]
impl Module for TaskModule {
    fn descriptor(&self) -> ModuleDescriptor {
        ModuleDescriptor::new("task", "任务系统", env!("CARGO_PKG_VERSION")).description(
            "工作流任务系统：提交多步操作、查询状态、取消，含进度与状态事件。底座基于 szal。",
        )
    }

    fn register(&self, reg: &mut Registration) -> Result<()> {
        // 注册表挂在 `AppState` 上，所以这里**不能**在 register 阶段就取 ——
        // 那时 AppState 还没建。改成在闭包里用 `ctx.app` 现取（每次调用一次
        // 查表，代价可忽略）。
        reg.method("task.flows", "已注册的工作流清单", move |ctx| async move {
            let flows = flows::registry(&ctx.app);
            Ok(json!({ "flows": flows.flows_summary() }))
        });

        {
            let state = self.state.clone();
            reg.method(
                "task.submit",
                "提交工作流任务（flow + params?）",
                move |ctx| {
                    let state = state.clone();
                    async move {
                        let Some(runner) = state.runner() else {
                            return Err(no_runner());
                        };
                        let flow: String = ctx.param("flow")?;
                        let params = ctx.optional::<Value>("params")?.unwrap_or(Value::Null);
                        runner.submit(&flow, params)
                    }
                },
            );
        }
        {
            let state = self.state.clone();
            reg.method(
                "task.list",
                "全部任务（最新提交在前）",
                move |_ctx| {
                    let state = state.clone();
                    async move {
                        let Some(runner) = state.runner() else {
                            return Err(no_runner());
                        };
                        let tasks = runner.list();
                        let count = tasks.len();
                        Ok(json!({ "tasks": tasks, "count": count }))
                    }
                },
            );
        }
        {
            let state = self.state.clone();
            reg.method("task.get", "按 id 查任务", move |ctx| {
                let state = state.clone();
                async move {
                    let Some(runner) = state.runner() else {
                        return Err(no_runner());
                    };
                    let id: String = ctx.param("id")?;
                    runner
                        .view(&id)
                        .ok_or_else(|| RpcError::new(CODE_NOT_FOUND, format!("任务 `{id}` 不存在")))
                }
            });
        }
        {
            let state = self.state.clone();
            reg.method(
                "task.cancel",
                "取消任务（幂等；已终态的原样返回）",
                move |ctx| {
                    let state = state.clone();
                    async move {
                        let Some(runner) = state.runner() else {
                            return Err(no_runner());
                        };
                        let id: String = ctx.param("id")?;
                        runner.cancel(&id)
                    }
                },
            );
        }

        reg.topic("task.state", "任务状态变化（含步骤级），载荷为完整任务对象");
        reg.topic("task.progress", "步骤进行中的进度，载荷为完整任务对象");

        reg.router("api/tasks", self.http_router());
        Ok(())
    }

    async fn start(&self, env: ModuleEnv) -> Result<()> {
        let config: TaskConfig = env.config()?;
        tracing::info!(
            max_concurrent = config.clamped_max_concurrent(),
            history_limit = config.clamped_history_limit(),
            "任务系统已就绪（零生产内置 flow，等业务模块注册）",
        );
        // 注册表就在 `AppState` 上：先于 task 起来的模块（mcserver / instance /
        // runtime / download）已经把自己的步骤放进去了，这里取到的是同一份。
        let flows = flows::registry(&env.app);
        let runner = Arc::new(TaskRunner::new(env.app.clone(), config, flows));
        let _ = self.state.runner.set(runner);
        Ok(())
    }

    async fn stop(&self) -> Result<()> {
        if let Some(runner) = self.state.runner() {
            runner.cancel_all();
        }
        Ok(())
    }
}

impl TaskModule {
    fn http_router(&self) -> Router<AppState> {
        // 与 WS 的 `task.flows` 同源：都从 `State<AppState>` 上取（register 阶段
        // 还没有 AppState，所以只能等请求进来再取）。
        let flows_route = |app: State<AppState>| {
            let flows = flows::registry(&app);
            async move { api_result(Ok(json!({ "flows": flows.flows_summary() }))) }
        };

        // 执行器在模块实例里（不是进程全局），HTTP handler 拿不到 ——
        // 用和 flows_route 同样的「闭包捕获」手法把 `TaskState` 塞进路由。
        let state = self.state.clone();
        let list_route = move |_app: State<AppState>| {
            let state = state.clone();
            async move { http_list(&state) }
        };
        let state = self.state.clone();
        let submit_route = move |_app: State<AppState>, axum::Json(body): axum::Json<Value>| {
            let state = state.clone();
            async move { http_submit(&state, body) }
        };
        let state = self.state.clone();
        let get_route =
            move |_app: State<AppState>, axum::extract::Path(id): axum::extract::Path<String>| {
                let state = state.clone();
                async move { http_get(&state, id) }
            };
        let state = self.state.clone();
        let cancel_route =
            move |_app: State<AppState>, axum::extract::Path(id): axum::extract::Path<String>| {
                let state = state.clone();
                async move { http_cancel(&state, id) }
            };

        Router::new()
            .route("/api/tasks", get(list_route).post(submit_route))
            .route("/api/tasks/{id}", get(get_route))
            .route("/api/tasks/{id}/cancel", post(cancel_route))
            .route("/api/task-flows", get(flows_route))
    }
}

fn http_list(state: &TaskState) -> Response {
    match state.runner() {
        Some(runner) => {
            let tasks = runner.list();
            api_result(Ok(json!({ "tasks": tasks, "count": tasks.len() })))
        }
        None => api_result(Err(no_runner())),
    }
}

fn http_submit(state: &TaskState, body: Value) -> Response {
    let Some(runner) = state.runner() else {
        return api_result(Err(no_runner()));
    };
    let flow = match body.get("flow").and_then(|v| v.as_str()) {
        Some(s) => s.to_string(),
        None => {
            return api_result(Err(RpcError::invalid_params(
                "POST /api/tasks 的 body 需要 `flow`（字符串）",
            )));
        }
    };
    let params = body.get("params").cloned().unwrap_or(Value::Null);
    api_result(runner.submit(&flow, params))
}

fn http_get(state: &TaskState, id: String) -> Response {
    let Some(runner) = state.runner() else {
        return api_result(Err(no_runner()));
    };
    match runner.view(&id) {
        Some(view) => api_result(Ok(view)),
        None => api_result(Err(RpcError::new(
            CODE_NOT_FOUND,
            format!("任务 `{id}` 不存在"),
        ))),
    }
}

fn http_cancel(state: &TaskState, id: String) -> Response {
    let Some(runner) = state.runner() else {
        return api_result(Err(no_runner()));
    };
    api_result(runner.cancel(&id))
}
