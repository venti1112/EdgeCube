//! 模块注册表：把「有哪些模块」变成「有什么能力」。
//!
//! [`builtin_modules`] 是整个 daemon 里**唯一**的插拔点。

use std::collections::BTreeMap;
use std::sync::Arc;

use serde_json::{Value, json};

use super::{
    CallCtx, HttpMount, MethodInfo, MethodSpec, Module, ModuleDescriptor, ModuleEnv, Registration,
    Scope, TopicSpec, builtin,
};
use crate::config::Config;
use crate::error::{Error, Result, RpcError, RpcResult};
use crate::state::AppState;

/// 编译期模块清单。
///
/// **加功能模块就在这里加一行；删功能模块就在这里删一行。**
/// 运行期开关则走配置 `modules.enabled` / `modules.disabled`。
pub fn builtin_modules() -> Vec<Arc<dyn Module>> {
    vec![
        Arc::new(builtin::core::CoreModule::new()),
        Arc::new(builtin::ticker::TickerModule::new()),
        Arc::new(builtin::instance::InstanceModule::new()),
    ]
}

/// 已注册的所有模块。
pub struct ModuleRegistry {
    /// 全部模块（含被配置禁用的），用于校验配置与排查问题。
    all: Vec<Arc<dyn Module>>,
    all_descriptors: Vec<ModuleDescriptor>,
    /// 实际启用并完成注册的模块。
    enabled: Vec<Arc<dyn Module>>,
    enabled_descriptors: Vec<ModuleDescriptor>,
    methods: BTreeMap<String, Arc<MethodSpec>>,
    topics: Vec<TopicSpec>,
    http: Vec<HttpMount>,
}

impl ModuleRegistry {
    /// 取模块 id 列表（配置校验用，可脱离注册表调用）。
    pub fn known_ids(modules: &[Arc<dyn Module>]) -> Vec<String> {
        modules.iter().map(|m| m.descriptor().id).collect()
    }

    /// 按配置构建注册表。
    ///
    /// 这一步不做任何 IO，也不会起后台任务——所有扩展点都静态收集好，
    /// 服务可以放心地在真正监听之前失败。
    pub fn build(all: Vec<Arc<dyn Module>>, config: &Config) -> Result<Self> {
        let all_descriptors: Vec<ModuleDescriptor> = all.iter().map(|m| m.descriptor()).collect();

        // 1) id 唯一性
        for (i, d) in all_descriptors.iter().enumerate() {
            if d.id.trim().is_empty() {
                return Err(Error::config(format!("第 {i} 个模块的 id 为空")));
            }
            if all_descriptors[..i].iter().any(|prev| prev.id == d.id) {
                return Err(Error::config(format!("模块 id `{}` 重复注册", d.id)));
            }
        }

        // 2) 配置里引用的模块必须存在
        config.validate_modules(&Self::known_ids(&all))?;

        // 3) 按配置筛选（always_on 不受开关影响）
        let mut enabled = Vec::new();
        let mut enabled_descriptors = Vec::new();
        for (module, descriptor) in all.iter().zip(&all_descriptors) {
            if descriptor.always_on {
                enabled.push(module.clone());
                enabled_descriptors.push(descriptor.clone());
                continue;
            }
            if config.modules.is_enabled(&descriptor.id) {
                enabled.push(module.clone());
                enabled_descriptors.push(descriptor.clone());
            } else {
                tracing::info!(module = %descriptor.id, "模块按配置跳过");
            }
        }

        // 4) 收集扩展点
        let mut methods: BTreeMap<String, Arc<MethodSpec>> = BTreeMap::new();
        let mut topics = Vec::new();
        let mut http = Vec::new();

        for (module, descriptor) in enabled.iter().zip(&enabled_descriptors) {
            let mut reg = Registration::new(descriptor.id.clone());
            module
                .register(&mut reg)
                .map_err(|e| Error::module(&descriptor.id, e.to_string()))?;

            for spec in reg.methods {
                if let Some(existing) = methods.get(&spec.name) {
                    return Err(Error::config(format!(
                        "WS 方法 `{}` 被模块 `{}` 与 `{}` 重复注册",
                        spec.name, existing.module, spec.module
                    )));
                }
                tracing::debug!(method = %spec.name, module = %spec.module, "注册 WS 方法");
                methods.insert(spec.name.clone(), spec);
            }
            for topic in reg.topics {
                if topics.iter().any(|t: &TopicSpec| t.topic == topic.topic) {
                    return Err(Error::config(format!(
                        "事件主题 `{}` 重复声明",
                        topic.topic
                    )));
                }
                topics.push(topic);
            }
            for mount in reg.http {
                tracing::debug!(mount = %mount.label, module = %descriptor.id, "挂载 HTTP 子路由");
                http.push(mount);
            }
        }

        Ok(Self {
            all,
            all_descriptors,
            enabled,
            enabled_descriptors,
            methods,
            topics,
            http,
        })
    }

    // ---- 只读视图 ---------------------------------------------------------

    pub fn all_descriptors(&self) -> &[ModuleDescriptor] {
        &self.all_descriptors
    }

    /// 全部模块实例（含被配置禁用的）。
    ///
    /// 目前只用于自省；将来做「不重启启用模块」时会从这里取。
    pub fn all_modules(&self) -> &[Arc<dyn Module>] {
        &self.all
    }

    pub fn enabled_descriptors(&self) -> &[ModuleDescriptor] {
        &self.enabled_descriptors
    }

    pub fn topics(&self) -> &[TopicSpec] {
        &self.topics
    }

    pub fn method_infos(&self) -> Vec<MethodInfo> {
        self.methods.values().map(|m| m.describe()).collect()
    }

    pub fn method_names(&self) -> Vec<String> {
        self.methods.keys().cloned().collect()
    }

    pub fn method_count(&self) -> usize {
        self.methods.len()
    }

    /// 取出 HTTP 子路由（`Router` 是 clone 廉价的句柄）。
    pub fn take_http_mounts(&self) -> Vec<HttpMount> {
        self.http
            .iter()
            .map(|m| HttpMount {
                label: m.label.clone(),
                router: m.router.clone(),
            })
            .collect()
    }

    // ---- 生命周期 ---------------------------------------------------------

    /// 依次启动已启用模块。任一失败则逆序回滚已启动的模块。
    pub async fn start_all(&self, app: &AppState) -> Result<()> {
        let mut started = Vec::new();
        for (module, descriptor) in self.enabled.iter().zip(&self.enabled_descriptors) {
            let env = ModuleEnv {
                app: app.clone(),
                config: app.config.modules.section(&descriptor.id).cloned(),
            };
            tracing::debug!(module = %descriptor.id, "启动模块");
            match module.start(env).await {
                Ok(()) => started.push(module.clone()),
                Err(e) => {
                    tracing::error!(module = %descriptor.id, error = %e, "模块启动失败，开始回滚");
                    for m in started.iter().rev() {
                        let id = m.descriptor().id;
                        if let Err(e2) = m.stop().await {
                            tracing::warn!(module = %id, error = %e2, "回滚关闭模块失败");
                        }
                    }
                    return Err(Error::module(&descriptor.id, e.to_string()));
                }
            }
        }
        Ok(())
    }

    /// 逆序关闭所有已启用模块。返回失败清单（不影响其余模块继续关闭）。
    pub async fn stop_all(&self) -> Vec<(String, String)> {
        let mut failures = Vec::new();
        for module in self.enabled.iter().rev() {
            let id = module.descriptor().id;
            tracing::debug!(module = %id, "关闭模块");
            if let Err(e) = module.stop().await {
                tracing::warn!(module = %id, error = %e, "模块关闭失败");
                failures.push((id, e.to_string()));
            }
        }
        failures
    }

    // ---- 调用分发 ---------------------------------------------------------

    /// 查方法但不调用（供自省接口使用）。
    pub fn lookup(&self, name: &str) -> Option<&Arc<MethodSpec>> {
        self.methods.get(name)
    }

    /// 分发一次 WS 调用，内含超时与可见性检查。
    pub async fn dispatch(&self, ctx: CallCtx) -> RpcResult<Value> {
        if ctx.app.is_shutting_down() {
            return Err(RpcError::unavailable("服务正在关闭"));
        }

        let spec = self.lookup(&ctx.method).ok_or_else(|| {
            let hint = self.suggest(&ctx.method);
            let msg = match hint {
                Some(h) => format!("未注册的方法 `{}`，是不是想调 `{h}`？", ctx.method),
                None => format!("未注册的方法 `{}`", ctx.method),
            };
            RpcError::method_not_found(msg)
        })?;

        if spec.scope == Scope::Local && !ctx.is_local {
            return Err(RpcError::forbidden(format!(
                "方法 `{}` 只允许本机调用",
                ctx.method
            )));
        }

        let timeout = std::time::Duration::from_secs(ctx.app.config.server.request_timeout_secs);
        match tokio::time::timeout(timeout, (spec.handler)(ctx)).await {
            Ok(result) => result,
            Err(_) => Err(RpcError::timeout(format!(
                "方法 `{}` 处理超时（{}s）",
                spec.name,
                timeout.as_secs()
            ))),
        }
    }

    /// 拼错方法名时给个候选：同模块的最短名字。
    fn suggest(&self, name: &str) -> Option<String> {
        let prefix = name.split('.').next()?;
        self.methods
            .keys()
            .filter(|k| k.starts_with(&format!("{prefix}.")))
            .min_by_key(|k| k.len())
            .cloned()
    }

    /// 注册表概览，用于启动日志与 `core.modules`。
    pub fn summary(&self) -> Value {
        json!({
            "modules": self.enabled_descriptors,
            "disabled": self
                .all_descriptors
                .iter()
                .filter(|d| !self.enabled_descriptors.iter().any(|e| e.id == d.id))
                .collect::<Vec<_>>(),
            "method_count": self.methods.len(),
            "topic_count": self.topics.len(),
            "http_mounts": self.http.iter().map(|m| m.label.clone()).collect::<Vec<_>>(),
        })
    }
}

impl std::fmt::Debug for ModuleRegistry {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ModuleRegistry")
            .field("enabled", &self.enabled_descriptors.len())
            .field("methods", &self.methods.len())
            .field("topics", &self.topics.len())
            .finish()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::Config;
    use async_trait::async_trait;
    use serde_json::json;
    use std::sync::atomic::{AtomicUsize, Ordering};

    /// 最小测试模块：注册一个方法 + 一个主题，并记录生命周期调用。
    struct ProbeModule {
        id: &'static str,
        started: Arc<AtomicUsize>,
        stopped: Arc<AtomicUsize>,
        fail_start: bool,
    }

    impl ProbeModule {
        fn new(id: &'static str) -> (Arc<Self>, Arc<AtomicUsize>, Arc<AtomicUsize>) {
            let started = Arc::new(AtomicUsize::new(0));
            let stopped = Arc::new(AtomicUsize::new(0));
            let m = Arc::new(Self {
                id,
                started: started.clone(),
                stopped: stopped.clone(),
                fail_start: false,
            });
            (m, started, stopped)
        }
    }

    #[async_trait]
    impl Module for ProbeModule {
        fn descriptor(&self) -> ModuleDescriptor {
            ModuleDescriptor::new(self.id, self.id, "0.1.0")
        }

        fn register(&self, reg: &mut Registration) -> Result<()> {
            let id = self.id;
            reg.topic(format!("{id}.evt"), "测试事件");
            reg.method(
                format!("{id}.hello"),
                "打招呼",
                move |ctx: CallCtx| async move {
                    let name: String = ctx.param_or("name", "world".to_string())?;
                    Ok(json!({ "from": id, "name": name, "conn": ctx.conn_id }))
                },
            );
            Ok(())
        }

        async fn start(&self, _env: ModuleEnv) -> Result<()> {
            if self.fail_start {
                return Err(Error::other("故意失败"));
            }
            self.started.fetch_add(1, Ordering::SeqCst);
            Ok(())
        }

        async fn stop(&self) -> Result<()> {
            self.stopped.fetch_add(1, Ordering::SeqCst);
            Ok(())
        }
    }

    fn ctx_for(state: &AppState, method: &str, params: Value) -> CallCtx {
        CallCtx {
            app: state.clone(),
            module: method.split('.').next().unwrap_or_default().to_string(),
            method: method.to_string(),
            params,
            conn_id: 7,
            peer: "127.0.0.1:5555".into(),
            is_local: true,
        }
    }

    fn state_with(registry: Arc<ModuleRegistry>, config: Config) -> AppState {
        AppState::new(
            config,
            None,
            registry,
            tokio_util::sync::CancellationToken::new(),
        )
    }

    #[test]
    fn duplicate_method_names_are_rejected() {
        let (a, _, _) = ProbeModule::new("alpha");
        // 第二个模块故意注册同名方法
        struct Clash;
        #[async_trait]
        impl Module for Clash {
            fn descriptor(&self) -> ModuleDescriptor {
                ModuleDescriptor::new("alpha", "alpha", "0.1.0")
            }
        }
        let err = ModuleRegistry::build(vec![a, Arc::new(Clash)], &Config::default()).unwrap_err();
        assert!(err.to_string().contains("重复注册"));
    }

    #[tokio::test]
    async fn dispatch_routes_to_the_right_module() {
        let (m, started, stopped) = ProbeModule::new("alpha");
        let registry = Arc::new(ModuleRegistry::build(vec![m], &Config::default()).unwrap());
        let app = state_with(registry.clone(), Config::default());

        registry.start_all(&app).await.unwrap();
        assert_eq!(started.load(Ordering::SeqCst), 1);

        let out = registry
            .dispatch(ctx_for(&app, "alpha.hello", json!({"name": "小明"})))
            .await
            .unwrap();
        assert_eq!(out["from"], json!("alpha"));
        assert_eq!(out["name"], json!("小明"));
        assert_eq!(out["conn"], json!(7));

        registry.stop_all().await;
        assert_eq!(stopped.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn unknown_method_suggests_sibling() {
        let (m, _, _) = ProbeModule::new("alpha");
        let registry = Arc::new(ModuleRegistry::build(vec![m], &Config::default()).unwrap());
        let app = state_with(registry.clone(), Config::default());

        let err = registry
            .dispatch(ctx_for(&app, "alpha.helo", json!({})))
            .await
            .unwrap_err();
        assert_eq!(err.code, "method_not_found");
        assert!(
            err.message.contains("alpha.hello"),
            "应给出候选: {}",
            err.message
        );
    }

    #[tokio::test]
    async fn missing_param_is_invalid_params() {
        let (m, _, _) = ProbeModule::new("alpha");
        let registry = Arc::new(ModuleRegistry::build(vec![m], &Config::default()).unwrap());
        let app = state_with(registry.clone(), Config::default());

        let mut ctx = ctx_for(&app, "alpha.hello", json!(1));
        ctx.params = json!({"name": 42});
        let err = registry.dispatch(ctx).await.unwrap_err();
        assert_eq!(err.code, "invalid_params");
        assert!(err.message.contains("name"));
    }

    #[tokio::test]
    async fn disabled_module_is_not_registered() {
        let (m, started, _) = ProbeModule::new("alpha");
        let mut config = Config::default();
        config.modules.enabled = crate::config::Enabled::List(vec!["alpha".into()]);
        config.modules.disabled = vec!["alpha".into()];

        let registry = Arc::new(ModuleRegistry::build(vec![m], &config).unwrap());
        assert_eq!(registry.method_count(), 0);
        assert!(registry.enabled_descriptors().is_empty());

        let app = state_with(registry.clone(), config);
        registry.start_all(&app).await.unwrap();
        assert_eq!(started.load(Ordering::SeqCst), 0);
    }

    #[tokio::test]
    async fn local_scope_rejects_remote_peer() {
        struct LocalOnly;
        #[async_trait]
        impl Module for LocalOnly {
            fn descriptor(&self) -> ModuleDescriptor {
                ModuleDescriptor::new("local", "local", "0.1.0")
            }
            fn register(&self, reg: &mut Registration) -> Result<()> {
                reg.method_with_scope("local.shutdown", "关闭", Scope::Local, |_ctx| async move {
                    Ok(json!({"ok": true}))
                });
                Ok(())
            }
        }

        let registry =
            Arc::new(ModuleRegistry::build(vec![Arc::new(LocalOnly)], &Config::default()).unwrap());
        let app = state_with(registry.clone(), Config::default());

        let mut ctx = ctx_for(&app, "local.shutdown", json!({}));
        ctx.is_local = false;
        let err = registry.dispatch(ctx).await.unwrap_err();
        assert_eq!(err.code, "forbidden");

        let err = registry
            .dispatch(ctx_for(&app, "local.shutdown", json!({})))
            .await;
        assert!(err.is_ok());
    }

    #[tokio::test]
    async fn handler_timeout_is_enforced() {
        struct Slow;
        #[async_trait]
        impl Module for Slow {
            fn descriptor(&self) -> ModuleDescriptor {
                ModuleDescriptor::new("slow", "slow", "0.1.0")
            }
            fn register(&self, reg: &mut Registration) -> Result<()> {
                reg.method("slow.wait", "很慢", |_ctx| async move {
                    tokio::time::sleep(std::time::Duration::from_secs(30)).await;
                    Ok(json!(null))
                });
                Ok(())
            }
        }

        let registry =
            Arc::new(ModuleRegistry::build(vec![Arc::new(Slow)], &Config::default()).unwrap());
        let mut config = Config::default();
        config.server.request_timeout_secs = 1;
        let app = state_with(registry.clone(), config);

        let started = std::time::Instant::now();
        let err = registry
            .dispatch(ctx_for(&app, "slow.wait", json!({})))
            .await
            .unwrap_err();
        assert_eq!(err.code, "timeout");
        assert!(started.elapsed() < std::time::Duration::from_secs(5));
    }

    #[tokio::test]
    async fn shutting_down_blocks_new_calls() {
        let (m, _, _) = ProbeModule::new("alpha");
        let registry = Arc::new(ModuleRegistry::build(vec![m], &Config::default()).unwrap());
        let app = state_with(registry.clone(), Config::default());
        app.cancel.cancel();

        let err = registry
            .dispatch(ctx_for(&app, "alpha.hello", json!({})))
            .await
            .unwrap_err();
        assert_eq!(err.code, "unavailable");
    }

    #[test]
    fn builtin_registry_builds_and_exposes_capabilities() {
        let registry = ModuleRegistry::build(builtin_modules(), &Config::default()).unwrap();
        assert!(registry.method_count() >= 5, "内置模块至少要暴露几个方法");
        assert!(registry.lookup("core.ping").is_some());
        assert!(registry.lookup("ticker.status").is_some());
        assert!(registry.topics().iter().any(|t| t.topic == "ticker.tick"));
        assert!(registry.all_descriptors().iter().any(|d| d.always_on));
    }
}
