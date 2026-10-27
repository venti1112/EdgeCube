//! PROXY protocol v2 头部构造（HAProxy 规范）。
//!
//! 隧道转发会让服务端只看到 `127.0.0.1`，开启后在转发的第一批字节前插入本
//! 头部，服务端（Velocity / Paper 等，需自行开启 `proxy_protocol`）便能拿到
//! 玩家真实 IP。服务端未开启时会把这些字节当作协议数据，导致玩家无法进入，
//! 故默认关闭。
//!
//! 逐字节照抄 V1 的 `lib/stun/proxy_protocol.dart`（含 IPv4-mapped 补齐规则）。

use std::net::SocketAddr;

/// 12 字节固定签名。
const SIGNATURE: [u8; 12] = [
    0x0D, 0x0A, 0x0D, 0x0A, 0x00, 0x0D, 0x0A, 0x51, 0x55, 0x49, 0x54, 0x0A,
];

/// 构造一条 TCP 连接的 PROXY v2 头部。
///
/// `src` = 玩家真实来源（accept 到的对端），`dst` = 玩家实际连上的本地监听
/// 端点（accept 到的本端）。源与目的地址族不一致（极少见）时按 IPv6 处理，
/// IPv4 地址会被映射为 `::ffff:a.b.c.d`。
pub fn build_header(src: SocketAddr, dst: SocketAddr) -> Vec<u8> {
    let is_ipv4 = src.is_ipv4() && dst.is_ipv4();
    let address_length: u16 = if is_ipv4 { 12 } else { 36 };
    let mut header = Vec::with_capacity(16 + address_length as usize);
    header.extend_from_slice(&SIGNATURE);
    header.push(0x21); // 版本 2（高 4 位）+ PROXY 命令（低 4 位）
    header.push(if is_ipv4 { 0x11 } else { 0x21 }); // TCP over IPv4 / TCP over IPv6
    header.push((address_length >> 8) as u8);
    header.push((address_length & 0xFF) as u8);

    header.extend_from_slice(&raw_address(src, is_ipv4));
    header.extend_from_slice(&raw_address(dst, is_ipv4));
    header.extend_from_slice(&src.port().to_be_bytes());
    header.extend_from_slice(&dst.port().to_be_bytes());
    header
}

/// 取地址原始字节；IPv6 头部里的 IPv4 地址按 IPv4-mapped 形式补齐到 16 字节。
fn raw_address(addr: SocketAddr, ipv4_header: bool) -> Vec<u8> {
    match addr {
        SocketAddr::V4(v4) => {
            if ipv4_header {
                v4.ip().octets().to_vec()
            } else {
                let mut mapped = vec![0u8; 16];
                mapped[10] = 0xFF;
                mapped[11] = 0xFF;
                mapped[12..16].copy_from_slice(&v4.ip().octets());
                mapped
            }
        }
        SocketAddr::V6(v6) => v6.ip().octets().to_vec(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ipv4_header_matches_v1_byte_layout() {
        let src: SocketAddr = "203.0.113.7:51000".parse().unwrap();
        let dst: SocketAddr = "192.168.1.100:25565".parse().unwrap();
        let header = build_header(src, dst);

        assert_eq!(header.len(), 16 + 12);
        assert_eq!(
            &header[..12],
            &[
                0x0D, 0x0A, 0x0D, 0x0A, 0x00, 0x0D, 0x0A, 0x51, 0x55, 0x49, 0x54, 0x0A
            ]
        );
        assert_eq!(header[12], 0x21);
        assert_eq!(header[13], 0x11, "TCP over IPv4");
        assert_eq!(&header[14..16], &[0x00, 0x0C], "地址长度 12");
        assert_eq!(&header[16..20], &[203, 0, 113, 7]);
        assert_eq!(&header[20..24], &[192, 168, 1, 100]);
        assert_eq!(&header[24..26], &51000u16.to_be_bytes());
        assert_eq!(&header[26..28], &25565u16.to_be_bytes());
    }

    #[test]
    fn ipv6_header_pads_mapped_addresses() {
        let src: SocketAddr = "[2001:db8::1]:51000".parse().unwrap();
        let dst: SocketAddr = "[2001:db8::2]:25565".parse().unwrap();
        let header = build_header(src, dst);
        assert_eq!(header.len(), 16 + 36);
        assert_eq!(header[13], 0x21, "TCP over IPv6");
        assert_eq!(&header[14..16], &[0x00, 0x24], "地址长度 36");

        // 地址族不一致：IPv4 按 ::ffff: 补齐
        let v4: SocketAddr = "203.0.113.7:1".parse().unwrap();
        let header = build_header(v4, dst);
        assert_eq!(header[13], 0x21);
        assert_eq!(&header[16..26], &[0u8; 10]);
        assert_eq!(&header[26..28], &[0xFF, 0xFF]);
        assert_eq!(&header[28..32], &[203, 0, 113, 7]);
    }
}
