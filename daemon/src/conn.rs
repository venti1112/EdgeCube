//! 连接表。
//!
//! 事件总线负责「按主题扇出」，这里负责「按连接点对点」：
//! 广播给所有连接、踢掉指定连接、给管理页列出当前连接。
//! 出站消息统一走每条连接的 `mpsc`，保证**只有一个 writer**，不会交叉写坏帧。

use std::collections::BTreeMap;
use std::sync::Arc;

use serde::Serialize;
use tokio::sync::{Mutex, mpsc};

use crate::server::ws::protocol::ServerMessage;
use crate::util::now_ms;

/// 出站消息。控制帧和业务帧共用一条队列，保证顺序。
#[derive(Debug, Clone)]
pub enum Outbound {
    Msg(Arc<ServerMessage>),
    /// WS 层 Ping 帧（浏览器/标准客户端会自动回 Pong，无需业务代码）。
    Ping,
    /// WS 层 Pong 帧：回应客户端的 Ping。
    Pong(Vec<u8>),
    Close {
        code: u16,
        reason: String,
    },
}

/// 一条连接的句柄。
#[derive(Debug, Clone)]
pub struct ConnHandle {
    pub id: u64,
    /// `ip:port`，用于日志与管理页。
    pub peer: String,
    pub opened_at_ms: u64,
    tx: mpsc::UnboundedSender<Outbound>,
}

impl ConnHandle {
    /// 投递消息。连接已断开时返回 `false`。
    pub fn send(&self, msg: Outbound) -> bool {
        self.tx.send(msg).is_ok()
    }

    /// 推送一条业务消息。
    pub fn push(&self, msg: Arc<ServerMessage>) -> bool {
        self.send(Outbound::Msg(msg))
    }

    pub fn close(&self, code: u16, reason: impl Into<String>) -> bool {
        self.send(Outbound::Close {
            code,
            reason: reason.into(),
        })
    }

    /// 回应客户端的 WS Ping 帧。
    pub fn pong(&self, payload: Vec<u8>) -> bool {
        self.send(Outbound::Pong(payload))
    }
}

/// 连接表快照条目（对外可序列化）。
#[derive(Debug, Clone, Serialize)]
pub struct ConnSnapshot {
    pub id: u64,
    pub peer: String,
    pub opened_at_ms: u64,
    pub uptime_ms: u64,
}

#[derive(Default)]
struct Inner {
    conns: Mutex<BTreeMap<u64, ConnHandle>>,
}

/// 连接表。克隆成本 = 一次 Arc 自增。
#[derive(Clone, Default)]
pub struct ConnRegistry {
    inner: Arc<Inner>,
}

impl std::fmt::Debug for ConnRegistry {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ConnRegistry").finish_non_exhaustive()
    }
}

impl ConnRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    /// 登记一条新连接。返回句柄与写入端。
    pub async fn register(
        &self,
        id: u64,
        peer: impl Into<String>,
    ) -> (ConnHandle, mpsc::UnboundedReceiver<Outbound>) {
        let (tx, rx) = mpsc::unbounded_channel();
        let handle = ConnHandle {
            id,
            peer: peer.into(),
            opened_at_ms: now_ms(),
            tx,
        };
        self.inner.conns.lock().await.insert(id, handle.clone());
        (handle, rx)
    }

    pub async fn unregister(&self, id: u64) {
        self.inner.conns.lock().await.remove(&id);
    }

    pub async fn count(&self) -> usize {
        self.inner.conns.lock().await.len()
    }

    pub async fn get(&self, id: u64) -> Option<ConnHandle> {
        self.inner.conns.lock().await.get(&id).cloned()
    }

    pub async fn snapshots(&self) -> Vec<ConnSnapshot> {
        let now = now_ms();
        self.inner
            .conns
            .lock()
            .await
            .values()
            .map(|h| ConnSnapshot {
                id: h.id,
                peer: h.peer.clone(),
                opened_at_ms: h.opened_at_ms,
                uptime_ms: now.saturating_sub(h.opened_at_ms),
            })
            .collect()
    }

    /// 给所有连接推同一条消息。返回成功入队的连接数。
    pub async fn broadcast(&self, msg: Arc<ServerMessage>) -> usize {
        let conns = self.inner.conns.lock().await;
        conns.values().filter(|h| h.push(msg.clone())).count()
    }

    /// 关闭所有连接（用于优雅退出）。返回被通知的连接数。
    pub async fn close_all(&self, code: u16, reason: impl Into<String>) -> usize {
        let reason = reason.into();
        let conns = self.inner.conns.lock().await;
        conns
            .values()
            .filter(|h| h.close(code, reason.clone()))
            .count()
    }

    /// 连接 id 分配器。独立于连接表，避免加锁。
    pub fn next_id(&self) -> u64 {
        use std::sync::atomic::{AtomicU64, Ordering};
        static SEQ: AtomicU64 = AtomicU64::new(0);
        SEQ.fetch_add(1, Ordering::Relaxed) + 1
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::server::ws::protocol::ServerMessage;

    #[tokio::test]
    async fn register_unregister_and_snapshot() {
        let reg = ConnRegistry::new();
        let (h, _rx) = reg.register(reg.next_id(), "127.0.0.1:1").await;
        assert_eq!(reg.count().await, 1);
        let snap = reg.snapshots().await;
        assert_eq!(snap.len(), 1);
        assert_eq!(snap[0].id, h.id);
        assert_eq!(snap[0].peer, "127.0.0.1:1");

        reg.unregister(h.id).await;
        assert_eq!(reg.count().await, 0);
    }

    #[tokio::test]
    async fn broadcast_hits_every_connection() {
        let reg = ConnRegistry::new();
        let (_a, mut ra) = reg.register(1, "a").await;
        let (_b, mut rb) = reg.register(2, "b").await;

        let n = reg
            .broadcast(Arc::new(ServerMessage::Pong { id: None, ts: 1 }))
            .await;
        assert_eq!(n, 2);
        assert!(matches!(ra.recv().await.unwrap(), Outbound::Msg(_)));
        assert!(matches!(rb.recv().await.unwrap(), Outbound::Msg(_)));
    }

    #[tokio::test]
    async fn close_all_sends_close_frame() {
        let reg = ConnRegistry::new();
        let (_a, mut ra) = reg.register(1, "a").await;
        assert_eq!(reg.close_all(1001, "bye").await, 1);
        assert!(matches!(
            ra.recv().await.unwrap(),
            Outbound::Close { code: 1001, .. }
        ));
    }

    #[tokio::test]
    async fn send_to_dropped_connection_returns_false() {
        let reg = ConnRegistry::new();
        let (h, rx) = reg.register(1, "a").await;
        drop(rx);
        assert!(!h.push(Arc::new(ServerMessage::Pong { id: None, ts: 1 })));
    }
}
