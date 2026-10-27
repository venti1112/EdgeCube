//! UPnP 传输层：把 igd-next 的**阻塞** API 收成两个 trait。
//!
//! 抽 trait 不是为了抽象而抽象 —— 路由器是没法在测试机房里复现的：
//! 没有它，「映射失败怎么办、端口被占怎么重试、网关错误怎么呈现」这些
//! 逻辑一行都测不了。真实现只有 [`IgdTransport`] / [`Gateway`] 那一小段。
//!
//! 所有方法都是同步阻塞的（SSDP 发现 + SOAP 请求），调用方负责
//! `spawn_blocking` —— 这一层不认识 tokio。

use std::net::{IpAddr, SocketAddr, UdpSocket};
use std::time::Duration;

use igd_next::{PortMappingProtocol, SearchOptions};

/// 传输协议。线上与实例配置里都用这两个小写值。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Protocol {
    Tcp,
    Udp,
}

impl Protocol {
    /// 从配置值解析（大小写不敏感；怪值按 `tcp`，与 `InstanceConfig::upnp_protocol` 一致）。
    pub fn from_config(value: &str) -> Self {
        if value.trim().eq_ignore_ascii_case("udp") {
            Self::Udp
        } else {
            Self::Tcp
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Tcp => "tcp",
            Self::Udp => "udp",
        }
    }

    fn to_igd(self) -> PortMappingProtocol {
        match self {
            Self::Tcp => PortMappingProtocol::TCP,
            Self::Udp => PortMappingProtocol::UDP,
        }
    }
}

/// `add_port` 的失败分类。
///
/// `PortInUse` 单独拎出来是因为它有**专门的补救动作**：先撤掉那个占位的
/// 映射再重试（见 manager）——别的失败重试多少次都一样。
#[derive(Debug)]
pub enum AddPortFailure {
    /// 外部端口已被别的映射占用。
    PortInUse,
    /// 其它失败，原因直接给人看。
    Other(String),
}

/// 网关句柄：加映射 / 撤映射 / 查公网 IP。
///
/// 都是阻塞调用；实现要 `Send + Sync`（会被塞进 `spawn_blocking`）。
pub trait GatewayOps: Send + Sync + 'static {
    /// 网关看到的公网地址。
    fn external_ip(&self) -> Result<IpAddr, String>;
    /// 加一条端口映射。租约固定**永久**（与 V1 行为一致，路由器侧不会自己过期）。
    fn add_port(
        &self,
        protocol: Protocol,
        external_port: u16,
        local_addr: SocketAddr,
        description: &str,
    ) -> Result<(), AddPortFailure>;
    /// 撤一条端口映射。`NoSuchPortMapping` 也算成功（本来就没有）。
    fn remove_port(&self, protocol: Protocol, external_port: u16) -> Result<(), String>;
}

/// 发现网关。
pub trait UpnpTransport: Send + Sync + 'static {
    fn discover(&self) -> Result<FoundGateway, String>;
}

/// 一次成功发现的产物。
pub struct FoundGateway {
    pub ops: std::sync::Arc<dyn GatewayOps>,
    /// 网关自己的地址（展示用）。
    pub address: SocketAddr,
    /// 本机在网关那一侧的内网地址（加映射时的 local_addr 要它）。
    pub local_ip: IpAddr,
}

/// 真实现：igd-next。
pub struct IgdTransport;

/// SSDP 默认 10 秒太长 —— 点「重新探测」的人不会等那么久，而局域网上
/// 网关的响应是毫秒级的；3 秒还收不到，基本就是没有（或没开 UPnP）。
const DISCOVER_TIMEOUT: Duration = Duration::from_secs(3);

/// 映射条目的描述（路由器管理页里显示的那串）。与 V1 一致。
pub const MAPPING_DESCRIPTION: &str = "EdgeCube MC Server";

impl UpnpTransport for IgdTransport {
    fn discover(&self) -> Result<FoundGateway, String> {
        let options = SearchOptions {
            timeout: Some(DISCOVER_TIMEOUT),
            ..Default::default()
        };
        let gateway = igd_next::search_gateway(options)
            .map_err(|e| format!("没有发现 UPnP 网关（路由器可能未开启 UPnP）：{e}"))?;
        let address = gateway.addr;
        let local_ip = local_ip_for(address).map_err(|e| format!("确定本机内网地址失败：{e}"))?;
        Ok(FoundGateway {
            ops: std::sync::Arc::new(gateway),
            address,
            local_ip,
        })
    }
}

/// 本机在网关那一侧的地址：UDP「连一下」网关，让内核选出走哪张网卡。
///
/// 没有真的发包（UDP connect 只是记下路由），但拿到的正是网关能回连的地址。
fn local_ip_for(target: SocketAddr) -> std::io::Result<IpAddr> {
    let bind: SocketAddr = if target.is_ipv4() {
        SocketAddr::from(([0, 0, 0, 0], 0))
    } else {
        SocketAddr::from((std::net::Ipv6Addr::UNSPECIFIED, 0))
    };
    let socket = UdpSocket::bind(bind)?;
    socket.connect(target)?;
    Ok(socket.local_addr()?.ip())
}

impl GatewayOps for igd_next::Gateway {
    fn external_ip(&self) -> Result<IpAddr, String> {
        self.get_external_ip().map_err(|e| e.to_string())
    }

    fn add_port(
        &self,
        protocol: Protocol,
        external_port: u16,
        local_addr: SocketAddr,
        description: &str,
    ) -> Result<(), AddPortFailure> {
        // 租约 0 = 永久。V1 与 port_forwarder 都是这么做的：路由器不会
        // 自己把映射过期掉，「停止实例时撤销」由我们负责。
        match igd_next::Gateway::add_port(
            self,
            protocol.to_igd(),
            external_port,
            local_addr,
            0,
            description,
        ) {
            Ok(()) => Ok(()),
            Err(igd_next::AddPortError::PortInUse) => Err(AddPortFailure::PortInUse),
            Err(e) => Err(AddPortFailure::Other(e.to_string())),
        }
    }

    fn remove_port(&self, protocol: Protocol, external_port: u16) -> Result<(), String> {
        match igd_next::Gateway::remove_port(self, protocol.to_igd(), external_port) {
            Ok(()) => Ok(()),
            // 本来就没有 → 撤销的目标达成
            Err(igd_next::RemovePortError::NoSuchPortMapping) => Ok(()),
            Err(e) => Err(e.to_string()),
        }
    }
}
