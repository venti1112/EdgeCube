//! 可插拔功能模块。
//!
//! # 一个模块能挂三样东西
//!
//! | 扩展点 | 注册方法 | 用途 |
//! | --- | --- | --- |
//! | HTTP 路由 | [`Registration::router`] | REST 接口、静态资源、Webhook |
//! | WS 方法 | [`Registration::method`] | 长连接上的一问一答 |
//! | 事件主题 | [`Registration::topic`] | 声明自己能推哪些事件（供客户端发现） |
//!
//! 再加生命周期钩子 [`Module::start`] / [`Module::stop`]（起后台任务、优雅收尾），
//! 以及 `[modules.config.<id>]` 私有配置节。
//!
//! # 加一个模块
//!
//! 1. 在 `src/module/builtin/` 下新建文件，实现 [`Module`]；
//! 2. 在 [`registry::builtin_modules`] 的 `vec!` 里加一行。
//!
//! 卸载一个模块 = 删掉那一行。框架侧不需要任何改动。

pub mod builtin;
pub mod registry;

use std::future::Future;
use std::sync::Arc;

use async_trait::async_trait;
use axum::Router;
use futures_util::future::BoxFuture;
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::error::{Result, RpcError, RpcResult};
use crate::state::AppState;
use crate::util::now_ms;

/// 方法可见范围。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Scope {
    /// 任何已通过鉴权、且能从网络上摸到服务的客户端都能调。
    #[default]
    Remote,
    /// 只允许来自回环地址的连接调（危险操作的兜底）。
    Local,
}

/// WS 方法处理器的统一形态：拿到调用上下文，返回未来。
pub type Handler =
    Arc<dyn Fn(CallCtx) -> BoxFuture<'static, RpcResult<Value>> + Send + Sync + 'static>;

/// 一个被注册的 WS 方法。
pub struct MethodSpec {
    /// 完整方法名，约定 `模块id.动作`，如 `ticker.start`。
    pub name: String,
    /// 所属模块 id。
    pub module: String,
    pub description: String,
    pub scope: Scope,
    pub handler: Handler,
}

impl std::fmt::Debug for MethodSpec {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("MethodSpec")
            .field("name", &self.name)
            .field("module", &self.module)
            .field("scope", &self.scope)
            .finish_non_exhaustive()
    }
}

impl MethodSpec {
    /// 对外描述（不含处理器）。
    pub fn describe(&self) -> MethodInfo {
        MethodInfo {
            name: self.name.clone(),
            module: self.module.clone(),
            description: self.description.clone(),
            scope: self.scope,
        }
    }
}

/// 方法的可序列化描述。
#[derive(Debug, Clone, Serialize)]
pub struct MethodInfo {
    pub name: String,
    pub module: String,
    pub description: String,
    pub scope: Scope,
}

/// 事件主题声明。
#[derive(Debug, Clone, Serialize)]
pub struct TopicSpec {
    pub topic: String,
    pub module: String,
    pub description: String,
}

/// 模块自述信息。
#[derive(Debug, Clone, Serialize)]
pub struct ModuleDescriptor {
    pub id: String,
    pub name: String,
    pub version: String,
    pub description: String,
    /// 常驻模块：不受 `modules.enabled` / `disabled` 影响，卸不掉。
    pub always_on: bool,
}

impl ModuleDescriptor {
    pub fn new(id: impl Into<String>, name: impl Into<String>, version: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            name: name.into(),
            version: version.into(),
            description: String::new(),
            always_on: false,
        }
    }

    pub fn description(mut self, d: impl Into<String>) -> Self {
        self.description = d.into();
        self
    }

    pub fn always_on(mut self) -> Self {
        self.always_on = true;
        self
    }
}

/// 模块挂载的 HTTP 子路由。
pub struct HttpMount {
    /// 仅用于日志/描述，如 `api/ticker`。
    pub label: String,
    pub router: Router<AppState>,
}

impl std::fmt::Debug for HttpMount {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("HttpMount")
            .field("label", &self.label)
            .finish()
    }
}

/// 模块注册期收集到的全部扩展点。
pub struct Registration {
    module_id: String,
    pub(crate) http: Vec<HttpMount>,
    pub(crate) methods: Vec<Arc<MethodSpec>>,
    pub(crate) topics: Vec<TopicSpec>,
}

impl Registration {
    pub fn new(module_id: impl Into<String>) -> Self {
        Self {
            module_id: module_id.into(),
            http: vec![],
            methods: vec![],
            topics: vec![],
        }
    }

    pub fn module_id(&self) -> &str {
        &self.module_id
    }

    /// 挂一个 HTTP 子路由。路径冲突会在组装根路由时立刻暴露。
    pub fn router(&mut self, label: impl Into<String>, router: Router<AppState>) -> &mut Self {
        self.http.push(HttpMount {
            label: label.into(),
            router,
        });
        self
    }

    /// 注册一个 WS 方法。
    ///
    /// `f` 是 `Fn(CallCtx) -> impl Future`，所以直接写 `|ctx| async move { .. }` 即可。
    pub fn method<F, Fut>(
        &mut self,
        name: impl Into<String>,
        description: impl Into<String>,
        f: F,
    ) -> &mut Self
    where
        F: Fn(CallCtx) -> Fut + Send + Sync + 'static,
        Fut: Future<Output = RpcResult<Value>> + Send + 'static,
    {
        self.method_with_scope(name, description, Scope::Remote, f)
    }

    /// 同上，但限定调用来源。
    pub fn method_with_scope<F, Fut>(
        &mut self,
        name: impl Into<String>,
        description: impl Into<String>,
        scope: Scope,
        f: F,
    ) -> &mut Self
    where
        F: Fn(CallCtx) -> Fut + Send + Sync + 'static,
        Fut: Future<Output = RpcResult<Value>> + Send + 'static,
    {
        let name = name.into();
        let handler: Handler = Arc::new(move |ctx: CallCtx| Box::pin(f(ctx)));
        self.methods.push(Arc::new(MethodSpec {
            name,
            module: self.module_id.clone(),
            description: description.into(),
            scope,
            handler,
        }));
        self
    }

    /// 声明本模块会推送的事件主题，客户端据此发现可用订阅。
    pub fn topic(&mut self, topic: impl Into<String>, description: impl Into<String>) -> &mut Self {
        self.topics.push(TopicSpec {
            topic: topic.into(),
            module: self.module_id.clone(),
            description: description.into(),
        });
        self
    }
}

/// 模块启动时拿到的环境。
pub struct ModuleEnv {
    pub app: AppState,
    /// 本模块在 `[modules.config.<id>]` 下的原始配置。
    pub config: Option<toml::Value>,
}

impl ModuleEnv {
    /// 反序列化本模块私有配置；没写该节时用 `T::default()`。
    pub fn config<T>(&self) -> Result<T>
    where
        T: DeserializeOwned + Default,
    {
        let Some(value) = &self.config else {
            return Ok(T::default());
        };
        T::deserialize(value.clone())
            .map_err(|e| crate::error::Error::module("", format!("配置解析失败: {e}")))
    }
}

/// 功能模块。
///
/// 三个方法都有默认实现，最小模块只需要 `descriptor` + `register`。
#[async_trait]
pub trait Module: Send + Sync + 'static {
    /// 模块自述。`id` 必须全局唯一，也是配置节名与方法名前缀。
    fn descriptor(&self) -> ModuleDescriptor;

    /// 注册扩展点。启动期同步调用一次，此时服务还没开始监听。
    fn register(&self, _reg: &mut Registration) -> Result<()> {
        Ok(())
    }

    /// 服务已就绪，起后台任务。
    ///
    /// 返回 `Err` 会让启动失败，框架会回滚已启动的模块。
    async fn start(&self, _env: ModuleEnv) -> Result<()> {
        Ok(())
    }

    /// 优雅关闭。按启动的逆序调用。
    async fn stop(&self) -> Result<()> {
        Ok(())
    }
}

/// 一次 WS 调用的上下文。
#[derive(Clone)]
pub struct CallCtx {
    pub app: AppState,
    /// 处理本次调用的模块 id。
    pub module: String,
    /// 完整方法名。
    pub method: String,
    /// 客户端传入的参数（缺省为 `null`）。
    pub params: Value,
    pub conn_id: u64,
    /// 对端地址 `ip:port`。
    pub peer: String,
    /// 对端是否来自回环地址。
    pub is_local: bool,
}

impl CallCtx {
    pub fn param_raw(&self, key: &str) -> Option<&Value> {
        self.params.get(key)
    }

    /// 取必填参数。缺失或类型不符都是 `invalid_params`。
    pub fn param<T: DeserializeOwned>(&self, key: &str) -> RpcResult<T> {
        let raw = self
            .params
            .get(key)
            .ok_or_else(|| RpcError::invalid_params(format!("缺少参数 `{key}`")))?;
        serde_json::from_value(raw.clone())
            .map_err(|e| RpcError::invalid_params(format!("参数 `{key}` 类型不符: {e}")))
    }

    /// 取可选参数。
    pub fn optional<T: DeserializeOwned>(&self, key: &str) -> RpcResult<Option<T>> {
        match self.params.get(key) {
            None | Some(Value::Null) => Ok(None),
            Some(raw) => serde_json::from_value(raw.clone())
                .map(Some)
                .map_err(|e| RpcError::invalid_params(format!("参数 `{key}` 类型不符: {e}"))),
        }
    }

    /// 取可选参数，缺省用 `default`。
    pub fn param_or<T: DeserializeOwned>(&self, key: &str, default: T) -> RpcResult<T> {
        Ok(self.optional(key)?.unwrap_or(default))
    }

    /// 本模块的私有配置。
    pub fn module_config<T>(&self) -> Result<T>
    where
        T: DeserializeOwned + Default,
    {
        ModuleEnv {
            app: self.app.clone(),
            config: self.app.config.modules.section(&self.module).cloned(),
        }
        .config::<T>()
    }

    /// 推送事件，来源自动标记为本模块。返回事件序号。
    pub fn publish(&self, topic: impl Into<String>, data: Value) -> u64 {
        self.app.bus.publish_from(Some(&self.module), topic, data)
    }
}

impl std::fmt::Debug for CallCtx {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("CallCtx")
            .field("method", &self.method)
            .field("conn_id", &self.conn_id)
            .field("peer", &self.peer)
            .finish_non_exhaustive()
    }
}

/// 构造 `ok` 结果的便捷函数。
pub fn ok(value: Value) -> RpcResult<Value> {
    Ok(value)
}

/// 便于 `ok()` 的语法糖：`Ok(json!(..))` 里省掉一层 `Ok`。
pub use serde_json::json;

/// 当前时间戳，转发给模块用，免得它们各自 import。
pub fn timestamp_ms() -> u64 {
    now_ms()
}
