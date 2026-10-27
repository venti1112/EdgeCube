//! 任务系统的进程内注册入口：工作流模板与步骤实现在这里挂载。
//!
//! 「task 模块只管执行与可观测性，工作流的业务知识留在各自的模块里」——
//! 所以别的模块（`instance` / `runtime` / `mcserver`）在自己的 `start()` 里把
//! 两样东西注册进来：
//!
//! 1. **步骤**（[`FlowRegistry::register_step`]）：一个可复用的原子操作，
//!    比如「创建实例」「提交下载并等它结束」。注册名就是步骤的
//!    `step_type`，约定用 `模块id.动作`（与 WS 方法命名同构，但这是给
//!    工作流用的内部入口，不走网络）。
//! 2. **工作流模板**（[`FlowRegistry::register_flow`]）：把调用方参数变成
//!    一份 [`FlowDef`] 的构造函数。模板声明自己的步骤清单（展示用），
//!    `build` 产出的步骤必须与之对应；`task.submit` 提交时会预检每个
//!    `step_type` 都已注册——别等跑起来一半才发现步骤不存在。
//!
//! 模块之间没有对象查找（`ModuleRegistry` 回吐的是 `Arc<dyn Module>`，
//! 拿不到具体类型），所以注册表挂在 `AppState` 上的跨模块句柄槽
//! （见 [`crate::services`]）里 —— **每个 `AppState` 一份**。生产形态下只有
//! 一份（与进程级全局等价），集成测试一个进程起多个 harness 时各一份，
//! 不会互相串。测试要注册临时工作流也走同一个入口。

use std::collections::{BTreeMap, HashMap};
use std::sync::{Arc, Mutex};

use futures_util::future::BoxFuture;
use serde_json::Value;
use szal::engine::ProgressReporter;
use szal::flow::FlowDef;
use szal::step::StepDef;
use tokio_util::sync::CancellationToken;

use crate::state::AppState;

/// 步骤超时用「不限」的哨兵值：szal 对 `u64::MAX` 不套 `tokio::time::timeout`。
///
/// 必须提醒：`StepDef::new` 的**默认超时是 30 秒**——下载这类长步骤必须
/// 显式 `with_timeout(...)`（给个足够大的数，或这个哨兵），否则 30 秒一到
/// 步骤就被判超时失败（而且还会按重试配置再来几轮）。
pub const TIMEOUT_UNLIMITED: u64 = u64::MAX;

/// 一次步骤执行的环境。
///
/// szal 的 handler 只收到步骤自己的 [`StepDef`]（定义原样，引擎不注入
/// 任何上下文），所以「这个任务是谁、前面步骤产生了什么」都从这里给。
#[derive(Clone)]
pub struct StepEnv {
    /// 所属任务 id（完整 UUID 字符串）。
    pub task_id: String,
    /// 全局状态：步骤实现要干活（读配置、推事件、调别的模块的进程内
    /// 入口）都从这拿。
    pub app: AppState,
    /// 步骤间共享的产出表：步骤名 → 该步骤的 output。
    ///
    /// 由任务执行器在**步骤成功后**写入；后续步骤与回滚处理从这里取
    /// 「前面步骤产生了什么」（例如 create 步骤写进去的 `instance_id`，
    /// 下载步骤和「下载失败删实例」的回滚都要用）。失败的尝试不写——
    /// 半截产物不算产出。
    pub outputs: Arc<tokio::sync::RwLock<serde_json::Map<String, Value>>>,
    /// 任务取消令牌。szal 只在**步骤之间**检查取消，正在执行的步骤会跑完；
    /// 等待类步骤（下载、长 IO）应该 `select!` 它，好让取消尽快生效——
    /// 返回 `Err` 即可，执行器在 `token.is_cancelled()` 时会把这种失败
    /// 降级成 `skipped`，任务终态判 `cancelled`。
    pub cancel: CancellationToken,
    /// 任务级暂存：步骤间传「JSON 装不下」的东西（RAII guard、句柄）。
    ///
    /// **生命周期 = 这个任务**。任务到终态、执行流（`runner::execute`）返回时，
    /// 引擎与它持有的全部步骤闭包一起被丢掉，这张表随之析构 —— 所以往里放
    /// RAII guard 就等于「任务一结束就归还资源」，不需要额外的收尾钩子，
    /// **取消也一样**（取消的任务同样会走到执行流结束）。
    ///
    /// 这正是它与 [`Self::outputs`] 的分工：outputs 是 JSON（会给前端看），
    /// 这里放 Rust 值（只给步骤自己用）。
    ///
    /// 典型用法见 `runtime` 模块的安装流程：`RunningGuard` 在第一个步骤里放进来，
    /// 用来挡住「同一个环境并发装两次」；任务一结束 guard 自动 drop，占位就摘掉了。
    pub scratch: Arc<Mutex<HashMap<String, Box<dyn std::any::Any + Send + Sync>>>>,
}

impl StepEnv {
    /// 取某个已完成步骤的 output（没有则为 `None`）。
    pub async fn output(&self, step: &str) -> Option<Value> {
        self.outputs.read().await.get(step).cloned()
    }

    /// 往任务级暂存里放一个 Rust 值（见 [`StepEnv::scratch`]）。
    pub fn scratch_put<T: std::any::Any + Send + Sync>(&self, key: &str, value: T) {
        self.scratch
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .insert(key.to_string(), Box::new(value));
    }

    /// 从任务级暂存里取一个值；类型对不上当作没有（取出即移除）。
    ///
    /// `downcast` 失败时那个值会被丢掉 —— 调用方与存放方对不上类型属于
    /// 编程错误，测试会先在断言上炸掉。
    pub fn scratch_take<T: std::any::Any + Send + Sync>(&self, key: &str) -> Option<T> {
        self.scratch
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .remove(key)
            .and_then(|boxed| boxed.downcast::<T>().ok())
            .map(|boxed| *boxed)
    }
}

/// 步骤执行体。错误是纯字符串（szal 的约定）；任务对象会把 `step + message`
/// 一起呈现给前端，不需要结构化错误码。
pub type StepFn = Arc<
    dyn Fn(StepDef, ProgressReporter, StepEnv) -> BoxFuture<'static, Result<Value, String>>
        + Send
        + Sync,
>;

/// 回滚执行体：把一个**已成功完成**的步骤撤销掉。
///
/// 引擎只在「flow 标了回滚且有步骤失败」时、按完成顺序的**逆序**调用；
/// 步骤当时的 output 可以从 `env.outputs` 里取。
pub type RollbackFn =
    Arc<dyn Fn(StepDef, StepEnv) -> BoxFuture<'static, Result<(), String>> + Send + Sync>;

/// 一个步骤类型的全部注册信息。
#[derive(Clone)]
pub struct StepSpec {
    /// 展示标题（如「创建实例」）。
    pub title: String,
    /// 执行体。
    pub run: StepFn,
    /// 回滚执行体。步骤标了 `rollbackable` 就必须有，提交预检会拦。
    pub rollback: Option<RollbackFn>,
}

/// 工作流模板的步骤声明（展示用，`task.flows` 会原样给出）。
#[derive(Debug, Clone, serde::Serialize)]
pub struct FlowStepInfo {
    /// 步骤名（flow 内唯一，也是共享产出表的键）。
    pub name: String,
    /// 展示标题。
    pub title: String,
    /// 对应的步骤注册名。
    pub step_type: String,
}

/// 工作流模板：名字怎么变成一份 [`FlowDef`]。
#[derive(Clone)]
pub struct FlowTemplate {
    /// 展示标题（如「创建实例并下载服务端」）。
    pub title: String,
    /// 步骤清单（展示用；`build` 产出的步骤应与之对应，e2e 测试会钉住）。
    pub steps: Vec<FlowStepInfo>,
    /// 参数 → `FlowDef`。参数不合法就在这里报错（`task_invalid_params`），
    /// 别把坏任务放进队列。
    #[allow(clippy::type_complexity)]
    pub build: Arc<dyn Fn(&Value) -> Result<FlowDef, String> + Send + Sync>,
}

/// 全局一份的注册表（进程内）。
///
/// 写入只发生在各模块的 `start()`（启动期单线程）与测试的注册阶段；
/// 运行期全是读 —— 所以用 `Mutex` 就够（临界区只有查表/插表，不跑 await），
/// 不追求无锁。
pub struct FlowRegistry {
    steps: Mutex<BTreeMap<String, StepSpec>>,
    flows: Mutex<BTreeMap<String, FlowTemplate>>,
}

impl Default for FlowRegistry {
    fn default() -> Self {
        Self::new()
    }
}

impl FlowRegistry {
    pub fn new() -> Self {
        Self {
            steps: Mutex::new(BTreeMap::new()),
            flows: Mutex::new(BTreeMap::new()),
        }
    }

    /// 注册一个步骤类型。同名重复注册直接报错——静默覆盖会让「后注册的
    /// 模块悄悄改掉别人的步骤行为」这种事无法排查。
    pub fn register_step(&self, step_type: &str, spec: StepSpec) -> Result<(), String> {
        let mut steps = self.steps.lock().unwrap_or_else(|e| e.into_inner());
        if steps.contains_key(step_type) {
            return Err(format!("步骤类型 `{step_type}` 已注册"));
        }
        steps.insert(step_type.to_string(), spec);
        Ok(())
    }

    /// 注册一个工作流模板。同名重复注册同理报错。
    pub fn register_flow(&self, name: &str, template: FlowTemplate) -> Result<(), String> {
        let mut flows = self.flows.lock().unwrap_or_else(|e| e.into_inner());
        if flows.contains_key(name) {
            return Err(format!("工作流 `{name}` 已注册"));
        }
        flows.insert(name.to_string(), template);
        Ok(())
    }

    /// 模块 `start()` 里注册步骤用：同名已注册时**记一条 warn 后跳过**，
    /// 不打断模块启动。
    ///
    /// 为什么不像 [`Self::register_step`] 那样直接报错：注册表是进程级的，
    /// 而集成测试里一个进程会起多个 `AppState`（每个 harness 一套模块）——
    /// 第二个 harness 的模块必然「重复注册」。让它在这里炸掉，测试全都起不来；
    /// 记一条 warn 则只在真的撞名时留痕。生产形态只有一个 `AppState`，
    /// 撞名一定是编程错误，warn 也够显眼（启动日志里就有）。
    pub fn register_step_or_warn(&self, step_type: &str, spec: StepSpec) {
        if let Err(message) = self.register_step(step_type, spec) {
            tracing::warn!(step = step_type, %message, "步骤没注册上，跳过");
        }
    }

    /// 同 [`Self::register_step_or_warn`]，用于工作流模板。
    pub fn register_flow_or_warn(&self, name: &str, template: FlowTemplate) {
        if let Err(message) = self.register_flow(name, template) {
            tracing::warn!(flow = name, %message, "工作流没注册上，跳过");
        }
    }

    /// 取一个步骤的实现。
    pub fn step(&self, step_type: &str) -> Option<StepSpec> {
        self.steps
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .get(step_type)
            .cloned()
    }

    /// 取一个工作流模板。
    pub fn flow(&self, name: &str) -> Option<FlowTemplate> {
        self.flows
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .get(name)
            .cloned()
    }

    /// 工作流清单（`task.flows` 的载荷）：展示名字、标题与步骤概览，
    /// **不含** build 函数。生产 daemon 里没人注册时就是空列表。
    pub fn flows_summary(&self) -> Vec<Value> {
        let flows = self.flows.lock().unwrap_or_else(|e| e.into_inner());
        flows
            .iter()
            .map(|(name, tpl)| {
                serde_json::json!({
                    "name": name,
                    "title": tpl.title,
                    "steps": tpl.steps,
                })
            })
            .collect()
    }
}

/// 取这次运行的注册表；还没有就建一个放进去。**业务模块注册步骤时用这个**。
///
/// 注册表挂在 `AppState` 的跨模块句柄槽上（见 [`crate::services`]），
/// **每个 `AppState` 一份** —— 生产形态下只有一份，与「进程级全局」等价；
/// 集成测试一个进程起多个 harness 时各自一份，不会互相串。
///
/// 用 `get_or_init` 而不是「task 模块起来时挂」：模块注册步骤的时机是各自的
/// `start()`，而启动顺序由模块表决定（`mcserver` 就排在 `task` 前面）——
/// 谁先要谁负责建，task 起来时直接采用已经放好的那一份。
pub fn registry(app: &AppState) -> Arc<FlowRegistry> {
    app.services.get_or_init(FlowRegistry::new)
}

/// 取注册表；这次运行里还没人建过就是 `None`（只读场景用，不想顺手建一个空表）。
pub fn registry_if_ready(app: &AppState) -> Option<Arc<FlowRegistry>> {
    app.services.get::<FlowRegistry>()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    /// 最小步骤实现：直接成功，output 回显 step_type。
    fn echo_step() -> StepSpec {
        StepSpec {
            title: "回显".into(),
            run: Arc::new(|step, _progress, _env| {
                Box::pin(
                    async move { Ok(json!({ "step_type": step.step_type.unwrap_or_default() })) },
                )
            }),
            rollback: None,
        }
    }

    #[test]
    fn register_and_lookup() {
        let reg = FlowRegistry::new();
        reg.register_step("test.echo", echo_step()).unwrap();
        assert!(reg.step("test.echo").is_some());
        assert!(reg.step("test.missing").is_none());
    }

    #[test]
    fn duplicate_step_is_rejected() {
        let reg = FlowRegistry::new();
        reg.register_step("test.echo", echo_step()).unwrap();
        assert!(reg.register_step("test.echo", echo_step()).is_err());
    }

    #[test]
    fn duplicate_flow_is_rejected() {
        let reg = FlowRegistry::new();
        let tpl = FlowTemplate {
            title: "测试".into(),
            steps: vec![FlowStepInfo {
                name: "a".into(),
                title: "甲".into(),
                step_type: "test.echo".into(),
            }],
            build: Arc::new(|_| {
                let mut flow = FlowDef::new("test", szal::flow::FlowMode::Sequential);
                flow.add_step(StepDef::new("a").with_step_type("test.echo"));
                Ok(flow)
            }),
        };
        reg.register_flow("test.demo", tpl.clone()).unwrap();
        assert!(reg.register_flow("test.demo", tpl).is_err());
    }

    #[test]
    fn flows_summary_shape() {
        let reg = FlowRegistry::new();
        reg.register_flow(
            "test.demo",
            FlowTemplate {
                title: "演示".into(),
                steps: vec![FlowStepInfo {
                    name: "a".into(),
                    title: "甲".into(),
                    step_type: "test.echo".into(),
                }],
                build: Arc::new(|_| {
                    Ok(FlowDef::new("test.demo", szal::flow::FlowMode::Sequential))
                }),
            },
        )
        .unwrap();
        let summary = reg.flows_summary();
        assert_eq!(summary.len(), 1);
        assert_eq!(summary[0]["name"], json!("test.demo"));
        assert_eq!(summary[0]["steps"][0]["step_type"], json!("test.echo"));
    }
}
