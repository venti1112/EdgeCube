//! 带上限（TTL）的内存缓存。
//!
//! 打上游的只读数据常常「变得很慢、但问得很勤」—— 服务端版本列表、加载器列表、
//! 运行环境的版本清单。每个客户端各打一遍上游既慢又可能撞上速率限制
//! （GitHub 未认证只有 60 次/小时），所以在模块里按 key 缓存一小会儿。
//!
//! 两个使用方：
//!
//! * `mcserver` —— 三类版本列表（ttl 来自模块配置）；
//! * `runtime` —— frp 的 GitHub release 清单（同一个 TTL）。
//!
//! **不做主动过期清理**：条目只在被查到时判定过期，过期的旧值留在表里直到
//! 被同一个 key 覆盖。这类缓存的 key 数量是个位数，留着不碍事。

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use crate::util::now_ms;

/// 按 key 的 TTL 缓存。
pub struct Cache<T> {
    ttl_ms: u64,
    entries: Mutex<HashMap<String, (u64, Arc<T>)>>,
}

impl<T> Cache<T> {
    /// `ttl_secs = 0` 表示不缓存（永远不命中，也不写入）。
    pub fn new(ttl_secs: u64) -> Self {
        Self {
            ttl_ms: ttl_secs.saturating_mul(1000),
            entries: Mutex::new(HashMap::new()),
        }
    }

    /// 命中且没过期就返回。
    pub fn get(&self, key: &str) -> Option<Arc<T>> {
        if self.ttl_ms == 0 {
            return None;
        }
        let entries = self.entries.lock().unwrap_or_else(|e| e.into_inner());
        let (at_ms, value) = entries.get(key)?;
        (now_ms().saturating_sub(*at_ms) < self.ttl_ms).then(|| Arc::clone(value))
    }

    pub fn put(&self, key: impl Into<String>, value: Arc<T>) {
        if self.ttl_ms == 0 {
            return;
        }
        self.entries
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .insert(key.into(), (now_ms(), value));
    }

    /// 丢掉一个 key（数据明显变了时用，比如刚装完一个新版本）。
    pub fn forget(&self, key: &str) {
        self.entries
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .remove(key);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hits_within_ttl_and_misses_after() {
        let cache: Cache<Vec<u32>> = Cache::new(60);
        assert!(cache.get("a").is_none());

        cache.put("a", Arc::new(vec![1, 2]));
        assert_eq!(cache.get("a").unwrap().as_slice(), &[1, 2]);
        // 别的 key 不受影响
        assert!(cache.get("b").is_none());

        // 0 TTL = 从不缓存
        let off: Cache<u32> = Cache::new(0);
        off.put("a", Arc::new(1));
        assert!(off.get("a").is_none());
    }

    #[test]
    fn forget_drops_the_entry() {
        let cache: Cache<u32> = Cache::new(60);
        cache.put("a", Arc::new(1));
        assert!(cache.get("a").is_some());
        cache.forget("a");
        assert!(cache.get("a").is_none());
    }
}
