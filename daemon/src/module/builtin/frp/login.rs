//! 登录会话：发起授权 → 后台轮询 → 令牌落盘 → 推事件。
//!
//! 这是「服务商登录请求发起、轮询、令牌保存都在后端」的落点：
//!
//! * **每个平台同时只有一个会话**：再点一次就
//!   把上一个取消掉，避免两个轮询任务抢着写同一份令牌；
//! * 轮询任务跑在 daemon 里，App 断开、切后台、关掉都不影响它；用户回来时
//!   用 `frp.login.status` 或 `frp.login` 事件拿到最终结果；
//! * 轮询上限、致命 / 可重试错误的划分：网络抖动接着轮，
//!   业务错误立即停（密文解密失败之类的，UUID 已被消费，再轮也不会好）。

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use serde_json::{Value, json};
use tokio_util::sync::CancellationToken;

use super::api::{self, LoginFlow, PollOutcome};
use super::model::{Account, LoginState, Provider};
use super::store::FrpStore;
use crate::error::{RpcError, RpcResult};
use crate::state::AppState;

/// 登录状态事件的唯一主题。
pub const TOPIC_LOGIN: &str = "frp.login";

/// 轮询次数上限（写死 60；间隔 5 秒 ≈ 5 分钟）。
const MAX_ATTEMPTS: u32 = 60;

/// 授权超时的提示语。
const TIMEOUT_MESSAGE: &str = "授权超时，请重试";

/// 一个平台当前（或最近一次）的登录会话。
struct Session {
    session_id: String,
    provider: Provider,
    /// 授权页地址（设备码流程里可能自带短码）。
    url: String,
    /// 设备码（仅 ChmlFrp 用；别的平台为空）。
    user_code: String,
    state: LoginState,
    /// 出错时的提示语；其余状态为空。
    message: String,
    account: Option<Account>,
    /// 取消令牌：`frp.login.cancel` 与模块停止都靠它把轮询任务收掉。
    cancel: CancellationToken,
}

impl Session {
    fn idle(provider: Provider) -> Self {
        Self {
            session_id: String::new(),
            provider,
            url: String::new(),
            user_code: String::new(),
            state: LoginState::Idle,
            message: String::new(),
            account: None,
            cancel: CancellationToken::new(),
        }
    }

    fn to_json(&self) -> Value {
        json!({
            "provider": self.provider,
            "session_id": self.session_id,
            "state": self.state,
            "message": self.message,
            "url": self.url,
            "user_code": self.user_code,
            "account": self.account.as_ref().map(Account::public_json),
        })
    }
}

/// 会话表。整个 daemon 一份，挂在 `FrpModule` 上。
pub struct LoginSessions {
    store: FrpStore,
    app: AppState,
    sessions: Mutex<HashMap<Provider, Session>>,
}

impl LoginSessions {
    pub fn new(store: FrpStore, app: AppState) -> Self {
        Self {
            store,
            app,
            sessions: Mutex::new(HashMap::new()),
        }
    }

    /// 当前会话状态；没有会话就是 `idle`。
    pub fn status_json(&self, provider: Provider) -> Value {
        let sessions = self.sessions.lock().expect("登录会话表锁没被投毒");
        sessions
            .get(&provider)
            .map(Session::to_json)
            .unwrap_or_else(|| Session::idle(provider).to_json())
    }

    /// 发起登录：作废旧会话 → 申请授权 → 起后台轮询。
    ///
    /// 授权申请失败直接返回错误（前端弹错误框）；成功则立刻回一份
    /// `waiting` 状态 —— 前端拿它去开浏览器，之后订阅 `frp.login`。
    pub async fn start(self: &Arc<Self>, provider: Provider) -> RpcResult<Value> {
        self.cancel(provider);

        let (start, flow) = api::login_start(provider).await?;
        let session = Session {
            session_id: random_session_id(),
            provider,
            url: start.url,
            user_code: start.user_code,
            state: LoginState::Waiting,
            message: String::new(),
            account: None,
            cancel: CancellationToken::new(),
        };
        let cancel = session.cancel.clone();
        let session_id = session.session_id.clone();
        let snapshot = session.to_json();

        {
            let mut sessions = self.sessions.lock().expect("登录会话表锁没被投毒");
            sessions.insert(provider, session);
        }
        self.publish(&snapshot);

        let sessions = self.clone();
        tokio::spawn(async move {
            sessions.poll(provider, session_id, flow, cancel).await;
        });
        tracing::info!(provider = provider.key(), "已发起浏览器授权登录");
        Ok(snapshot)
    }

    /// 取消登录（用户点了「取消」/ 关掉页面）。
    pub fn cancel(&self, provider: Provider) -> bool {
        let taken = {
            let mut sessions = self.sessions.lock().expect("登录会话表锁没被投毒");
            sessions.remove(&provider)
        };
        let Some(session) = taken else {
            return false;
        };
        session.cancel.cancel();
        // 会话已从表里摘掉，`status` 会回到 idle（未登录态）。
        true
    }

    /// 校验并保存一个用户粘贴的访问令牌（Sakura / ME 的登录方式）。
    pub async fn login_with_token(&self, provider: Provider, token: &str) -> RpcResult<Value> {
        let account = api::verify_token(&self.store, provider, token).await?;
        save_token(&self.store, provider, token, &account).await?;
        tracing::info!(provider = provider.key(), user = %account.username, "令牌登录成功");
        Ok(account.public_json())
    }

    /// 退出登录：清令牌 + 账号缓存，并把会话打回 idle。
    pub async fn logout(&self, provider: Provider) -> RpcResult<()> {
        self.cancel(provider);
        let store = self.store.clone();
        tokio::task::spawn_blocking(move || store.clear_token(provider))
            .await
            .map_err(|e| RpcError::internal(format!("清除令牌任务失败：{e}")))?
            .map_err(|e| RpcError::internal(format!("清除令牌失败：{e}")))?;
        Ok(())
    }

    /// 停掉全部轮询（模块停止时调用）。
    pub fn shutdown(&self) {
        let mut sessions = self.sessions.lock().expect("登录会话表锁没被投毒");
        for session in sessions.values() {
            session.cancel.cancel();
        }
        sessions.clear();
    }

    /// 轮询循环。`flow` 会被就地更新（ChmlFrp 的 `slow_down`）。
    async fn poll(
        self: Arc<Self>,
        provider: Provider,
        session_id: String,
        mut flow: LoginFlow,
        cancel: CancellationToken,
    ) {
        let mut attempts = 0u32;
        loop {
            let interval = Duration::from_millis(flow.interval_ms());
            tokio::select! {
                _ = tokio::time::sleep(interval) => {}
                _ = cancel.cancelled() => return,
            }
            if attempts >= MAX_ATTEMPTS {
                self.finish(
                    provider,
                    &session_id,
                    LoginState::Error,
                    TIMEOUT_MESSAGE.to_string(),
                    None,
                );
                return;
            }
            attempts += 1;

            match api::login_poll(&self.store, &mut flow).await {
                Ok(PollOutcome::Pending) => continue,
                Ok(PollOutcome::Done(token)) => {
                    // 拿到令牌先验一次账号：验不过就不该写进凭据
                    // （写进去下次照样用不了）。
                    match api::verify_token(&self.store, provider, &token).await {
                        Ok(account) => {
                            match save_token(&self.store, provider, &token, &account).await {
                                Ok(()) => {
                                    tracing::info!(
                                        provider = provider.key(),
                                        user = %account.username,
                                        "浏览器授权登录成功"
                                    );
                                    self.finish(
                                        provider,
                                        &session_id,
                                        LoginState::Success,
                                        String::new(),
                                        Some(account),
                                    );
                                }
                                Err(e) => {
                                    self.finish(
                                        provider,
                                        &session_id,
                                        LoginState::Error,
                                        e.message,
                                        None,
                                    );
                                }
                            }
                        }
                        Err(e) => {
                            tracing::warn!(provider = provider.key(), error = %e, "授权完成但账号校验失败");
                            self.finish(provider, &session_id, LoginState::Error, e.message, None);
                        }
                    }
                    return;
                }
                // 网络抖动接着轮（单次异常先吞掉继续等）；业务 / 协议错误是致命的。
                Err(e) if e.code == "frp_network_error" => {
                    tracing::debug!(provider = provider.key(), error = %e, "轮询失败，继续等待");
                    continue;
                }
                Err(e) => {
                    self.finish(provider, &session_id, LoginState::Error, e.message, None);
                    return;
                }
            }
        }
    }

    /// 收尾：写回会话状态并推事件。
    ///
    /// `session_id` 对不上说明这是上一轮遗留的轮询任务（用户又点了一次登录），
    /// 直接丢弃，别把新会话的状态覆盖掉。
    fn finish(
        &self,
        provider: Provider,
        session_id: &str,
        state: LoginState,
        message: String,
        account: Option<Account>,
    ) {
        let mut sessions = self.sessions.lock().expect("登录会话表锁没被投毒");
        let Some(session) = sessions.get_mut(&provider) else {
            return;
        };
        if session.session_id != session_id {
            return;
        }
        session.state = state;
        session.message = message;
        session.account = account;
        let snapshot = session.to_json();
        drop(sessions);
        self.publish(&snapshot);
    }

    fn publish(&self, data: &Value) {
        self.app
            .bus
            .publish_from(Some("frp"), TOPIC_LOGIN, data.clone());
        tracing::debug!(state = %data["state"], "推送登录状态");
    }
}

/// 保存令牌 + 账号缓存（同步 IO 丢进阻塞线程池）。
async fn save_token(
    store: &FrpStore,
    provider: Provider,
    token: &str,
    account: &Account,
) -> Result<(), super::api::ApiError> {
    let store = store.clone();
    let token = token.to_string();
    let account = account.clone();
    tokio::task::spawn_blocking(move || store.save_token(provider, &token, &account))
        .await
        .map_err(|e| super::api::ApiError::internal(format!("保存令牌任务失败：{e}")))?
        .map_err(|e| super::api::ApiError::internal(format!("保存令牌失败：{e}")))
}

/// 随机会话 ID（16 位十六进制，与实例 / 隧道 ID 同策略）。
fn random_session_id() -> String {
    // rand 0.10：`random_range` 在 `RngExt` 上（见 api/openfrp.rs 的说明）。
    use rand::RngExt as _;
    let mut rng = rand::rng();
    (0..16)
        .map(|_| char::from_digit(rng.random_range(0..16), 16).unwrap_or('0'))
        .collect()
}
