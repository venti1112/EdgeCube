//! 打洞实现层：nyat-core 包一层 trait，方便替换与测试。
//!
//! 一次「打洞」= 向某台 STUN 服务器建 TCP 探测连接 + 周期保活，NAT 为本地
//! 端口建立的公网映射经回调上报。nyat-core 的 [`TcpMapper`] 只管到这里；
//! **监听入站与转发**在 [`super::tunnel`] 里自己做（V1 也是这个分工）。
//!
//! 本地端口用 `0.0.0.0:0` 让内核挑（探测连接怎么出、监听就绑哪个端口）——
//! 拿到的实际端口在 [`Mapping::local`] 里给出来（同 V1 的临时端口做法）。

use std::net::{Ipv4Addr, SocketAddr};
use std::time::Duration;

use nyat_core::mapper::{MapperBuilder, MappingInfo};
use nyat_core::net::{IpVer, LocalAddr, RemoteAddr};
use tokio::sync::watch;
use tokio::task::JoinHandle;

use super::settings::parse_host_port;

/// 一次打洞拿到的映射。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Mapping {
    /// NAT 给公网侧分配的端点（玩家连它）。
    pub public: SocketAddr,
    /// 本机实际用的端口（监听要绑它）。
    pub local: SocketAddr,
}

/// 对某台 STUN 服务器打洞的参数。
#[derive(Debug, Clone)]
pub struct MapperSpec {
    /// STUN 服务器 `host[:port]`。
    pub server: String,
    /// TCP 保活用的 HTTP 目标 `host[:port]`。
    pub keepalive_http: String,
    /// 保活 / 探测间隔。
    pub interval: Duration,
}

/// 打洞实现（可替换：nyat-core 是当前实现，测试用假实现）。
pub trait StunMapper: Send + Sync + 'static {
    /// 起一次打洞。映射变化经 `tx` 通知（初始为 `None`）；
    /// 返回的任务结束时表示这次打洞彻底结束（内部重试用尽或致命错误）。
    fn start(
        &self,
        spec: MapperSpec,
    ) -> (
        watch::Receiver<Option<Mapping>>,
        JoinHandle<Result<(), String>>,
    );
}

/// 基于 nyat-core 的真实实现。
pub struct NyatMapper;

impl StunMapper for NyatMapper {
    fn start(
        &self,
        spec: MapperSpec,
    ) -> (
        watch::Receiver<Option<Mapping>>,
        JoinHandle<Result<(), String>>,
    ) {
        let (tx, rx) = watch::channel(None);
        let handle = tokio::spawn(async move {
            let Some((server_host, server_port)) = parse_host_port(&spec.server, 3478) else {
                return Err(format!("STUN 服务器地址为空: {}", spec.server));
            };
            let Some((ka_host, ka_port)) = parse_host_port(&spec.keepalive_http, 80) else {
                return Err(format!("保活目标地址为空: {}", spec.keepalive_http));
            };
            // IPv4 明确优先：隧道面向 IPv4 玩家，绑的也是 IPv4 套接字
            let local = LocalAddr::new(SocketAddr::from((Ipv4Addr::UNSPECIFIED, 0)));
            let stun = RemoteAddr::from_host(server_host, server_port, Some(IpVer::V4));
            let keepalive = RemoteAddr::from_host(ka_host, ka_port, Some(IpVer::V4));
            let mapper = MapperBuilder::new_tcp(local, stun, keepalive)
                .interval(spec.interval)
                .build();
            let mut handler = move |info: MappingInfo| {
                let _ = tx.send_replace(Some(Mapping {
                    public: info.pub_addr,
                    local: info.local_addr,
                }));
            };
            mapper.run(&mut handler).await.map_err(|e| e.to_string())
        });
        (rx, handle)
    }
}

// ══════════════════════════════════════════════════════════════════════════
// 测试用假实现：脚本化「这台服务器什么时候给出什么映射 / 失败 / 挂着」
// ══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
pub mod fake {
    use super::*;
    use std::collections::VecDeque;
    use std::sync::Mutex;

    /// 一次脚本动作。
    #[derive(Debug, Clone)]
    pub enum Step {
        /// 立即给出映射（`local` 端口由测试指定；通常用 `free_port()` 捡）。
        Map(Mapping),
        /// `delay` 之后给出映射（用来演练「限时内没赶上」）。
        MapAfter(Duration, Mapping),
        /// 立即失败。
        Fail(String),
        /// 一直挂着（等上限超时 / 等被 abort）。
        Hang,
    }

    /// 可编程的假打洞器。
    #[derive(Default)]
    pub struct FakeMapper {
        inner: Mutex<FakeInner>,
    }

    #[derive(Default)]
    struct FakeInner {
        script: VecDeque<Step>,
        /// 每次 `start` 收到的参数（断言用）。
        pub calls: Vec<MapperSpec>,
        /// 没脚本时按这个来（缺省「挂着」）。
        pub fallback: Option<Step>,
    }

    impl FakeMapper {
        pub fn new() -> Self {
            Self::default()
        }

        pub fn push(&self, step: Step) {
            self.lock().script.push_back(step);
        }

        pub fn set_fallback(&self, step: Step) {
            self.lock().fallback = Some(step);
        }

        pub fn calls(&self) -> Vec<MapperSpec> {
            self.lock().calls.clone()
        }

        fn lock(&self) -> std::sync::MutexGuard<'_, FakeInner> {
            self.inner.lock().unwrap_or_else(|e| e.into_inner())
        }
    }

    impl StunMapper for FakeMapper {
        fn start(
            &self,
            spec: MapperSpec,
        ) -> (
            watch::Receiver<Option<Mapping>>,
            JoinHandle<Result<(), String>>,
        ) {
            let step = {
                let mut inner = self.lock();
                inner.calls.push(spec);
                inner
                    .script
                    .pop_front()
                    .or_else(|| inner.fallback.clone())
                    .unwrap_or(Step::Hang)
            };
            let (tx, rx) = watch::channel(None);
            let handle = tokio::spawn(async move {
                match step {
                    Step::Map(mapping) => {
                        let _ = tx.send_replace(Some(mapping));
                        std::future::pending::<()>().await;
                        unreachable!()
                    }
                    Step::MapAfter(delay, mapping) => {
                        tokio::time::sleep(delay).await;
                        let _ = tx.send_replace(Some(mapping));
                        std::future::pending::<()>().await;
                        unreachable!()
                    }
                    Step::Fail(message) => Err(message),
                    Step::Hang => {
                        std::future::pending::<()>().await;
                        unreachable!()
                    }
                }
            });
            (rx, handle)
        }
    }

    /// 捡一个当下空闲的端口（先绑 :0 再放开；测试里够用）。
    pub fn free_port() -> u16 {
        let listener = std::net::TcpListener::bind(("127.0.0.1", 0)).expect("应能捡端口");
        listener.local_addr().expect("应能读地址").port()
    }
}
