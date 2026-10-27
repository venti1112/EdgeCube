//! FRP 映射隧道模块：平台登录 + 配置生成 / 保存。
//!
//! # 为什么登录在 daemon 而不是 App
//!
//! 若登录请求、轮询、令牌落盘全在 App 进程里，App 一关授权就断了。
//! 所以全部放进 daemon：后端发起授权、后端轮询、后端把令牌写进
//! `<data_dir>/config/frp/auth.json`（0600），App 只做「显示 + 收集用户输入」——
//! 拿到授权地址开浏览器、把用户在浏览器里做完的事的结果等回来
//! （`frp.login` 事件 / `frp.login.status`）。
//!
//! # 没做的部分
//!
//! frpc 的下载与启动（用户明确暂不做）。所以配置只生成到
//! `config/frp/toml/<localId>.toml` 为止：只做「生成 + 落盘」这一段，
//! 拼命令行 / 拉进程留给以后。
//!
//! # 方法
//!
//! | 方法 | 说明 |
//! | --- | --- |
//! | `frp.providers` | 平台清单（含登录方式） |
//! | `frp.account` | 某平台的登录态（`verify` 时联网复核） |
//! | `frp.login.start` | 发起浏览器授权，返回授权地址 |
//! | `frp.login.status` | 当前授权进度（daemon 侧在轮询） |
//! | `frp.login.cancel` | 取消授权 |
//! | `frp.login.token` | 用粘贴的令牌登录（Sakura / ME） |
//! | `frp.logout` | 退出登录（清令牌） |
//! | `frp.remote.tunnels` | 平台侧隧道列表 |
//! | `frp.remote.nodes` | 平台侧节点列表 |
//! | `frp.remote.create` | 在平台上创建隧道 |
//! | `frp.remote.delete` | 删除平台上的隧道 |
//! | `frp.tunnels.list` | 本地已保存的隧道 |
//! | `frp.tunnels.save` | 保存 / 更新一条隧道（自定义隧道顺带生成 TOML） |
//! | `frp.tunnels.config` | 生成并落盘该隧道的 frpc 配置 |
//! | `frp.tunnels.remove` | 删除本地隧道（元数据 + TOML） |
//!
//! 事件主题 `frp.login`：授权状态变化（`waiting` / `success` / `error`）。

pub mod api;
pub mod builder;
pub mod login;
pub mod model;
pub mod run;
pub mod store;

use std::path::{Path, PathBuf};
use std::sync::{Arc, OnceLock};

use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use self::api::{ApiError, CreateTunnelReq};
use self::login::{LoginSessions, TOPIC_LOGIN};
use self::model::{ALL_PROVIDERS, Account, Provider, SavedTunnel, TunnelInput};
use self::run::FrpRunManager;
use self::store::{FrpSettings, FrpStore};
use crate::error::{Result, RpcError, RpcResult};
use crate::module::{CallCtx, Module, ModuleDescriptor, ModuleEnv, Registration, ok};
use crate::state::AppState;

/// 错误码：本地没这条隧道。
const TUNNEL_NOT_FOUND: &str = "frp_tunnel_not_found";
/// 错误码：平台上找不到指定节点。
const NODE_NOT_FOUND: &str = "frp_node_not_found";

// ══════════════════════════════════════════════════════════════════════════
// 模块配置
// ══════════════════════════════════════════════════════════════════════════

/// `[modules.config.frp]`
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct FrpModuleConfig {
    /// 数据根目录。留空 = 平台默认（与实例模块同一套回退规则）。
    ///
    /// 隧道数据落在它下面的 `config/frp/`：元数据
    /// `config/frp/config/<localId>.json`、令牌 `config/frp/auth.json`、
    /// 生成的配置 `config/frp/toml/<localId>.toml`。
    pub dir: String,
}

/// FRP 的数据根（`<data_dir>`）。
///
/// 自己的 `dir` 优先；**留空时跟实例模块同一个根**，而不是各自回退到平台默认。
/// 后者会出这种事：用户把实例数据搬到 `/data/xyz`（数据根搬家），实例在
/// `/data/xyz/instances`、运行环境在 `/data/xyz/config/runtimes`，
/// 而 frp 却去平台默认目录找一个空壳 —— 症状是「frpc 明明装了，隧道却说没装」。
/// 「EdgeCube 的数据放哪」只该有一个答案（同 `instance::resolve_data_dir` 的说明）。
pub fn data_dir_of(app: &AppState) -> PathBuf {
    let dir = app
        .config
        .modules
        .section("frp")
        .and_then(|value| FrpModuleConfig::deserialize(value.clone()).ok())
        .map(|config| config.dir)
        .unwrap_or_default();
    resolve_data_dir(&dir, app.config.modules.section("instance"))
}

/// [`data_dir_of`] 里不碰 `AppState` 的那一半（所以能单测）。
fn resolve_data_dir(dir: &str, instance_section: Option<&toml::Value>) -> PathBuf {
    let trimmed = dir.trim();
    if !trimmed.is_empty() {
        return PathBuf::from(trimmed);
    }
    super::instance::resolve_data_dir(instance_section)
}

/// FRP 的落盘根：`<data_dir>/config/frp`。
///
/// HTTP 与进程内入口都拿不到 `CallCtx`，只能从 `AppState` 现算 —— 所以这两条
/// 路径与模块方法用的是**同一个函数**，不会各算一套然后漂移。
pub fn store_of(app: &AppState) -> FrpStore {
    FrpStore::new(data_dir_of(app).join("config").join("frp"))
}

/// 进程表的进程内入口。
///
/// **谁先用到谁建**（`get_or_init`）：模块启动顺序不该决定「进程表在不在」——
/// `instance` 的「连带启动」要在自己的请求里拿到它，而 `instance` 模块比
/// `frp` 先启动。
pub fn runs_of(app: &AppState) -> Arc<FrpRunManager> {
    app.services
        .get_or_init(|| FrpRunManager::new(app.bus.clone()))
}

// ══════════════════════════════════════════════════════════════════════════
// 模块状态
// ══════════════════════════════════════════════════════════════════════════

/// 已解析好的「存储 + 登录会话」。
///
/// 与实例模块同一套路：`register()` 阶段拿不到模块配置（要等 `start()`），
/// 所以做成惰性解析 —— `start()` 里定下来，被调用时再用。
#[derive(Clone)]
struct Resolved {
    store: FrpStore,
    /// 登录会话表。全局唯一那份 —— 轮询任务、事件推送都从它走。
    sessions: Arc<LoginSessions>,
    /// FRP 实例的进程表（键是隧道的 `local_id`）。
    ///
    /// 走 `Services`（每个 `AppState` 一份）：`instance` 的「连带启动」也要
    /// 拿到同一张表，而它拿不到 frp 的模块实例。做成进程级 `static` 会让
    /// 集成测试里的第二个 harness 拿到第一个的句柄（见 `services` 的说明）。
    runs: Arc<FrpRunManager>,
    /// 数据根（找 frpc 可执行文件用）。
    data_dir: PathBuf,
}

impl Resolved {
    fn new(_config: FrpModuleConfig, app: AppState) -> Self {
        // 目录一律走 `data_dir_of`（它才是「数据放哪」的唯一答案），
        // 模块配置这一节目前只有 `dir` 一项，已经被它吃掉了。
        let data_dir = data_dir_of(&app);
        let store = store_of(&app);
        let sessions = Arc::new(LoginSessions::new(store.clone(), app.clone()));
        let runs = runs_of(&app);
        Self {
            store,
            sessions,
            runs,
            data_dir,
        }
    }
}

struct FrpState {
    resolved: OnceLock<Resolved>,
}

impl FrpState {
    fn new() -> Self {
        Self {
            resolved: OnceLock::new(),
        }
    }

    /// 取已解析的状态；还没初始化就用传入的配置初始化一次。
    fn resolved(&self, fallback: Option<(FrpModuleConfig, AppState)>) -> RpcResult<Resolved> {
        if let Some(resolved) = self.resolved.get() {
            return Ok(resolved.clone());
        }
        let (config, app) = fallback
            .ok_or_else(|| RpcError::unavailable("FRP 模块尚未初始化（模块配置读取失败）"))?;
        let resolved = Resolved::new(config, app);
        // 另一个调用抢先设置也无所谓，值是一样的
        let _ = self.resolved.set(resolved);
        self.resolved
            .get()
            .cloned()
            .ok_or_else(|| RpcError::internal("FRP 模块初始化失败"))
    }
}

/// 一条隧道跑起来需要的东西（[`tunnel_config`] 的返回）。
pub struct TunnelConfig {
    /// 隧道显示名（日志与状态里用）。
    pub name: String,
    /// frpc 配置文件的绝对路径。
    pub path: PathBuf,
}

/// 进程内入口：按本地隧道 id 拿「隧道名 + frpc 配置文件路径」。
///
/// **给实例模块的「随实例启动」用**：实例那边只有 `AppState`，拿不到 frp 的
/// 模块实例，所以「隧道存在吗、配置写好了吗」这两件事在这里收口 ——
/// store 与 builder 都与 `frp.tunnels.config` 用的是同一套，不会出现
/// 「界面上能看到配置、跑起来找不到文件」。
///
/// * `Ok(None)` —— 隧道不存在（用户在别处删了）；
/// * `Err(reason)` —— 生成失败（没登录、平台接口出错），原因给人看。
pub async fn tunnel_config(
    app: &AppState,
    local_id: &str,
) -> std::result::Result<Option<TunnelConfig>, String> {
    let store = store_of(app);

    let Some(tunnel) = store.tunnel(local_id) else {
        return Ok(None);
    };

    // 磁盘上有就先用着（与 `frp.tunnels.config` 的非 refresh 分支一致）；
    // 没有就现生成一份写下去 —— 用户可能从没打开过那条隧道的详情页。
    if store.read_toml(local_id).is_none() {
        let content = builder::build(&store, &tunnel)
            .await
            .map_err(|e| format!("生成隧道配置失败：{e}"))?;
        store
            .write_toml(local_id, &content)
            .map_err(|e| format!("写隧道配置失败：{e}"))?;
    }

    let path = store
        .toml_path(local_id)
        .map_err(|e| format!("算配置路径失败：{e}"))?;
    Ok(Some(TunnelConfig {
        name: tunnel.name,
        path,
    }))
}

/// 起一条隧道：选 frpc 环境 → 拿隧道配置 → 起进程。
///
/// **`frp.run.start` 与游戏实例的「连带启动」共用这一条** —— 拆成两份的话，
/// 「界面上点得起来、连带启动起不来」这类分叉迟早会出现。
///
/// 选哪个 frpc：设置里选的那个；没选过就挑第一个装好的（省掉「装完还得先
/// 去选一次」）。一个都没装 → [`FrpStartError::RuntimeMissing`]。
pub async fn spawn_tunnel(
    app: &AppState,
    store: &FrpStore,
    data_dir: &Path,
    runs: &FrpRunManager,
    local_id: &str,
) -> std::result::Result<Arc<run::FrpRun>, run::FrpStartError> {
    let settings = store.read_settings();
    let runtimes = run::frpc_runtimes(data_dir);
    let chosen = settings
        .frpc_runtime_id
        .as_deref()
        .and_then(|id| runtimes.iter().find(|r| r.id == id))
        .or_else(|| runtimes.first())
        .ok_or_else(|| {
            run::FrpStartError::RuntimeMissing(
                settings
                    .frpc_runtime_id
                    .clone()
                    .unwrap_or_else(|| "frpc".to_string()),
            )
        })?;

    // 选中的那个记下来了、但环境被删了：**退回第一个装好的**而不是报错。
    // 用户删环境时不会想到「某条隧道还指着它」，这里报错等于隧道莫名起不来。
    if let Some(wanted) = settings.frpc_runtime_id.as_deref()
        && wanted != chosen.id
    {
        tracing::warn!(wanted, using = %chosen.id, "选中的 frpc 环境不在了，改用这个");
    }

    // 隧道要存在、配置要在（缺了现生成一份 —— 用户可能从没打开过详情页）
    let tunnel = tunnel_config(app, local_id)
        .await
        .map_err(run::FrpStartError::Tunnel)?
        .ok_or_else(|| {
            run::FrpStartError::Tunnel(format!("隧道 `{local_id}` 不在了（可能被删掉了）"))
        })?;

    run::start(
        local_id,
        chosen.binary.clone(),
        &chosen.id,
        &tunnel.name,
        tunnel.path,
        runs,
    )
}

/// 进程内入口：把一条隧道拉起来（游戏实例的「连带启动」用）。
///
/// * `Ok(run)` —— 起来了，或者**本来就在跑**（一条隧道同时只有一个进程，
///   所以多条游戏实例连带同一条隧道是安全的）；
/// * `Err(reason)` —— 起不来。调用方**不需要**再报错：原因已经作为一条
///   `failed` 记录留在进程表里，「网络映射 → 管理隧道」里看得见。
pub async fn start_tunnel(
    app: &AppState,
    local_id: &str,
) -> std::result::Result<Arc<run::FrpRun>, String> {
    let runs = runs_of(app);
    // 已经在跑就到此为止：后面的解析会要求隧道还在，而用户可能只是删了
    // 元数据、进程还好好的 —— 那种情况不该把跑着的隧道算成失败。
    if let Some(running) = runs.get(local_id).filter(|r| r.alive()) {
        return Ok(running);
    }
    let store = store_of(app);
    let data_dir = data_dir_of(app);

    match spawn_tunnel(app, &store, &data_dir, &runs, local_id).await {
        Ok(run) => Ok(run),
        Err(error) => {
            let message = error.message();
            run::record_failure(
                local_id,
                None,
                &store
                    .tunnel(local_id)
                    .map(|t| t.name)
                    .unwrap_or_else(|| local_id.to_string()),
                message.clone(),
                &runs,
            );
            Err(message)
        }
    }
}

/// 从 `CallCtx` 取模块配置并解析状态（方法处理器里反复用到）。
fn resolve_for(state: &Arc<FrpState>, ctx: &CallCtx) -> RpcResult<Resolved> {
    let config = ctx.module_config::<FrpModuleConfig>().ok();
    state.resolved(config.map(|config| (config, ctx.app.clone())))
}

/// 把同步的磁盘操作丢到阻塞线程池，别卡住 tokio 的工作线程。
async fn blocking<T, F>(f: F) -> RpcResult<T>
where
    F: FnOnce() -> RpcResult<T> + Send + 'static,
    T: Send + 'static,
{
    match tokio::task::spawn_blocking(f).await {
        Ok(result) => result,
        Err(join) => Err(RpcError::internal(format!(
            "FRP 操作的后台任务失败: {join}"
        ))),
    }
}

// ══════════════════════════════════════════════════════════════════════════
// 处理逻辑（同步部分单独拎出来，测试直接打这些函数，不起 WS）
// ══════════════════════════════════════════════════════════════════════════

/// 平台清单。
fn providers_json() -> Value {
    let providers: Vec<Value> = ALL_PROVIDERS
        .into_iter()
        .map(|provider| {
            json!({
                "key": provider.key(),
                "name": provider.display_name(),
                "requires_login": provider.requires_login(),
                "browser_login": provider.supports_browser_login(),
                "token_login": provider.supports_token_login(),
            })
        })
        .collect();
    json!({ "providers": providers })
}

/// 缓存的登录态（`frp.account` 不联网时的返回体）。
///
/// `account` 只在缓存里有非空用户名时给：供应商选择页靠
/// 「token 非空 **且** 账号名非空」决定是否跳过登录页。
fn cached_account_json(store: &FrpStore, provider: Provider) -> Value {
    let token = store.token(provider).unwrap_or_default();
    let account = store.account(provider).filter(|a| !a.username.is_empty());
    json!({
        "provider": provider,
        "logged_in": !token.trim().is_empty(),
        "account": account.as_ref().map(Account::public_json),
    })
}

/// 本地已保存隧道。
fn list_tunnels_json(store: &FrpStore) -> Value {
    let tunnels: Vec<Value> = store
        .load_tunnels()
        .iter()
        .map(|tunnel| tunnel.to_wire_json(store.toml_exists(&tunnel.local_id)))
        .collect();
    let count = tunnels.len();
    json!({
        "tunnels": tunnels,
        "count": count,
        "data_dir": store.root().display().to_string(),
    })
}

/// 保存（新增或更新）一条隧道，返回落盘后的模型。
///
/// 自定义隧道的校验：简易表单要「名称 + 服务器地址 + 三个端口」，
/// 粘贴模式要配置非空 —— 提示语是固定的两句文案。
fn save_tunnel(store: &FrpStore, input: TunnelInput) -> RpcResult<SavedTunnel> {
    if input.provider == Provider::Custom {
        validate_custom(&input)?;
    }
    let local_id = match input.local_id.as_deref() {
        Some(id) if FrpStore::is_valid_local_id(id) => id.to_string(),
        Some(id) if !id.trim().is_empty() => {
            return Err(RpcError::invalid_params(format!("非法的隧道 id `{id}`")));
        }
        // 空 / 缺省 = 新建（生成新的 localId）
        _ => store.new_local_id(),
    };
    let tunnel = input.into_tunnel(local_id);
    store
        .upsert_tunnel(&tunnel)
        .map_err(|e| RpcError::internal(format!("保存隧道失败：{e}")))?;
    Ok(tunnel)
}

/// 自定义隧道保存前的两条前置校验。
fn validate_custom(input: &TunnelInput) -> RpcResult<()> {
    if let Some(form) = &input.custom_form {
        if input.name.trim().is_empty()
            || form.server_addr.trim().is_empty()
            || form.server_port.is_none()
            || form.local_port.is_none()
            || form.remote_port.is_none()
        {
            return Err(RpcError::new("invalid_params", "请完整填写隧道名称与端口"));
        }
        return Ok(());
    }
    if input.custom_toml.as_deref().unwrap_or("").trim().is_empty() {
        return Err(RpcError::new("invalid_params", "配置内容不能为空"));
    }
    Ok(())
}

/// 生成并落盘某条隧道的 frpc 配置，返回 `(配置文本, 文件路径)`。
async fn generate_config(
    store: &FrpStore,
    tunnel: &SavedTunnel,
) -> Result<(String, String), RpcError> {
    let config = builder::build(store, tunnel).await?;
    let store = store.clone();
    let id = tunnel.local_id.clone();
    let body = config.clone();
    let path = blocking(move || {
        store
            .write_toml(&id, &body)
            .map(|path| path.display().to_string())
            .map_err(|e| RpcError::internal(format!("写入配置失败：{e}")))
    })
    .await?;
    Ok((config, path))
}

/// 取一条本地隧道，不在就报 `frp_tunnel_not_found`。
fn require_tunnel(store: &FrpStore, local_id: &str) -> RpcResult<SavedTunnel> {
    store.tunnel(local_id).ok_or_else(|| {
        RpcError::new(
            TUNNEL_NOT_FOUND,
            format!("本地没有隧道 `{local_id}`（可能已被删除）"),
        )
    })
}

/// 创建隧道时校验必填项（名称与两个端口）。
fn require_create_fields(
    name: &str,
    local_port: Option<u32>,
    remote_port: Option<u32>,
) -> RpcResult<()> {
    if name.trim().is_empty() || local_port.is_none() || remote_port.is_none() {
        return Err(RpcError::new("invalid_params", "请完整填写隧道名称与端口"));
    }
    Ok(())
}

// ══════════════════════════════════════════════════════════════════════════
// 模块本体
// ══════════════════════════════════════════════════════════════════════════

pub struct FrpModule {
    state: Arc<FrpState>,
}

impl FrpModule {
    pub fn new() -> Self {
        Self {
            state: Arc::new(FrpState::new()),
        }
    }
}

impl Default for FrpModule {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl Module for FrpModule {
    fn descriptor(&self) -> ModuleDescriptor {
        ModuleDescriptor::new("frp", "映射隧道", env!("CARGO_PKG_VERSION"))
            .description("FRP 内网穿透：平台登录（后端轮询 + 令牌落盘）与 frpc 配置生成 / 保存；配置好的隧道由 instance 随实例启停。")
    }

    fn register(&self, reg: &mut Registration) -> Result<()> {
        reg.topic(
            TOPIC_LOGIN,
            "浏览器授权登录的进度变了（等待 / 成功 / 失败）",
        );
        reg.topic(
            run::TOPIC_RUN,
            "某条隧道的运行态变了（起了 / 退出了 / 起不来）",
        );

        // ── 平台与登录态 ──

        reg.method(
            "frp.providers",
            "映射平台清单（含登录方式）",
            |_ctx| async move { ok(providers_json()) },
        );

        {
            let module = self.state.clone();
            reg.method(
                "frp.account",
                "某平台的登录态（verify=true 时联网复核令牌）",
                move |ctx| {
                    let module = module.clone();
                    async move {
                        let resolved = resolve_for(&module, &ctx)?;
                        let provider: Provider = ctx.param("provider")?;
                        let verify: bool = ctx.param_or("verify", false)?;
                        let store = resolved.store.clone();
                        if !verify {
                            return blocking(move || Ok(cached_account_json(&store, provider)))
                                .await;
                        }
                        // 联网复核（自动登录）：成功刷新账号缓存，
                        // 失败（含网络错误）一律清令牌回登录表单。
                        match api::user_info(&store, provider).await {
                            Ok(account) => {
                                let token = store.token(provider).unwrap_or_default();
                                let cached = account.clone();
                                api::store_op(&store, move |store| {
                                    store.save_token(provider, &token, &cached).map_err(|e| {
                                        ApiError::internal(format!("保存账号失败：{e}"))
                                    })
                                })
                                .await?;
                                ok(json!({
                                    "provider": provider,
                                    "logged_in": true,
                                    "account": account.public_json(),
                                }))
                            }
                            Err(e) => {
                                tracing::debug!(
                                    provider = provider.key(),
                                    error = %e,
                                    "自动登录复核失败，清除本地令牌"
                                );
                                let _ = api::store_op(&store, move |store| {
                                    store.clear_token(provider).map_err(|e| {
                                        ApiError::internal(format!("清除令牌失败：{e}"))
                                    })
                                })
                                .await;
                                ok(json!({
                                    "provider": provider,
                                    "logged_in": false,
                                    "account": null,
                                }))
                            }
                        }
                    }
                },
            );
        }

        // ── 浏览器授权登录 ──

        {
            let module = self.state.clone();
            reg.method(
                "frp.login.start",
                "发起浏览器授权登录（轮询在 daemon 侧跑）",
                move |ctx| {
                    let module = module.clone();
                    async move {
                        let resolved = resolve_for(&module, &ctx)?;
                        let provider: Provider = ctx.param("provider")?;
                        let snapshot = resolved.sessions.start(provider).await?;
                        ok(snapshot)
                    }
                },
            );
        }

        {
            let module = self.state.clone();
            reg.method(
                "frp.login.status",
                "当前授权进度（没有会话时是 idle）",
                move |ctx| {
                    let module = module.clone();
                    async move {
                        let resolved = resolve_for(&module, &ctx)?;
                        let provider: Provider = ctx.param("provider")?;
                        ok(resolved.sessions.status_json(provider))
                    }
                },
            );
        }

        {
            let module = self.state.clone();
            reg.method("frp.login.cancel", "取消授权登录", move |ctx| {
                let module = module.clone();
                async move {
                    let resolved = resolve_for(&module, &ctx)?;
                    let provider: Provider = ctx.param("provider")?;
                    ok(json!({ "cancelled": resolved.sessions.cancel(provider) }))
                }
            });
        }

        {
            let module = self.state.clone();
            reg.method(
                "frp.login.token",
                "用粘贴的访问令牌登录（Sakura / ME Frp）",
                move |ctx| {
                    let module = module.clone();
                    async move {
                        let resolved = resolve_for(&module, &ctx)?;
                        let provider: Provider = ctx.param("provider")?;
                        let token: String = ctx.param("token")?;
                        if token.trim().is_empty() {
                            return Err(RpcError::invalid_params("请输入访问 Token"));
                        }
                        let account = resolved
                            .sessions
                            .login_with_token(provider, token.trim())
                            .await?;
                        ok(json!({
                            "provider": provider,
                            "logged_in": true,
                            "account": account,
                        }))
                    }
                },
            );
        }

        {
            let module = self.state.clone();
            reg.method(
                "frp.logout",
                "退出登录（清除本地令牌）",
                move |ctx| {
                    let module = module.clone();
                    async move {
                        let resolved = resolve_for(&module, &ctx)?;
                        let provider: Provider = ctx.param("provider")?;
                        resolved.sessions.logout(provider).await?;
                        ok(json!({ "ok": true }))
                    }
                },
            );
        }

        // ── 平台侧隧道 ──

        {
            let module = self.state.clone();
            reg.method("frp.remote.tunnels", "平台侧隧道列表", move |ctx| {
                let module = module.clone();
                async move {
                    let resolved = resolve_for(&module, &ctx)?;
                    let provider: Provider = ctx.param("provider")?;
                    let tunnels = api::tunnel_list(&resolved.store, provider).await?;
                    ok(json!({ "tunnels": tunnels }))
                }
            });
        }

        {
            let module = self.state.clone();
            reg.method("frp.remote.nodes", "平台侧节点列表", move |ctx| {
                let module = module.clone();
                async move {
                    let resolved = resolve_for(&module, &ctx)?;
                    let provider: Provider = ctx.param("provider")?;
                    let nodes = api::node_list(&resolved.store, provider).await?;
                    ok(json!({ "nodes": nodes }))
                }
            });
        }

        {
            let module = self.state.clone();
            reg.method("frp.remote.create", "在平台上创建隧道", move |ctx| {
                let module = module.clone();
                async move {
                    let resolved = resolve_for(&module, &ctx)?;
                    let provider: Provider = ctx.param("provider")?;
                    let node_id: String = ctx.param("node_id")?;
                    let name: String = ctx.param("name")?;
                    let kind: String = ctx.param_or("type", "tcp".to_string())?;
                    let local_ip: String = ctx.param_or("local_ip", "127.0.0.1".to_string())?;
                    let local_port: Option<u32> = ctx.optional("local_port")?;
                    let remote_port: Option<u32> = ctx.optional("remote_port")?;
                    require_create_fields(&name, local_port, remote_port)?;

                    // 节点从平台列表里取：前端只发表单，节点详情不该由它拼。
                    let nodes = api::node_list(&resolved.store, provider).await?;
                    let node = nodes
                        .into_iter()
                        .find(|node| node.id == node_id)
                        .ok_or_else(|| {
                            RpcError::new(
                                NODE_NOT_FOUND,
                                format!("节点不存在或已下线（id={node_id}）"),
                            )
                        })?;
                    let req = CreateTunnelReq {
                        node,
                        name,
                        kind,
                        local_ip,
                        local_port: local_port.unwrap_or(25565),
                        remote_port: remote_port.unwrap_or(0),
                    };
                    api::create_tunnel(&resolved.store, provider, &req).await?;
                    ok(json!({ "ok": true }))
                }
            });
        }

        {
            let module = self.state.clone();
            reg.method("frp.remote.delete", "删除平台上的隧道", move |ctx| {
                let module = module.clone();
                async move {
                    let resolved = resolve_for(&module, &ctx)?;
                    let provider: Provider = ctx.param("provider")?;
                    let remote_tunnel_id: String = ctx.param("remote_tunnel_id")?;
                    if remote_tunnel_id.trim().is_empty() {
                        return Err(RpcError::invalid_params("缺少远端隧道 ID"));
                    }
                    api::delete_tunnel(&resolved.store, provider, remote_tunnel_id.trim()).await?;
                    ok(json!({ "ok": true }))
                }
            });
        }

        // ── 本地已保存隧道 ──

        {
            let module = self.state.clone();
            reg.method(
                "frp.tunnels.list",
                "本地已保存的映射隧道",
                move |ctx| {
                    let module = module.clone();
                    async move {
                        let resolved = resolve_for(&module, &ctx)?;
                        let store = resolved.store.clone();
                        blocking(move || Ok(list_tunnels_json(&store))).await
                    }
                },
            );
        }

        {
            let module = self.state.clone();
            reg.method(
                "frp.tunnels.save",
                "保存 / 更新一条隧道（自定义隧道顺带生成 TOML）",
                move |ctx| {
                    let module = module.clone();
                    async move {
                        let resolved = resolve_for(&module, &ctx)?;
                        let input: TunnelInput = serde_json::from_value(ctx.params.clone())
                            .map_err(|e| {
                                RpcError::invalid_params(format!("隧道参数不合法：{e}"))
                            })?;
                        let store = resolved.store.clone();
                        let tunnel = blocking(move || save_tunnel(&store, input)).await?;

                        // 自定义隧道的配置在保存时就能生成（不联网，纯拼文本）：
                        // 顺手写盘，让「保存完就有配置」成立。别的平台要联网拉，
                        // 留给 `frp.tunnels.config`。
                        let mut config_error: Option<String> = None;
                        if tunnel.provider == Provider::Custom
                            && let Err(e) = generate_config(&resolved.store, &tunnel).await
                        {
                            config_error = Some(e.message);
                        }
                        let store = resolved.store.clone();
                        let local_id = tunnel.local_id.clone();
                        let exists = blocking(move || Ok(store.toml_exists(&local_id))).await?;
                        let mut body = json!({ "tunnel": tunnel.to_wire_json(exists) });
                        if let Some(message) = config_error {
                            body["config_error"] = json!(message);
                        }
                        ok(body)
                    }
                },
            );
        }

        {
            let module = self.state.clone();
            reg.method(
                "frp.tunnels.config",
                "生成 / 读取隧道的 frpc 配置（refresh=true 强制重新生成）",
                move |ctx| {
                    let module = module.clone();
                    async move {
                        let resolved = resolve_for(&module, &ctx)?;
                        let local_id: String = ctx.param("local_id")?;
                        let refresh: bool = ctx.param_or("refresh", false)?;
                        let store = resolved.store.clone();

                        if !refresh {
                            let id = local_id.clone();
                            let store2 = store.clone();
                            if let Some(config) =
                                blocking(move || Ok(store2.read_toml(&id))).await?
                            {
                                let path = store
                                    .toml_path(&local_id)
                                    .map(|p| p.display().to_string())
                                    .unwrap_or_default();
                                return ok(json!({
                                    "config": config,
                                    "path": path,
                                    "generated": false,
                                }));
                            }
                        }

                        let tunnel = require_tunnel(&store, &local_id)?;
                        let (config, path) = generate_config(&store, &tunnel).await?;
                        ok(json!({ "config": config, "path": path, "generated": true }))
                    }
                },
            );
        }

        {
            let module = self.state.clone();
            reg.method(
                "frp.tunnels.remove",
                "删除本地隧道（元数据 + 配置一并删）",
                move |ctx| {
                    let module = module.clone();
                    async move {
                        let resolved = resolve_for(&module, &ctx)?;
                        let local_id: String = ctx.param("local_id")?;
                        let store = resolved.store.clone();
                        blocking(move || {
                            if !FrpStore::is_valid_local_id(&local_id) {
                                return Err(RpcError::invalid_params(format!(
                                    "非法的隧道 id `{local_id}`"
                                )));
                            }
                            store
                                .remove_tunnel(&local_id)
                                .map_err(|e| RpcError::internal(format!("删除隧道失败：{e}")))?;
                            Ok(json!({ "ok": true }))
                        })
                        .await
                    }
                },
            );
        }

        // ── FRP 实例的运行 ──
        //
        // 上面那一大段是**配置**（登录平台、把隧道存下来、生成 toml），这里才是
        // **运行**：一条隧道配置 = 一个可独立运行的 FRP 实例，同时只有一个进程。
        // 游戏实例的「连带启动」走的是同一个 `spawn_tunnel`，所以
        // 「界面上点得起来、连带启动起不来」这类分叉不会出现。
        {
            let module = self.state.clone();
            reg.method(
                "frp.runtimes",
                "能拿来跑隧道的 frpc 运行环境（已装好的）+ 当前选中的那个",
                move |ctx| {
                    let module = module.clone();
                    async move {
                        let resolved = resolve_for(&module, &ctx)?;
                        let data_dir = resolved.data_dir.clone();
                        let store = resolved.store.clone();
                        blocking(move || {
                            let settings = store.read_settings();
                            let runtimes: Vec<Value> = run::frpc_runtimes(&data_dir)
                                .iter()
                                .map(run::FrpcRuntime::to_wire)
                                .collect();
                            // 选中项回显「生效的那个」：设置里没选过（或选的那个
                            // 不在了）时就是第一个 —— 前端不必自己猜
                            let selected = settings
                                .frpc_runtime_id
                                .filter(|id| runtimes.iter().any(|r| r["id"] == json!(id)))
                                .or_else(|| {
                                    runtimes
                                        .first()
                                        .and_then(|r| r["id"].as_str().map(str::to_string))
                                });
                            Ok(json!({ "runtimes": runtimes, "selected": selected }))
                        })
                        .await
                    }
                },
            );
        }
        {
            let module = self.state.clone();
            reg.method(
                "frp.settings.save",
                "记下跑隧道用哪个 frpc 运行环境",
                move |ctx| {
                    let module = module.clone();
                    async move {
                        let resolved = resolve_for(&module, &ctx)?;
                        let runtime_id: Option<String> = ctx.param_or("frpc_runtime_id", None)?;
                        let store = resolved.store.clone();
                        blocking(move || {
                            let next = FrpSettings {
                                frpc_runtime_id: runtime_id
                                    .map(|text| text.trim().to_string())
                                    .filter(|text| !text.is_empty()),
                            };
                            store
                                .write_settings(&next)
                                .map_err(|e| RpcError::internal(format!("写 FRP 设置失败：{e}")))?;
                            Ok(json!({ "frpc_runtime_id": next.frpc_runtime_id }))
                        })
                        .await
                    }
                },
            );
        }
        {
            let module = self.state.clone();
            reg.method(
                "frp.run.list",
                "所有 FRP 实例的运行态（不含日志）",
                move |ctx| {
                    let module = module.clone();
                    async move {
                        let resolved = resolve_for(&module, &ctx)?;
                        let runs: Vec<Value> = resolved
                            .runs
                            .list()
                            .iter()
                            .map(|run| run.to_wire_summary())
                            .collect();
                        ok(json!({ "runs": runs }))
                    }
                },
            );
        }
        {
            let module = self.state.clone();
            reg.method(
                "frp.run.get",
                "单条隧道的运行态（含日志，给运行页）",
                move |ctx| {
                    let module = module.clone();
                    async move {
                        let resolved = resolve_for(&module, &ctx)?;
                        let local_id: String = ctx.param("local_id")?;
                        let wire = resolved
                            .runs
                            .get(&local_id)
                            .map(|run| run.to_wire())
                            .unwrap_or(Value::Null);
                        ok(json!({ "run": wire }))
                    }
                },
            );
        }
        {
            let module = self.state.clone();
            reg.method(
                "frp.run.start",
                "启动一条隧道（已经在跑就原样返回，不会起第二个）",
                move |ctx| {
                    let module = module.clone();
                    async move {
                        // 先过一遍参数合法性，再交给进程内入口 —— 那条路径是
                        // 「游戏实例连带启动」也在用的，两边行为必须一致
                        resolve_for(&module, &ctx)?;
                        let local_id: String = ctx.param("local_id")?;
                        if !FrpStore::is_valid_local_id(&local_id) {
                            return Err(RpcError::invalid_params(format!(
                                "非法的隧道 id `{local_id}`"
                            )));
                        }
                        let run = start_tunnel(&ctx.app, &local_id)
                            .await
                            .map_err(|message| RpcError::new("frp_run_failed", message))?;
                        ok(json!({ "run": run.to_wire_summary() }))
                    }
                },
            );
        }
        {
            let module = self.state.clone();
            reg.method(
                "frp.run.stop",
                "停止一条隧道（幂等）",
                move |ctx| {
                    let module = module.clone();
                    async move {
                        let resolved = resolve_for(&module, &ctx)?;
                        let local_id: String = ctx.param("local_id")?;
                        if !FrpStore::is_valid_local_id(&local_id) {
                            return Err(RpcError::invalid_params(format!(
                                "非法的隧道 id `{local_id}`"
                            )));
                        }
                        resolved.runs.stop_and_forget(&local_id).await;
                        ok(json!({ "stopped": true }))
                    }
                },
            );
        }
        {
            let module = self.state.clone();
            reg.method(
                "frp.run.clear_log",
                "清空某条隧道的运行日志",
                move |ctx| {
                    let module = module.clone();
                    async move {
                        let resolved = resolve_for(&module, &ctx)?;
                        let local_id: String = ctx.param("local_id")?;
                        if let Some(run) = resolved.runs.get(&local_id) {
                            run::clear_log(&run);
                        }
                        ok(json!({ "cleared": true }))
                    }
                },
            );
        }

        Ok(())
    }

    async fn start(&self, env: ModuleEnv) -> Result<()> {
        let config: FrpModuleConfig = env.config()?;
        let resolved = Resolved::new(config, env.app.clone());
        tracing::info!(dir = %resolved.store.root().display(), "frp 模块已加载");
        let _ = self.state.resolved.set(resolved);
        Ok(())
    }

    async fn stop(&self) -> Result<()> {
        if let Some(resolved) = self.state.resolved.get() {
            resolved.sessions.shutdown();
            // frpc 是普通管道子进程，父进程退出它们**不会**跟着走（不像 PTY 上
            // 那些会吃到 SIGHUP），所以必须显式收一遍，
            // 否则会留下一堆占着隧道的孤儿进程。
            resolved.runs.stop_all().await;
        }
        Ok(())
    }
}

// ══════════════════════════════════════════════════════════════════════════
// 测试：直接打处理逻辑（不走 WS，跑得快）
// ══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;
    use crate::util::now_ms;

    /// 一个临时数据目录 + 对应的存储；析构时清盘。
    struct TempData(PathBuf, FrpStore);

    impl TempData {
        fn new(tag: &str) -> Self {
            let root = std::env::temp_dir().join(format!(
                "edgecube-frp-mod-{tag}-{}-{}",
                std::process::id(),
                now_ms()
            ));
            std::fs::create_dir_all(&root).expect("应能建临时目录");
            let store = FrpStore::new(root.join("config").join("frp"));
            Self(root, store)
        }
    }

    impl Drop for TempData {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    fn custom_input(name: &str, local_id: Option<&str>) -> TunnelInput {
        let mut value = json!({
            "provider": "custom",
            "name": name,
            "custom_form": {
                "server_addr": "frp.example.com",
                "server_port": 7000,
                "local_port": 25565,
                "remote_port": 25566,
            },
        });
        if let Some(id) = local_id {
            value["local_id"] = json!(id);
        }
        serde_json::from_value(value).expect("入参该能解析")
    }

    /// `dir` 留空时**跟实例同一个根**，而不是各自回退到平台默认 ——
    /// 否则用户把实例数据搬走之后，frp 会去一个空目录找 frpc
    /// （症状是「frpc 明明装了，隧道却说没装」）。
    #[test]
    fn data_dir_falls_back_to_the_instance_root() {
        // 自己的 `dir` 优先
        assert_eq!(
            resolve_data_dir("/data/frp", None),
            PathBuf::from("/data/frp")
        );

        // 留空 → 实例那一节说什么就是什么
        let section: toml::Value = toml::from_str("dir = \"/data/main\"").unwrap();
        assert_eq!(
            resolve_data_dir("   ", Some(&section)),
            PathBuf::from("/data/main")
        );

        // 两边都留空 → 平台默认（不硬编码路径：它会随环境变量变）
        assert_eq!(
            resolve_data_dir("", None),
            super::super::instance::default_data_dir()
        );
    }

    #[test]
    fn providers_list_is_stable() {
        let value = providers_json();
        let providers = value["providers"].as_array().expect("该是数组");
        assert_eq!(providers.len(), ALL_PROVIDERS.len());
        let custom = providers
            .iter()
            .find(|p| p["key"] == json!("custom"))
            .expect("该有 custom");
        assert_eq!(custom["requires_login"], json!(false));
        let sakura = providers
            .iter()
            .find(|p| p["key"] == json!("sakurafrp"))
            .expect("该有 sakurafrp");
        assert_eq!(sakura["token_login"], json!(true));
        assert_eq!(sakura["browser_login"], json!(false));
    }

    #[test]
    fn custom_save_validates_inputs() {
        let data = TempData::new("validate");

        // 粘贴模式：配置为空
        let empty_raw: TunnelInput =
            serde_json::from_value(json!({"provider": "custom", "name": "x"})).unwrap();
        let err = save_tunnel(&data.1, empty_raw).unwrap_err();
        assert_eq!(err.code, "invalid_params");
        assert_eq!(err.message, "配置内容不能为空");

        // 简易表单：缺端口
        let missing_port: TunnelInput = serde_json::from_value(json!({
            "provider": "custom",
            "name": "x",
            "custom_form": {"server_addr": "frp.example.com", "server_port": 7000},
        }))
        .unwrap();
        let err = save_tunnel(&data.1, missing_port).unwrap_err();
        assert_eq!(err.message, "请完整填写隧道名称与端口");

        // 简易表单：缺名称（名称必须非空）
        let untitled: TunnelInput = serde_json::from_value(json!({
            "provider": "custom",
            "name": "  ",
            "custom_form": {
                "server_addr": "frp.example.com",
                "server_port": 7000,
                "local_port": 25565,
                "remote_port": 25566,
            },
        }))
        .unwrap();
        assert!(save_tunnel(&data.1, untitled).is_err());

        // 校验不通过不该落盘
        assert_eq!(list_tunnels_json(&data.1)["count"], json!(0));
    }

    #[test]
    fn save_then_list_round_trips() {
        let data = TempData::new("roundtrip");
        let store = &data.1;

        let tunnel = save_tunnel(store, custom_input("我的隧道", None)).unwrap();
        assert!(
            FrpStore::is_valid_local_id(&tunnel.local_id),
            "该生成 16 位 hex 的 id：{}",
            tunnel.local_id
        );
        assert_eq!(tunnel.local_port, 25565);
        assert_eq!(tunnel.remote_port, Some(25566));
        assert_eq!(tunnel.remote_address, "frp.example.com:25566");
        assert!(
            tunnel
                .custom_toml
                .contains("serverAddr = \"frp.example.com\"")
        );

        let listed = list_tunnels_json(store);
        assert_eq!(listed["count"], json!(1));
        assert_eq!(listed["tunnels"][0]["name"], json!("我的隧道"));
        assert_eq!(listed["tunnels"][0]["type"], json!("tcp"));
        assert_eq!(listed["tunnels"][0]["config_exists"], json!(false));
        assert!(listed["data_dir"].as_str().unwrap().ends_with("config/frp"));

        // 落盘一份配置后标记翻转
        store
            .write_toml(&tunnel.local_id, &tunnel.custom_toml)
            .unwrap();
        assert_eq!(
            list_tunnels_json(store)["tunnels"][0]["config_exists"],
            json!(true)
        );

        // 更新同一条：不该新增
        let updated = save_tunnel(store, custom_input("改了名字", Some(&tunnel.local_id))).unwrap();
        assert_eq!(updated.local_id, tunnel.local_id);
        assert_eq!(list_tunnels_json(store)["count"], json!(1));
        assert_eq!(
            list_tunnels_json(store)["tunnels"][0]["name"],
            json!("改了名字")
        );
    }

    #[test]
    fn illegal_local_id_is_rejected() {
        let data = TempData::new("illegal");
        let input = custom_input("越界", Some("../../etc/passwd"));
        let err = save_tunnel(&data.1, input).unwrap_err();
        assert_eq!(err.code, "invalid_params");
        assert!(err.message.contains("非法的隧道 id"));
    }

    #[test]
    fn remove_deletes_metadata_and_config() {
        let data = TempData::new("remove");
        let store = &data.1;
        let tunnel = save_tunnel(store, custom_input("待删", None)).unwrap();
        store
            .write_toml(&tunnel.local_id, &tunnel.custom_toml)
            .unwrap();

        store.remove_tunnel(&tunnel.local_id).unwrap();
        assert_eq!(list_tunnels_json(store)["count"], json!(0));
        assert!(!store.toml_exists(&tunnel.local_id), "配置该一并删掉");
    }

    #[test]
    fn missing_tunnel_reports_dedicated_code() {
        let data = TempData::new("missing");
        let err = require_tunnel(&data.1, "0123456789abcdef").unwrap_err();
        assert_eq!(err.code, TUNNEL_NOT_FOUND);
    }

    #[test]
    fn create_fields_follow_validation_rules() {
        assert!(require_create_fields("隧道", Some(25565), Some(30000)).is_ok());
        assert!(require_create_fields("", Some(25565), Some(30000)).is_err());
        assert!(require_create_fields("隧道", None, Some(30000)).is_err());
        assert!(require_create_fields("隧道", Some(25565), None).is_err());
    }

    #[test]
    fn account_view_requires_token_and_cached_username() {
        let data = TempData::new("account");
        let store = &data.1;

        let empty = cached_account_json(store, Provider::SakuraFrp);
        assert_eq!(empty["logged_in"], json!(false));
        assert_eq!(empty["account"], json!(null));

        // 只有令牌、没有账号缓存：登录态为真但 account 为空 ——
        // 供应商选择页靠这一点决定「要不要再走一次登录页」。
        store
            .save_token(Provider::SakuraFrp, "tok", &Account::default())
            .unwrap();
        let token_only = cached_account_json(store, Provider::SakuraFrp);
        assert_eq!(token_only["logged_in"], json!(true));
        assert_eq!(token_only["account"], json!(null));

        store
            .save_token(
                Provider::SakuraFrp,
                "tok",
                &Account {
                    username: "steve".into(),
                    group: "普通用户".into(),
                    ..Default::default()
                },
            )
            .unwrap();
        let logged_in = cached_account_json(store, Provider::SakuraFrp);
        assert_eq!(logged_in["account"]["username"], json!("steve"));
        assert_eq!(logged_in["account"]["group"], json!("普通用户"));
    }

    #[test]
    fn builtin_registry_exposes_frp_methods() {
        let registry = crate::module::registry::ModuleRegistry::build(
            crate::module::registry::builtin_modules(),
            &crate::config::Config::default(),
        )
        .unwrap();
        for method in [
            "frp.providers",
            "frp.account",
            "frp.login.start",
            "frp.login.status",
            "frp.login.cancel",
            "frp.login.token",
            "frp.logout",
            "frp.remote.tunnels",
            "frp.remote.nodes",
            "frp.remote.create",
            "frp.remote.delete",
            "frp.tunnels.list",
            "frp.tunnels.save",
            "frp.tunnels.config",
            "frp.tunnels.remove",
        ] {
            assert!(registry.lookup(method).is_some(), "缺少方法 {method}");
        }
        assert!(
            registry.topics().iter().any(|t| t.topic == TOPIC_LOGIN),
            "该声明 frp.login 主题"
        );
    }
}
