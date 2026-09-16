//! 事件总线：服务端主动推送的唯一出处。
//!
//! 用 `broadcast` 做扇出：每个连接各持一个 receiver，慢消费者只会丢自己的事件，
//! 不会拖住发布方。模块只管 `publish`，不用关心谁在听。

use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};

use serde::Serialize;
use serde_json::Value;
use tokio::sync::broadcast;

use crate::util::now_ms;

/// 框架自身推送的主题名。
///
/// 由 `core` 模块声明，由框架内部（服务层 / 会话层）发布——这样客户端
/// 通过 `core.topics` 就能发现它们。
pub mod topics {
    /// 服务已开始监听，可以接受连接。
    pub const STARTED: &str = "core.started";
    /// 收到退出信号，进入优雅关闭。
    pub const SHUTTING_DOWN: &str = "core.shutting_down";
    /// 新连接接入。
    pub const CONN_OPENED: &str = "core.conn_opened";
    /// 连接断开。
    pub const CONN_CLOSED: &str = "core.conn_closed";
}

/// 一条推送给客户端的事件。
#[derive(Debug, Clone, Serialize)]
pub struct Event {
    /// 主题，如 `ticker.tick`。
    pub topic: String,
    /// 全局自增序号，客户端可据此判断是否丢事件。
    pub seq: u64,
    /// 毫秒时间戳。
    pub ts: u64,
    /// 发出该事件的模块 id。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source: Option<String>,
    pub data: Value,
}

/// 主题匹配式。
///
/// * `"*"` / `"#"` —— 订阅全部
/// * `"ticker.*"` —— 订阅 `ticker` 及其所有子主题（`ticker`、`ticker.tick`……）
/// * `"ticker.tick"` —— 精确匹配
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TopicPattern(String);

impl TopicPattern {
    pub fn new(pattern: impl Into<String>) -> Self {
        Self(pattern.into())
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }

    pub fn is_global(&self) -> bool {
        matches!(self.0.as_str(), "*" | "#")
    }

    pub fn matches(&self, topic: &str) -> bool {
        if self.is_global() {
            return true;
        }
        if let Some(prefix) = self.0.strip_suffix(".*") {
            return topic == prefix || topic.starts_with(&format!("{prefix}."));
        }
        if let Some(prefix) = self.0.strip_suffix('.') {
            return topic.starts_with(prefix);
        }
        self.0 == topic
    }
}

impl std::fmt::Display for TopicPattern {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

/// 全局事件总线。克隆成本 = 一次 Arc 自增。
#[derive(Clone)]
pub struct EventBus {
    tx: broadcast::Sender<Arc<Event>>,
    seq: Arc<AtomicU64>,
}

impl EventBus {
    pub fn new(capacity: usize) -> Self {
        let (tx, _rx) = broadcast::channel(capacity.max(16));
        Self {
            tx,
            seq: Arc::new(AtomicU64::new(0)),
        }
    }

    /// 发布事件。没有订阅者时静默丢弃。
    pub fn publish(&self, topic: impl Into<String>, data: Value) -> u64 {
        self.publish_from(None, topic, data)
    }

    /// 带来源的发布。模块内部统一走 [`crate::module::CallCtx::publish`] 更省事。
    pub fn publish_from(&self, source: Option<&str>, topic: impl Into<String>, data: Value) -> u64 {
        let seq = self.seq.fetch_add(1, Ordering::Relaxed) + 1;
        let event = Arc::new(Event {
            topic: topic.into(),
            seq,
            ts: now_ms(),
            source: source.map(str::to_string),
            data,
        });

        tracing::trace!(topic = %event.topic, seq = event.seq, "发布事件");
        // 返回 Err 只有一个原因：当前没有订阅者。不算异常。
        let _ = self.tx.send(event);
        seq
    }

    pub fn subscribe(&self) -> broadcast::Receiver<Arc<Event>> {
        self.tx.subscribe()
    }

    /// 当前订阅者数量（活跃连接数）。
    pub fn subscriber_count(&self) -> usize {
        self.tx.receiver_count()
    }
}

impl std::fmt::Debug for EventBus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("EventBus")
            .field("seq", &self.seq.load(Ordering::Relaxed))
            .field("subscribers", &self.subscriber_count())
            .finish()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn exact_and_prefix_matching() {
        assert!(TopicPattern::new("*").matches("anything.at.all"));
        assert!(TopicPattern::new("ticker.tick").matches("ticker.tick"));
        assert!(!TopicPattern::new("ticker.tick").matches("ticker.tock"));

        let p = TopicPattern::new("ticker.*");
        assert!(p.matches("ticker"));
        assert!(p.matches("ticker.tick"));
        assert!(p.matches("ticker.a.b"));
        assert!(!p.matches("tickers"));
    }

    #[tokio::test]
    async fn publish_reaches_subscriber_with_monotonic_seq() {
        let bus = EventBus::new(16);
        let mut rx = bus.subscribe();
        bus.publish("a", json!(1));
        bus.publish_from(Some("m"), "b", json!(2));

        let e1 = rx.recv().await.unwrap();
        let e2 = rx.recv().await.unwrap();
        assert_eq!(e1.topic, "a");
        assert_eq!(e1.source, None);
        assert_eq!(e2.topic, "b");
        assert_eq!(e2.source.as_deref(), Some("m"));
        assert_eq!(e2.seq, e1.seq + 1);
        assert!(e1.ts > 0);
    }

    #[test]
    fn publish_without_subscriber_is_fine() {
        let bus = EventBus::new(16);
        bus.publish("nobody.listens", json!({}));
        assert_eq!(bus.subscriber_count(), 0);
    }
}
