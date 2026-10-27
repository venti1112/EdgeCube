//! STUN 隧道测试：用假打洞器（`FakeMapper`）把状态机与转发全流程打一遍。
//!
//! 覆盖：播种只收开着开关的实例、启动→就绪、停止、探测全挂的失败终态
//! （含「不自动重试」与「改设置救回」）、配置变更重启、删除收尾、
//! 设置保存重灌、绑定失败路径、以及带 PROXY v2 头的真实转发 + 流量计数。

use std::net::{Ipv4Addr, SocketAddr};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;

use serde_json::{Value, json};
use tokio::io::{AsyncReadExt, AsyncWriteExt};

use super::TunnelManager;
use super::mapper::Mapping;
use super::mapper::fake::{FakeMapper, Step, free_port};
use super::settings::{StunSettings, StunStore};
use super::tunnel::Tuning;
use crate::event::EventBus;
use crate::module::builtin::instance::model::{InstanceConfig, InstanceSummary};
use crate::module::builtin::instance::process::TOPIC_PHASE;
use crate::module::builtin::instance::store::InstanceStore;
use crate::module::builtin::instance::{TOPIC_DELETED, TOPIC_UPDATED};
use crate::util::now_ms;

// ── 临时实例目录 ─────────────────────────────────────────────────────────

struct TempRoot(PathBuf);

impl TempRoot {
    fn new(tag: &str) -> Self {
        let root = std::env::temp_dir().join(format!(
            "edgecube-stun-{tag}-{}-{}",
            std::process::id(),
            now_ms()
        ));
        std::fs::create_dir_all(&root).expect("应能建临时目录");
        Self(root)
    }

    fn path(&self) -> &Path {
        &self.0
    }

    /// 往磁盘上摆一个实例（元数据 + 索引 + 工作目录）。
    fn add_instance(
        &self,
        id: &str,
        name: &str,
        enabled: bool,
        proxy: bool,
        target: Option<u16>,
    ) -> PathBuf {
        let store = InstanceStore::new(&self.0);
        store.ensure_dirs().expect("目录");
        let config = InstanceConfig {
            id: id.to_string(),
            name: name.to_string(),
            stun_enabled: enabled,
            stun_proxy_protocol: proxy,
            stun_target_port: target,
            ..Default::default()
        };
        store.write_config(&config).expect("写元数据");
        let mut index = store.read_index();
        if !index.contains(id) {
            index.instances.push(InstanceSummary::new(id, name));
            store.write_index(&index).expect("写索引");
        }
        let dir = store.default_dir(id);
        std::fs::create_dir_all(&dir).expect("实例目录");
        dir
    }

    /// 模拟用户在实例设置里改了 STUN 配置。
    fn update(&self, id: &str, f: impl FnOnce(&mut InstanceConfig)) {
        let store = InstanceStore::new(&self.0);
        let mut config = store.read_config(id).expect("读元数据").expect("实例存在");
        f(&mut config);
        store.write_config(&config).expect("写元数据");
    }

    /// 从索引里摘掉（模拟删除；`TOPIC_DELETED` 的处理不读盘）。
    fn remove(&self, id: &str) {
        let store = InstanceStore::new(&self.0);
        let mut index = store.read_index();
        index.instances.retain(|summary| summary.id != id);
        store.write_index(&index).expect("写索引");
    }

    fn write_settings(&self, settings: &StunSettings) {
        StunStore::new(self.0.join("config").join("stun"))
            .write_settings(settings)
            .expect("写设置");
    }

    fn settings_store(&self) -> StunStore {
        StunStore::new(self.0.join("config").join("stun"))
    }
}

impl Drop for TempRoot {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

// ── 工具 ─────────────────────────────────────────────────────────────────

/// 测试用时序：把 V1 的 15/5/3 秒都压到毫秒级。
fn fast_tuning() -> Tuning {
    Tuning {
        establish_timeout: Duration::from_secs(2),
        retry_delay: Duration::from_millis(30),
        bind_retry_delay: Duration::from_millis(30),
        rebuild_delay: Duration::from_millis(30),
        max_failures: 3,
    }
}

fn manager_for(root: &TempRoot, mapper: &Arc<FakeMapper>) -> Arc<TunnelManager> {
    let manager = Arc::new(TunnelManager::with_tuning(
        EventBus::new(64),
        root.path().to_path_buf(),
        mapper.clone(),
        fast_tuning(),
    ));
    manager.remember();
    manager
}

async fn seed(manager: &TunnelManager) {
    let _guard = manager.ops.lock().await;
    manager.reconcile_locked().await;
}

async fn wait_for(mut cond: impl FnMut() -> bool) -> bool {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(5);
    loop {
        if cond() {
            return true;
        }
        if tokio::time::Instant::now() >= deadline {
            return false;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
}

fn row<'a>(status: &'a Value, id: &str) -> &'a Value {
    status["tunnels"]
        .as_array()
        .expect("tunnels 该是数组")
        .iter()
        .find(|row| row["instance_id"] == json!(id))
        .unwrap_or_else(|| panic!("状态里该有 {id}: {status}"))
}

fn log_text(manager: &TunnelManager) -> String {
    manager.logs_json()["lines"]
        .as_array()
        .expect("lines 该是数组")
        .iter()
        .map(|line| line["text"].as_str().unwrap_or_default())
        .collect::<Vec<_>>()
        .join("\n")
}

fn map_step(port: u16, public: &str) -> Step {
    Step::Map(Mapping {
        public: public.parse().expect("测试公网地址"),
        local: SocketAddr::from((Ipv4Addr::UNSPECIFIED, port)),
    })
}

fn phase(id: &str, value: &str) -> Value {
    json!({ "id": id, "phase": value })
}

// ── 状态机 ───────────────────────────────────────────────────────────────

#[tokio::test]
async fn seeds_only_enabled_instances() {
    let root = TempRoot::new("seed");
    root.add_instance("aaaa", "开着", true, false, None);
    root.add_instance("bbbb", "关着", false, false, None);
    let mapper = Arc::new(FakeMapper::new());
    let manager = manager_for(&root, &mapper);

    assert_eq!(manager.status_json()["count"], json!(0), "播种前没有行");

    seed(&manager).await;
    let status = manager.status_json();
    assert_eq!(status["count"], json!(1));
    assert_eq!(row(&status, "aaaa")["state"], json!("idle"));
    assert_eq!(row(&status, "aaaa")["enabled"], json!(true));
    // 留空覆盖时给服务端实际端口（没配置文件 → 25565）
    assert_eq!(row(&status, "aaaa")["target_port"], json!(25565));
    // 实例没在跑：不该有任何打洞尝试
    assert!(mapper.calls().is_empty());
    // 设置随总览一起给（生效列表 = 内置 8 台）
    assert_eq!(status["settings"]["servers"].as_array().unwrap().len(), 8);
    assert_eq!(status["settings"]["keep_alive_seconds"], json!(20));
}

#[tokio::test]
async fn starting_instance_builds_tunnel() {
    let root = TempRoot::new("run");
    let port = free_port();
    root.add_instance("aaaa", "主服", true, false, Some(25570));
    let mapper = Arc::new(FakeMapper::new());
    mapper.push(map_step(port, "203.0.113.7:40000"));
    let manager = manager_for(&root, &mapper);
    seed(&manager).await;

    manager
        .handle_event(TOPIC_PHASE, &phase("aaaa", "starting"))
        .await;
    assert!(
        wait_for(|| row(&manager.status_json(), "aaaa")["state"] == json!("running")).await,
        "隧道该就绪: {}",
        manager.status_json()
    );

    let status = manager.status_json();
    let tunnel_row = row(&status, "aaaa");
    assert_eq!(tunnel_row["running"], json!(true));
    assert_eq!(tunnel_row["public_address"], json!("203.0.113.7:40000"));
    assert_eq!(tunnel_row["local_port"], json!(port));
    assert_eq!(tunnel_row["target_port"], json!(25570));
    assert_eq!(tunnel_row["max_connections"], json!(128));

    // 打洞参数：默认设置的第一台服务器 + 20 秒保活间隔
    let calls = mapper.calls();
    assert_eq!(calls.len(), 1, "{calls:?}");
    assert_eq!(calls[0].server, "fwa.lifesizecloud.com");
    assert_eq!(calls[0].interval, Duration::from_secs(20));

    // 日志文案（V1 同款）
    let text = log_text(&manager);
    assert!(text.contains("隧道启动中，本地目标端口 25570"), "{text}");
    assert!(
        text.contains(&format!(
            "隧道已就绪：tcp://127.0.0.1:25570 → tcp://0.0.0.0:{port}"
        )),
        "{text}"
    );
    assert!(text.contains("公网直连地址：203.0.113.7:40000"), "{text}");

    // 停止：行留着但回到 idle，日志有停止文案
    manager
        .handle_event(TOPIC_PHASE, &phase("aaaa", "stopped"))
        .await;
    let status = manager.status_json();
    assert_eq!(row(&status, "aaaa")["state"], json!("idle"));
    assert_eq!(row(&status, "aaaa")["running"], json!(false));
    assert!(log_text(&manager).contains("隧道已停止"));
}

#[tokio::test]
async fn probe_failures_end_in_failed_state() {
    let root = TempRoot::new("fail");
    root.add_instance("aaaa", "主服", true, false, None);
    root.write_settings(&StunSettings {
        servers: vec!["s1.example".to_string(), "s2.example".to_string()],
        ..StunSettings::default()
    });
    let mapper = Arc::new(FakeMapper::new());
    mapper.set_fallback(Step::Fail("boom".to_string()));
    let manager = manager_for(&root, &mapper);
    seed(&manager).await;

    manager
        .handle_event(TOPIC_PHASE, &phase("aaaa", "starting"))
        .await;
    assert!(
        wait_for(|| row(&manager.status_json(), "aaaa")["state"] == json!("failed")).await,
        "该进失败终态: {}",
        manager.status_json()
    );

    let status = manager.status_json();
    assert!(
        row(&status, "aaaa")["error"]
            .as_str()
            .unwrap_or_default()
            .contains("对称 NAT"),
        "{status}"
    );
    // 2 台服务器 × 3 轮
    assert_eq!(mapper.calls().len(), 6);

    // 终态不再自动重试
    tokio::time::sleep(Duration::from_millis(150)).await;
    assert_eq!(mapper.calls().len(), 6);

    let text = log_text(&manager);
    assert!(text.contains("STUN [s1.example] 不可用：boom"), "{text}");
    assert!(text.contains("本轮探测失败"), "{text}");
    assert!(text.contains("隧道启动失败"), "{text}");

    // 改全局设置 = 强灌一次：这次脚本给成功
    let port = free_port();
    mapper.push(map_step(port, "203.0.113.7:40000"));
    let mut next = manager.settings();
    next.keep_alive_seconds = 30;
    manager.set_settings(next).await.expect("应能保存设置");
    assert!(
        wait_for(|| row(&manager.status_json(), "aaaa")["state"] == json!("running")).await,
        "改设置后该救回来: {}",
        manager.status_json()
    );
}

#[tokio::test]
async fn turning_on_proxy_restarts_running_tunnel() {
    let root = TempRoot::new("restart");
    let port_a = free_port();
    let port_b = free_port();
    root.add_instance("aaaa", "主服", true, false, Some(25570));
    let mapper = Arc::new(FakeMapper::new());
    mapper.push(map_step(port_a, "203.0.113.7:40000"));
    mapper.push(map_step(port_b, "203.0.113.7:41000"));
    let manager = manager_for(&root, &mapper);
    seed(&manager).await;
    manager
        .handle_event(TOPIC_PHASE, &phase("aaaa", "starting"))
        .await;
    assert!(wait_for(|| row(&manager.status_json(), "aaaa")["local_port"] == json!(port_a)).await);

    // 打开 PROXY protocol → 该重建
    root.update("aaaa", |config| config.stun_proxy_protocol = true);
    manager
        .handle_event(TOPIC_UPDATED, &json!({ "id": "aaaa" }))
        .await;
    assert!(
        wait_for(|| row(&manager.status_json(), "aaaa")["local_port"] == json!(port_b)).await,
        "该用新参数重建: {}",
        manager.status_json()
    );
    assert_eq!(mapper.calls().len(), 2);
}

#[tokio::test]
async fn disabling_keeps_row_but_stops_tunnel() {
    let root = TempRoot::new("disable");
    let port = free_port();
    root.add_instance("aaaa", "主服", true, false, Some(25570));
    let mapper = Arc::new(FakeMapper::new());
    mapper.push(map_step(port, "203.0.113.7:40000"));
    let manager = manager_for(&root, &mapper);
    seed(&manager).await;
    manager
        .handle_event(TOPIC_PHASE, &phase("aaaa", "starting"))
        .await;
    assert!(wait_for(|| row(&manager.status_json(), "aaaa")["state"] == json!("running")).await);

    root.update("aaaa", |config| config.stun_enabled = false);
    manager
        .handle_event(TOPIC_UPDATED, &json!({ "id": "aaaa" }))
        .await;
    let status = manager.status_json();
    assert_eq!(status["count"], json!(1), "行留着（显示为关着）");
    assert_eq!(row(&status, "aaaa")["enabled"], json!(false));
    assert_eq!(row(&status, "aaaa")["state"], json!("idle"));
    assert!(log_text(&manager).contains("隧道已停止"));
}

#[tokio::test]
async fn deleting_instance_forgets_row() {
    let root = TempRoot::new("delete");
    let port = free_port();
    root.add_instance("aaaa", "主服", true, false, Some(25570));
    let mapper = Arc::new(FakeMapper::new());
    mapper.push(map_step(port, "203.0.113.7:40000"));
    let manager = manager_for(&root, &mapper);
    seed(&manager).await;
    manager
        .handle_event(TOPIC_PHASE, &phase("aaaa", "starting"))
        .await;
    assert!(wait_for(|| row(&manager.status_json(), "aaaa")["state"] == json!("running")).await);

    root.remove("aaaa");
    manager
        .handle_event(TOPIC_DELETED, &json!({ "id": "aaaa" }))
        .await;
    let status = manager.status_json();
    assert_eq!(status["count"], json!(0));
    assert!(log_text(&manager).contains("隧道已停止"));
}

#[tokio::test]
async fn saving_settings_restarts_and_persists() {
    let root = TempRoot::new("settings");
    let port_a = free_port();
    let port_b = free_port();
    root.add_instance("aaaa", "主服", true, false, Some(25570));
    let mapper = Arc::new(FakeMapper::new());
    mapper.push(map_step(port_a, "203.0.113.7:40000"));
    mapper.push(map_step(port_b, "203.0.113.7:41000"));
    let manager = manager_for(&root, &mapper);
    seed(&manager).await;
    manager
        .handle_event(TOPIC_PHASE, &phase("aaaa", "starting"))
        .await;
    assert!(wait_for(|| row(&manager.status_json(), "aaaa")["local_port"] == json!(port_a)).await);

    let mut next = manager.settings();
    next.servers = vec!["custom.example".to_string()];
    next.keep_alive_seconds = 45;
    manager.set_settings(next).await.expect("应能保存设置");

    assert!(
        wait_for(|| row(&manager.status_json(), "aaaa")["local_port"] == json!(port_b)).await,
        "该按新参数重建: {}",
        manager.status_json()
    );
    let calls = mapper.calls();
    assert_eq!(calls.len(), 2);
    assert_eq!(calls[1].server, "custom.example");
    assert_eq!(calls[1].interval, Duration::from_secs(45));

    // 落盘了（下次 daemon 启动读得到）
    let back = root.settings_store().read_settings();
    assert_eq!(back.servers, vec!["custom.example".to_string()]);
    assert_eq!(back.keep_alive_seconds, 45);
}

#[cfg(unix)]
#[tokio::test]
async fn bind_failure_ends_failed_after_rounds() {
    let root = TempRoot::new("bind");
    root.add_instance("aaaa", "主服", true, false, Some(25570));
    root.write_settings(&StunSettings {
        servers: vec!["s1.example".to_string()],
        ..StunSettings::default()
    });
    // 占着端口不放：SO_REUSEPORT 单边设置绑不上去（Linux/macOS 语义）
    let blocker = std::net::TcpListener::bind(("0.0.0.0", 0)).expect("占位监听");
    let blocked_port = blocker.local_addr().expect("读地址").port();
    let mapper = Arc::new(FakeMapper::new());
    mapper.push(map_step(blocked_port, "203.0.113.7:40000"));
    mapper.set_fallback(map_step(blocked_port, "203.0.113.7:40000"));
    let manager = manager_for(&root, &mapper);
    seed(&manager).await;

    manager
        .handle_event(TOPIC_PHASE, &phase("aaaa", "starting"))
        .await;
    assert!(
        wait_for(|| row(&manager.status_json(), "aaaa")["state"] == json!("failed")).await,
        "该进失败终态: {}",
        manager.status_json()
    );
    let status = manager.status_json();
    assert!(
        row(&status, "aaaa")["error"]
            .as_str()
            .unwrap_or_default()
            .contains("建立监听"),
        "{status}"
    );
    let text = log_text(&manager);
    assert!(
        text.contains(&format!("绑定本地端口 {blocked_port} 失败")),
        "{text}"
    );
    drop(blocker);
}

// ── 转发（真套接字） ─────────────────────────────────────────────────────

#[tokio::test]
async fn forwards_inbound_connections_with_proxy_header() {
    let root = TempRoot::new("forward");
    // 后端：真实监听 + 先验 PROXY v2 头、再把 4 字节数据回显
    let backend = tokio::net::TcpListener::bind(("127.0.0.1", 0))
        .await
        .expect("后端监听");
    let backend_port = backend.local_addr().expect("后端地址").port();
    let echo = tokio::spawn(async move {
        let (mut stream, _) = backend.accept().await.expect("应有一条入站");
        // TCP4 的 PROXY v2 头共 28 字节（16 固定 + 12 地址块）
        let mut header = [0u8; 28];
        stream.read_exact(&mut header).await.expect("该有 PROXY 头");
        assert_eq!(
            &header[..12],
            &[
                0x0D, 0x0A, 0x0D, 0x0A, 0x00, 0x0D, 0x0A, 0x51, 0x55, 0x49, 0x54, 0x0A
            ],
            "签名"
        );
        assert_eq!(header[12], 0x21, "version + PROXY 命令");
        assert_eq!(header[13], 0x11, "TCP over IPv4");
        assert_eq!(
            u16::from_be_bytes([header[14], header[15]]),
            12,
            "地址块长度"
        );
        assert_eq!(&header[16..20], &[127, 0, 0, 1], "src 地址");
        assert_eq!(&header[20..24], &[127, 0, 0, 1], "dst 地址");
        let mut buf = [0u8; 4];
        stream.read_exact(&mut buf).await.expect("该有数据");
        stream.write_all(&buf).await.expect("回显");
    });

    let port = free_port();
    root.add_instance("aaaa", "主服", true, true, Some(backend_port));
    let mapper = Arc::new(FakeMapper::new());
    mapper.push(map_step(port, "203.0.113.7:40000"));
    let manager = manager_for(&root, &mapper);
    seed(&manager).await;
    manager
        .handle_event(TOPIC_PHASE, &phase("aaaa", "starting"))
        .await;
    assert!(wait_for(|| row(&manager.status_json(), "aaaa")["state"] == json!("running")).await);

    // 玩家侧连「公网端口」（测试里就是本机监听端口）
    let mut client = tokio::net::TcpStream::connect(("127.0.0.1", port))
        .await
        .expect("连隧道端口");
    client.write_all(b"ping").await.expect("发送");
    let mut back = [0u8; 4];
    tokio::time::timeout(Duration::from_secs(3), client.read_exact(&mut back))
        .await
        .expect("回包超时")
        .expect("读回包");
    assert_eq!(&back, b"ping");
    echo.await.expect("后端任务");

    // 流量计数：下行 = 玩家 → 服务端；上行 = 服务端 → 玩家
    assert!(
        wait_for(|| row(&manager.status_json(), "aaaa")["total_down"]
            .as_u64()
            .unwrap_or(0)
            >= 4)
        .await,
        "下行该计数: {}",
        manager.status_json()
    );
    assert!(
        wait_for(|| row(&manager.status_json(), "aaaa")["total_up"]
            .as_u64()
            .unwrap_or(0)
            >= 4)
        .await,
        "上行该计数: {}",
        manager.status_json()
    );

    let text = log_text(&manager);
    assert!(text.contains("入站连接 127.0.0.1:"), "{text}");
}

#[tokio::test]
async fn logs_capture_and_clear() {
    let root = TempRoot::new("logs");
    let port = free_port();
    root.add_instance("aaaa", "主服", true, false, Some(25570));
    let mapper = Arc::new(FakeMapper::new());
    mapper.push(map_step(port, "203.0.113.7:40000"));
    let manager = manager_for(&root, &mapper);
    seed(&manager).await;
    manager
        .handle_event(TOPIC_PHASE, &phase("aaaa", "starting"))
        .await;
    assert!(wait_for(|| row(&manager.status_json(), "aaaa")["state"] == json!("running")).await);

    let logs = manager.logs_json();
    assert!(logs["count"].as_u64().unwrap_or(0) > 0);
    // 行上带实例归属
    let first = &logs["lines"][0];
    assert_eq!(first["instance_id"], json!("aaaa"));
    assert_eq!(first["instance_name"], json!("主服"));
    assert!(first["time_ms"].as_u64().unwrap_or(0) > 0);

    let cleared = manager.clear_logs();
    assert!(cleared["cleared"].as_u64().unwrap_or(0) > 0);
    assert_eq!(manager.logs_json()["count"], json!(0));
}
