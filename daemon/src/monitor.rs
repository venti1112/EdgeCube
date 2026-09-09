//! 系统监控(契约 /monitor/snapshot):CPU / 内存 / 磁盘 / 网络速率 / 开机时长。
//!
//! 数据源为 sysinfo(跨 Windows/Linux/macOS);网络速率为相邻两次快照的
//! 收发字节差 ÷ 时间差(首次快照返回 0,由客户端轮询自然收敛)。
//! 实时曲线走 WS monitor/stats(P1 后续),REST 快照供页面轮询。

use std::time::Instant;

use sysinfo::{Disks, Networks, System};

use serde::Serialize;

/// 相邻快照间隔过短(<200ms)时跳过速率计算,避免毛刺。
const MIN_NET_INTERVAL: std::time::Duration = std::time::Duration::from_millis(200);

/// 系统监控快照(契约 MonitorSnapshot)。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MonitorSnapshot {
    /// 全机 CPU 使用率(0..100)。
    pub cpu_percent: f32,
    pub memory_total_bytes: i64,
    pub memory_used_bytes: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub disks: Option<Vec<MonitorDisk>>,
    /// 接收速率(字节/秒;首次快照为 0)。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub network_rx_bytes_per_sec: Option<i64>,
    /// 发送速率(字节/秒;首次快照为 0)。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub network_tx_bytes_per_sec: Option<i64>,
    /// 系统开机时长(秒)。
    pub uptime_seconds: i64,
}

/// 磁盘用量(契约 disks[])。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MonitorDisk {
    /// 挂载点(如 "/"、"C:\\")。
    pub path: String,
    pub total_bytes: i64,
    pub used_bytes: i64,
}

/// 监控管理器:持有 sysinfo 采样器与上次网络采样(速率差分)。
pub struct MonitorManager {
    sys: std::sync::Mutex<System>,
    disks: std::sync::Mutex<Disks>,
    networks: std::sync::Mutex<Networks>,
    /// 上次网络采样:(时刻, 累计收字节, 累计发字节)。
    last_net: std::sync::Mutex<Option<(Instant, u64, u64)>>,
}

impl Default for MonitorManager {
    fn default() -> Self {
        Self::new()
    }
}

impl MonitorManager {
    pub fn new() -> Self {
        MonitorManager {
            sys: std::sync::Mutex::new(System::new()),
            disks: std::sync::Mutex::new(Disks::new()),
            networks: std::sync::Mutex::new(Networks::new()),
            last_net: std::sync::Mutex::new(None),
        }
    }

    /// 采集一次快照(CPU 使用率需 sysinfo 两次间隔刷新,首次读数为 0,
    /// 由客户端 3s 轮询自然收敛)。
    pub fn snapshot(&self) -> MonitorSnapshot {
        // ── CPU / 内存 ────────────────────────────────────────────
        let (cpu_percent, mem_total, mem_used) = {
            let mut sys = self.sys.lock().unwrap();
            sys.refresh_cpu_usage();
            sys.refresh_memory();
            (
                sys.global_cpu_usage(),
                sys.total_memory(),
                sys.used_memory(),
            )
        };

        // ── 磁盘(挂载点去重,容量>0) ─────────────────────────────
        let disks = {
            let mut disks = self.disks.lock().unwrap();
            disks.refresh(true);
            let mut seen = std::collections::HashSet::new();
            let mut list = Vec::new();
            for disk in disks.list() {
                let total = disk.total_space();
                if total == 0 {
                    continue;
                }
                let path = disk.mount_point().to_string_lossy().into_owned();
                if !seen.insert(path.clone()) {
                    continue;
                }
                list.push(MonitorDisk {
                    path,
                    total_bytes: total as i64,
                    used_bytes: (total - disk.available_space()) as i64,
                });
            }
            list
        };

        // ── 网络速率(与上次快照差分) ─────────────────────────────
        let (rx_rate, tx_rate) = {
            let mut networks = self.networks.lock().unwrap();
            networks.refresh(true);
            let mut total_rx: u64 = 0;
            let mut total_tx: u64 = 0;
            for (_, data) in networks.iter() {
                total_rx += data.total_received();
                total_tx += data.total_transmitted();
            }

            let now = Instant::now();
            let mut last = self.last_net.lock().unwrap();
            let rates = match *last {
                Some((at, prev_rx, prev_tx)) => {
                    let dt = now.duration_since(at);
                    if dt >= MIN_NET_INTERVAL {
                        let secs = dt.as_secs_f64();
                        (
                            ((total_rx.saturating_sub(prev_rx)) as f64 / secs) as i64,
                            ((total_tx.saturating_sub(prev_tx)) as f64 / secs) as i64,
                        )
                    } else {
                        (0, 0)
                    }
                }
                None => (0, 0),
            };
            *last = Some((now, total_rx, total_tx));
            rates
        };

        MonitorSnapshot {
            cpu_percent: cpu_percent.clamp(0.0, 100.0),
            memory_total_bytes: mem_total as i64,
            memory_used_bytes: mem_used as i64,
            disks: (!disks.is_empty()).then_some(disks),
            network_rx_bytes_per_sec: Some(rx_rate),
            network_tx_bytes_per_sec: Some(tx_rate),
            uptime_seconds: System::uptime() as i64,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn snapshot_returns_plausible_values() {
        let mgr = MonitorManager::new();
        let first = mgr.snapshot();
        assert!(first.memory_total_bytes > 0);
        assert!(first.memory_used_bytes > 0);
        assert!(first.memory_used_bytes <= first.memory_total_bytes);
        assert!((0.0..=100.0).contains(&first.cpu_percent));
        assert!(first.uptime_seconds >= 0);
        assert_eq!(first.network_rx_bytes_per_sec, Some(0)); // 首次快照速率为 0

        // 磁盘:至少一块可读盘,used <= total
        let disks = first.disks.unwrap();
        assert!(!disks.is_empty());
        for d in &disks {
            assert!(d.total_bytes > 0);
            assert!(d.used_bytes <= d.total_bytes);
            assert!(!d.path.is_empty());
        }

        // 间隔足够后速率收敛为非负值
        std::thread::sleep(std::time::Duration::from_millis(250));
        let second = mgr.snapshot();
        assert!(second.network_rx_bytes_per_sec.unwrap() >= 0);
        assert!(second.network_tx_bytes_per_sec.unwrap() >= 0);
    }

    #[test]
    fn snapshot_serializes_camel_case() {
        let snap = MonitorSnapshot {
            cpu_percent: 12.5,
            memory_total_bytes: 100,
            memory_used_bytes: 40,
            disks: None,
            network_rx_bytes_per_sec: None,
            network_tx_bytes_per_sec: None,
            uptime_seconds: 7,
        };
        let json = serde_json::to_value(&snap).unwrap();
        assert_eq!(json["cpuPercent"], 12.5);
        assert_eq!(json["memoryTotalBytes"], 100);
        assert_eq!(json["uptimeSeconds"], 7);
        assert!(json.get("disks").is_none()); // None 跳过序列化
    }
}
