//! PTY 输出的公共层：环形历史 + 订阅者扇出。
//!
//! 实例控制台（`instance::process`）与主机终端（`builtin::shell`）共用这一套 ——
//! 两者都是「一个 PTY 进程 + 若干条 WebSocket 连接」，协议也完全一样
//! （`history_begin` / 二进制历史 / `history_end` + state / 实时二进制 / `exit`）。
//!
//! **取历史快照与注册订阅者必须在同一把锁里完成**（[`Broadcast::subscribe`]）：
//! 拆成两步的话，先取历史再注册会漏掉中间的帧，先注册再取历史会重复。
//! 这是整套方案的关键，别改。

use std::collections::{HashMap, VecDeque};
use std::io::Write;
use std::sync::mpsc::Receiver;
use std::sync::{Arc, Mutex};

use portable_pty::{MasterPty, PtySize};
use tokio::sync::mpsc::Sender as TokioSender;

/// 每条连接的输出缓冲。满了就丢帧 —— **绝不阻塞 PTY 读取线程**。
pub const SUBSCRIBER_BUFFER: usize = 256;

/// 送给输入线程的指令。
pub enum Input {
    /// 原样写进 PTY（用户敲的键、停止命令……）。
    Data(Vec<u8>),
    /// 调整 PTY 尺寸。
    Resize(u16, u16),
}

/// 输入线程：把通道里的字节 / resize 写进 PTY，通道关闭就退出。
///
/// 实例控制台与主机终端共用 —— 两边都只是「一个 writer + 一个 master」。
pub fn input_loop(
    mut writer: Box<dyn Write + Send>,
    master: Arc<Mutex<Box<dyn MasterPty + Send>>>,
    rx: Receiver<Input>,
) {
    while let Ok(msg) = rx.recv() {
        match msg {
            Input::Data(data) => {
                if writer.write_all(&data).is_err() || writer.flush().is_err() {
                    break;
                }
            }
            Input::Resize(cols, rows) => {
                if let Ok(m) = master.lock() {
                    let _ = m.resize(PtySize {
                        rows,
                        cols,
                        pixel_width: 0,
                        pixel_height: 0,
                    });
                }
            }
        }
    }
}

/// 发给终端连接的一帧。
#[derive(Debug, Clone)]
pub enum OutFrame {
    /// 原始 PTY 输出 → 客户端用二进制帧发。
    Data(Vec<u8>),
    /// 控制消息（JSON）→ 客户端用文本帧发。
    Control(String),
}

/// 输出历史 + 订阅者。
///
/// 历史是**块**的队列（每次 PTY 读取一块），超过上限从最旧的块开始丢，
/// 但至少留一块 —— 免得「最后一行输出」也被裁掉。
pub struct Broadcast {
    chunks: VecDeque<Vec<u8>>,
    total: usize,
    max: usize,
    subscribers: HashMap<u64, TokioSender<OutFrame>>,
}

impl Broadcast {
    pub fn new(max: usize) -> Self {
        Self {
            chunks: VecDeque::new(),
            total: 0,
            max,
            subscribers: HashMap::new(),
        }
    }

    /// 追加一块输出，从最旧的块开始裁剪，并扇给所有订阅者。
    pub fn append(&mut self, data: Vec<u8>) {
        self.total += data.len();
        self.chunks.push_back(data.clone());
        // 至少留一块，免得裁完历史是空的
        while self.total > self.max && self.chunks.len() > 1 {
            if let Some(old) = self.chunks.pop_front() {
                self.total -= old.len();
            }
        }
        self.fan_out(OutFrame::Data(data));
    }

    /// 把历史拼成一份连续快照。
    pub fn snapshot(&self) -> Vec<u8> {
        let mut buf = Vec::with_capacity(self.total);
        for chunk in &self.chunks {
            buf.extend_from_slice(chunk);
        }
        buf
    }

    /// 取快照 + 注册订阅者（**同一把锁**，见模块注释）。
    pub fn subscribe(&mut self, id: u64, tx: TokioSender<OutFrame>) -> Vec<u8> {
        let snapshot = self.snapshot();
        self.subscribers.insert(id, tx);
        snapshot
    }

    /// 退订。PTY 继续跑 —— 断开连接不等于停进程。
    pub fn unsubscribe(&mut self, id: u64) {
        self.subscribers.remove(&id);
    }

    /// 当前订阅者数量（自省与测试用）。
    pub fn subscriber_count(&self) -> usize {
        self.subscribers.len()
    }

    /// 清掉输出历史（终端的「清屏」）。
    pub fn clear(&mut self) {
        self.chunks.clear();
        self.total = 0;
    }

    /// 广播一条控制消息（**不进历史** —— 那是瞬时状态，不是输出）。
    pub fn control(&mut self, json: String) {
        self.fan_out(OutFrame::Control(json));
    }

    /// 写一条给人看的提示（进历史 + 广播）。
    ///
    /// `[EdgeCube] …` 这类提示走这里：它和终端输出连在一起，迟到的连接
    /// 也能在历史里看到。
    pub fn notice(&mut self, text: &str) {
        let mut bytes = Vec::with_capacity(text.len() + 4);
        bytes.extend_from_slice(b"\r\n");
        bytes.extend_from_slice(text.as_bytes());
        bytes.extend_from_slice(b"\r\n");
        self.append(bytes);
    }

    fn fan_out(&mut self, frame: OutFrame) {
        for tx in self.subscribers.values() {
            let _ = tx.try_send(frame.clone());
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 历史是环形的：超上限后从最旧的块开始丢。
    #[test]
    fn history_is_trimmed_from_the_oldest_chunk() {
        let mut broadcast = Broadcast::new(64);
        for i in 0..10 {
            broadcast.append(format!("chunk-{i};").into_bytes());
        }
        let text = String::from_utf8_lossy(&broadcast.snapshot()).to_string();
        assert!(text.len() <= 64 + "chunk-9;".len(), "应当被裁剪过: {text}");
        assert!(text.ends_with("chunk-9;"), "最新的必须留着: {text}");
        assert!(!text.contains("chunk-0;"), "最旧的应被丢掉: {text}");
    }

    /// 快照与订阅在同一把锁里：订阅之后追加的输出会扇给我，之前的不重复给。
    #[test]
    fn subscribe_takes_a_snapshot_and_then_receives_live_frames() {
        let mut broadcast = Broadcast::new(1024);
        broadcast.append(b"old".to_vec());

        let (tx, mut rx) = tokio::sync::mpsc::channel(4);
        let snapshot = broadcast.subscribe(7, tx);
        assert_eq!(snapshot, b"old");

        broadcast.append(b"new".to_vec());
        match rx.try_recv() {
            Ok(OutFrame::Data(data)) => assert_eq!(data, b"new"),
            other => panic!("应当收到实时帧: {other:?}"),
        }

        broadcast.unsubscribe(7);
        assert_eq!(broadcast.subscriber_count(), 0);
    }
}
