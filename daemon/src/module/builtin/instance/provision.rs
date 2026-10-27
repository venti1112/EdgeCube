//! 「创建实例 → 下载服务端」工作流（`instance-provision`）。
//!
//! 这条流程以前是**前端串三步**（`mcserver.plan` → `instance.create` →
//! `download.add`）。现在交给任务系统编排，前端只发一次 `task.submit`：
//!
//! ```text
//! plan（准备服务端，mcserver 注册的步骤）
//!   ↓ output: url / file_name / checksum / startup_command
//! create（创建实例，本模块）
//!   ↓ output: instance_id          ← 回滚点：后续失败就删掉它
//! download（下载服务端，本模块）
//! ```
//!
//! 三个步骤而不是两个，是因为「解析下载计划」要打上游（异步），塞不进
//! `FlowTemplate::build`（它是同步的、只做参数校验）。拆出来还有个好处：
//! 解析失败时用户看到的是「准备服务端」这一步挂了，而不是莫名其妙的「创建失败」。
//!
//! ## 回滚
//!
//! 目标是**不留空壳实例**：下载失败就把刚建的实例删掉，且只删
//! 「这一次建的」—— id 走 `create` 步骤的 output，回滚处理从那里取，
//! 不会误伤别的实例。
//!
//! 注意**取消不触发回滚**（szal 的语义：skipped ≠ failed）。用户主动放弃时
//! 实例会留在列表里，这是刻意的 —— 与「失败必须收拾干净」是两种语义。

use std::sync::Arc;

use serde_json::{Value, json};
use szal::flow::{FlowDef, FlowMode};
use szal::step::StepDef;

use super::{InstanceState, Resolved, TOPIC_CREATED, blocking, now_ms, resolve_instance_root};
use crate::module::builtin::download::{self, InternalRequest, Owner};
use crate::module::builtin::task::flows::{
    self, FlowStepInfo, FlowTemplate, StepSpec, TIMEOUT_UNLIMITED,
};
use crate::state::AppState;

/// 工作流名（`task.submit` 的 `flow`）。
pub const FLOW: &str = "instance-provision";

/// 本模块的三个步骤里，前两个是我们自己实现的；
/// 第一步 `plan` 由 mcserver 注册（见 `mcserver::register_plan_step`）。
const STEP_PLAN: &str = "mcserver.plan";
const STEP_CREATE: &str = "instance.create";
const STEP_DOWNLOAD: &str = "instance.download";

/// 步骤在 flow 里的**名字**（`StepEnv::output(..)` 用的键）。
///
/// 与 `step_type` 是两回事：产出表按 `StepDef.name` 建。混用会得到
/// 「上一步没有产出…」这种下游报错、而上游明明成功了（runtime 那边实测踩过）。
const NAME_PLAN: &str = "plan";
const NAME_CREATE: &str = "create";
const NAME_DOWNLOAD: &str = "download";

/// 把这条工作流挂到任务系统的注册表里。`start()` 里调。
///
/// task 模块没启用时不注册 —— 注册表没人读。
pub(super) fn register(state: &Arc<InstanceState>, app: &AppState) {
    if !crate::module::builtin::task::enabled(app) {
        tracing::debug!("task 模块未启用，`{FLOW}` 工作流跳过注册");
        return;
    }

    let registry = flows::registry(app);
    registry.register_step_or_warn(STEP_CREATE, create_step(state.clone()));
    registry.register_step_or_warn(STEP_DOWNLOAD, download_step(state.clone()));
    registry.register_flow_or_warn(FLOW, template());
}

/// 步骤「创建实例」：拿上一步解析出的启动命令建实例，产出实例 id。
///
/// 回滚 = 删掉这个实例（`keep_files: false`，连目录一起 —— 里面可能有
/// 下了一半的 jar）。
fn create_step(state: Arc<InstanceState>) -> StepSpec {
    let rollback_state = state.clone();
    StepSpec {
        title: "创建实例".into(),
        run: Arc::new(move |step, progress, env| {
            let state = state.clone();
            Box::pin(async move {
                let name = step
                    .config
                    .as_ref()
                    .and_then(|c| c.get("name"))
                    .and_then(Value::as_str)
                    .ok_or("`instance.create` 步骤缺少 `name` 配置")?
                    .trim()
                    .to_string();

                // 启动命令来自 `plan` 步骤的产出（daemon 侧统一解析，前端不掺和）
                let plan = env
                    .output(NAME_PLAN)
                    .await
                    .ok_or("上一步（准备服务端）没有产出下载计划")?;
                let startup_command = plan.get("startup_command").cloned().unwrap_or(Value::Null);

                progress.report(json!({ "percent": null, "message": "正在创建实例" }));

                let resolved = resolved_of(&state)?;
                // 与 `instance.create` 同一条临界区：索引是「读-改-写」的，
                // 不加锁两个并发的建实例会一个覆盖掉另一个。
                let guard = state.lock.lock().await;
                let created = blocking({
                    let resolved = resolved.clone();
                    move || {
                        resolved.create(json!({ "name": name, "startup_command": startup_command }))
                    }
                })
                .await;
                drop(guard);
                let created = created.map_err(|e| format!("{}：{}", e.code, e.message))?;

                let instance = &created["instance"];
                let id = instance["id"].as_str().unwrap_or_default().to_string();
                // 与 WS 的 `instance.create` 推同一个主题：列表页不用区分来源
                env.app.bus.publish_from(
                    Some("instance"),
                    TOPIC_CREATED,
                    json!({ "id": id, "name": instance["name"], "ts": now_ms() }),
                );
                Ok(json!({ "instance_id": id, "name": instance["name"] }))
            })
        }),
        rollback: Some(Arc::new(move |_step, env| {
            let state = rollback_state.clone();
            Box::pin(async move {
                // id 从 `create` 步骤的产出里拿 —— 只删这一次流程建的那个
                let Some(created) = env.output(NAME_CREATE).await else {
                    return Ok(());
                };
                let Some(id) = created.get("instance_id").and_then(Value::as_str) else {
                    return Ok(());
                };
                let id = id.to_string();

                let resolved = resolved_of(&state)?;
                let guard = state.lock.lock().await;
                let deleted = blocking({
                    let resolved = resolved.clone();
                    let id = id.clone();
                    move || resolved.delete(&id, false)
                })
                .await;
                drop(guard);

                match deleted {
                    Ok(_) => {
                        tracing::info!(instance = %id, "下载失败，已回滚删掉这次建的实例");
                        Ok(())
                    }
                    // 回滚失败不算「步骤回滚失败」之外还要再做什么 —— 引擎会把
                    // 这条信息带进任务对象，用户能看到实例还在（可手工删）。
                    Err(e) => Err(format!("回滚删实例失败：{}：{}", e.code, e.message)),
                }
            })
        })),
    }
}

/// 步骤「下载服务端」：把上一步的下载计划落进实例目录。
///
/// 没有回滚 —— 下载是最后一步，失败时该删的是实例（由 `create` 步骤的回滚处理）。
fn download_step(state: Arc<InstanceState>) -> StepSpec {
    StepSpec {
        title: "下载服务端".into(),
        run: Arc::new(move |_step, progress, env| {
            let state = state.clone();
            Box::pin(async move {
                let plan = env
                    .output(NAME_PLAN)
                    .await
                    .ok_or("上一步（准备服务端）没有产出下载计划")?;
                let created = env
                    .output(NAME_CREATE)
                    .await
                    .ok_or("上一步（创建实例）没有产出实例")?;

                let instance_id = created
                    .get("instance_id")
                    .and_then(Value::as_str)
                    .ok_or("实例 id 缺失")?
                    .to_string();
                let url = str_field(&plan, "url")?;
                let file_name = str_field(&plan, "file_name")?;
                let checksum = checksum_of(&plan)?;

                let resolved = resolved_of(&state)?;
                let dir = resolve_instance_root(resolved.store.root(), &instance_id)
                    .map_err(|e| format!("算实例目录失败：{e}"))?;

                // 复用全局下载队列：`download::fetch` 负责报进度与协作取消，
                // 落盘目录是我们算好的绝对路径（模块间调用没有用户输入穿过）。
                let queue = download::queue_of(&env.app)
                    .ok_or("下载队列尚未就绪（download 模块没起来）")?;
                let path = download::fetch(
                    &queue,
                    &env.app,
                    InternalRequest {
                        dir,
                        filename: file_name.clone(),
                        url,
                        checksum,
                        owner: Owner::Instance {
                            instance_id: instance_id.clone(),
                            // 服务端文件落在实例根目录
                            path: String::new(),
                        },
                    },
                    &env.cancel,
                    // 实例侧不关心队列任务 id：进度与归属都走任务对象
                    |_task_id| {},
                    |frame| progress.report(frame),
                )
                .await?;

                Ok(json!({
                    "path": path.display().to_string(),
                    "file_name": file_name,
                    "instance_id": instance_id,
                }))
            })
        }),
        rollback: None,
    }
}

/// 工作流模板：展示用的步骤清单 + 参数 → [`FlowDef`]。
fn template() -> FlowTemplate {
    FlowTemplate {
        title: "创建实例并下载服务端".into(),
        steps: vec![
            FlowStepInfo {
                name: NAME_PLAN.into(),
                title: "准备服务端".into(),
                step_type: STEP_PLAN.into(),
            },
            FlowStepInfo {
                name: NAME_CREATE.into(),
                title: "创建实例".into(),
                step_type: STEP_CREATE.into(),
            },
            FlowStepInfo {
                name: NAME_DOWNLOAD.into(),
                title: "下载服务端".into(),
                step_type: STEP_DOWNLOAD.into(),
            },
        ],
        build: Arc::new(|params| {
            // 参数校验都在这里做完（同步、不碰网络）：坏参数不该拿到任务 id。
            let name = required_str(params, "name")?;
            let type_id = required_str(params, "type")?;
            let version = optional_str(params, "version");
            let loader_version = optional_str(params, "loader_version");

            let mut plan_config = json!({ "type": type_id });
            if let Some(version) = &version {
                plan_config["version"] = json!(version);
            }
            if let Some(loader) = &loader_version {
                plan_config["loader_version"] = json!(loader);
            }

            let mut flow = FlowDef::new(FLOW, FlowMode::Sequential);
            // 没有这一行引擎不会回滚，`create` 标了 rollbackable 也没用
            flow.rollback_on_failure = true;
            flow.add_step(
                StepDef::new(NAME_PLAN)
                    .with_step_type(STEP_PLAN)
                    .with_config(plan_config)
                    .with_timeout(TIMEOUT_UNLIMITED),
            );
            flow.add_step(
                StepDef::new(NAME_CREATE)
                    .with_step_type(STEP_CREATE)
                    .with_config(json!({ "name": name }))
                    .with_rollback()
                    .with_timeout(TIMEOUT_UNLIMITED),
            );
            flow.add_step(
                StepDef::new(NAME_DOWNLOAD)
                    .with_step_type(STEP_DOWNLOAD)
                    .with_timeout(TIMEOUT_UNLIMITED),
            );
            Ok(flow)
        }),
    }
}

// ---------------------------------------------------------------------------
// 小工具
// ---------------------------------------------------------------------------

/// 取实例存储。`start()` 已经把 `Resolved` 填进 `InstanceState` 了，
/// 这里直接拿（不必再解析一次模块配置）。
fn resolved_of(state: &Arc<InstanceState>) -> Result<Resolved, String> {
    state
        .resolved(None)
        .map_err(|e| format!("实例存储不可用：{}：{}", e.code, e.message))
}

fn required_str(params: &Value, key: &str) -> Result<String, String> {
    let value = params
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .unwrap_or_default();
    if value.is_empty() {
        return Err(format!("参数 `{key}` 不能为空"));
    }
    Ok(value.to_string())
}

fn optional_str(params: &Value, key: &str) -> Option<String> {
    params
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|v| !v.is_empty())
        .map(str::to_string)
}

fn str_field(plan: &Value, key: &str) -> Result<String, String> {
    plan.get(key)
        .and_then(Value::as_str)
        .filter(|v| !v.is_empty())
        .map(str::to_string)
        .ok_or_else(|| format!("下载计划里缺 `{key}`"))
}

/// 把 `mcserver.plan` output 里的校验值翻成下载队列要的 `(算法, 值)`。
///
/// `algorithm` 的取值就是 `download.add` 的参数名，所以这里只是「字符串 →
/// `&'static str`」的搬运；认不出的算法**报错而不是静默跳过** —— 悄悄不校验
/// 比下载失败更糟。
fn checksum_of(plan: &Value) -> Result<Option<(&'static str, String)>, String> {
    let Some(checksum) = plan.get("checksum").filter(|v| !v.is_null()) else {
        return Ok(None);
    };
    let algorithm = checksum
        .get("algorithm")
        .and_then(Value::as_str)
        .ok_or("下载计划里的校验值缺 `algorithm`")?;
    let value = checksum
        .get("value")
        .and_then(Value::as_str)
        .ok_or("下载计划里的校验值缺 `value`")?
        .to_string();

    match algorithm {
        "sha1" => Ok(Some(("sha1", value))),
        "sha256" => Ok(Some(("sha256", value))),
        "md5" => Ok(Some(("md5", value))),
        other => Err(format!("不认识的校验算法 `{other}`")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 参数校验在 `build` 里做完：缺 name / type 都该被拒，且**不产生任务**。
    #[test]
    fn build_rejects_missing_params() {
        let build = template().build;
        assert!(build(&json!({})).is_err());
        assert!(build(&json!({ "name": "服" })).is_err());
        assert!(build(&json!({ "type": "paper" })).is_err());
        assert!(build(&json!({ "name": "   ", "type": "paper" })).is_err());
    }

    /// 参数齐了就该产出一份三步的顺序流程，且只有 `create` 可回滚。
    #[test]
    fn build_produces_three_steps() {
        let build = template().build;
        let flow = build(&json!({
            "name": "我的服",
            "type": "fabric",
            "version": "1.21.1",
            "loader_version": "0.16.5",
        }))
        .expect("参数齐全应当能构造流程");

        assert_eq!(flow.steps.len(), 3);
        // 顺序与步骤类型对得上
        assert_eq!(flow.steps[0].name, NAME_PLAN);
        assert_eq!(flow.steps[0].step_type.as_deref(), Some(STEP_PLAN));
        assert_eq!(flow.steps[1].name, NAME_CREATE);
        assert_eq!(flow.steps[1].step_type.as_deref(), Some(STEP_CREATE));
        assert_eq!(flow.steps[2].name, NAME_DOWNLOAD);
        assert_eq!(flow.steps[2].step_type.as_deref(), Some(STEP_DOWNLOAD));
        // 回滚开关：flow 级 + create 步骤级都要开，否则引擎不回滚
        assert!(flow.rollback_on_failure);
        assert!(!flow.steps[0].rollbackable);
        assert!(flow.steps[1].rollbackable);
        assert!(!flow.steps[2].rollbackable);
    }

    /// 版本 / 加载器是可选的，且会写进 plan 步骤的 config。
    #[test]
    fn build_passes_optional_params_into_plan_config() {
        let build = template().build;
        let flow = build(&json!({ "name": "服", "type": "paper" })).unwrap();
        let config = flow.steps[0].config.clone().unwrap();
        assert_eq!(config["type"], json!("paper"));
        assert!(config.get("version").is_none(), "没给版本就不该造一个出来");
        assert!(config.get("loader_version").is_none());
    }

    #[test]
    fn checksum_translates_known_algorithms_and_rejects_others() {
        let plan = json!({ "checksum": { "algorithm": "sha256", "value": "abc" } });
        assert_eq!(checksum_of(&plan).unwrap(), Some(("sha256", "abc".into())));

        // 上游没给校验值 → 不校验（不是错误）
        assert!(checksum_of(&json!({ "checksum": null })).unwrap().is_none());
        assert!(checksum_of(&json!({})).unwrap().is_none());

        // 认不出的算法必须报错，不能静默放过
        let bad = json!({ "checksum": { "algorithm": "crc32", "value": "x" } });
        assert!(checksum_of(&bad).is_err());
    }
}
