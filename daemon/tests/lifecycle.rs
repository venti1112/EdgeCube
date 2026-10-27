//! 就绪文件与父进程看门狗的端到端行为（真实二进制）。
//!
//! 这两项是「App 拉起本地 daemon」的握手基础：
//! 前端靠就绪文件拿实际端口，靠看门狗保证 App 被杀后不留下孤儿进程。

use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use edgecube_daemon::VERSION;
use edgecube_daemon::lifecycle::process_alive;

const BIN: &str = env!("CARGO_BIN_EXE_edgecube-daemon");

struct TempDir(PathBuf);

impl TempDir {
    fn new(tag: &str) -> Self {
        let dir = std::env::temp_dir().join(format!(
            "edgecube-lifecycle-test-{tag}-{}-{}",
            std::process::id(),
            edgecube_daemon::util::now_ms()
        ));
        std::fs::create_dir_all(&dir).expect("应能建临时目录");
        Self(dir)
    }

    fn join(&self, name: &str) -> PathBuf {
        self.0.join(name)
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

/// 隔离环境的 daemon 命令（不碰真实 ~/.config 与仓库配置）。
fn command(dir: &TempDir) -> Command {
    let mut cmd = Command::new(BIN);
    cmd.current_dir(&dir.0)
        .env("XDG_CONFIG_HOME", dir.join("xdg"))
        .env("HOME", dir.join("home"))
        .env_remove("EDGECUBE_CONFIG")
        .env_remove("EDGECUBE_HOST")
        .env_remove("EDGECUBE_PORT")
        .env_remove("EDGECUBE_TOKEN")
        .env_remove("EDGECUBE_LOG_LEVEL")
        .env_remove("EDGECUBE_LOG_FORMAT")
        .env_remove("EDGECUBE_NO_COLOR");
    cmd
}

fn wait_for_file(path: &Path, timeout: Duration) -> bool {
    let deadline = Instant::now() + timeout;
    while Instant::now() < deadline {
        if path.is_file() {
            return true;
        }
        std::thread::sleep(Duration::from_millis(50));
    }
    false
}

fn read_json(path: &Path) -> serde_json::Value {
    serde_json::from_slice(&std::fs::read(path).expect("应能读就绪文件"))
        .expect("就绪文件应是 JSON")
}

fn diagnostics(out: &Path) -> String {
    std::fs::read_to_string(out).unwrap_or_default()
}

#[test]
fn ready_file_reports_the_real_port_and_is_removed_on_shutdown() {
    let dir = TempDir::new("ready");
    let ready = dir.join("ready.json");
    let log = dir.join("daemon.log");

    let mut child = command(&dir)
        .args([
            "--host",
            "127.0.0.1",
            "--port",
            "0",
            "--no-color",
            "--ready-file",
            &ready.to_string_lossy(),
        ])
        .stdout(Stdio::from(std::fs::File::create(&log).unwrap()))
        .stderr(Stdio::from(
            std::fs::File::create(dir.join("daemon.err")).unwrap(),
        ))
        .spawn()
        .expect("应能启动 daemon");

    if !wait_for_file(&ready, Duration::from_secs(15)) {
        let _ = child.kill();
        panic!("15s 内没写出就绪文件；日志:\n{}", diagnostics(&log));
    }

    let value = read_json(&ready);
    assert_eq!(value["pid"], child.id());
    assert_eq!(value["version"], VERSION);
    assert_eq!(value["host"], "127.0.0.1");
    let port = value["port"].as_u64().expect("port 应是整数");
    assert!(port > 0, "port = 0 时应写入系统分配的真实端口");
    assert_eq!(value["addr"], format!("127.0.0.1:{port}"));
    assert!(
        value["ws_path"]
            .as_str()
            .is_some_and(|p| p.starts_with('/')),
        "ws_path 应形如 /ws: {value}"
    );
    assert_eq!(value["auth_required"], false);

    // 文件写完时端口已经绑定，但 serve 可能还差几毫秒，给一点重试
    let addr = value["addr"].as_str().unwrap().to_string();
    let mut connected = false;
    for _ in 0..40 {
        if std::net::TcpStream::connect(&addr).is_ok() {
            connected = true;
            break;
        }
        std::thread::sleep(Duration::from_millis(50));
    }
    assert!(connected, "就绪文件中报告的地址应当可连接: {addr}");

    #[cfg(unix)]
    {
        // SIGTERM → 优雅关闭 → 就绪文件应被清理
        unsafe {
            libc::kill(child.id() as libc::pid_t, libc::SIGTERM);
        }
        let deadline = Instant::now() + Duration::from_secs(15);
        loop {
            if let Some(status) = child.try_wait().expect("try_wait 失败") {
                assert!(status.success(), "SIGTERM 下应正常退出: {status}");
                break;
            }
            if Instant::now() >= deadline {
                let _ = child.kill();
                panic!("15s 内没有退出");
            }
            std::thread::sleep(Duration::from_millis(50));
        }
    }
    #[cfg(not(unix))]
    {
        let _ = child.kill();
        let _ = child.wait();
    }

    assert!(!ready.exists(), "退出后就绪文件应被删除");
}

#[cfg(unix)]
#[test]
fn daemon_exits_after_its_parent_dies() {
    let dir = TempDir::new("parent");
    let ready = dir.join("ready.json");
    let daemon_pid_file = dir.join("daemon.pid");

    // 用 sh 当「App」：后台拉起 daemon 并把自己的 PID 交给它，然后等着被杀。
    let script = format!(
        "'{BIN}' --host 127.0.0.1 --port 0 --no-color \
         --exit-with-parent $$ --ready-file '{}' \
         >/dev/null 2>&1 & echo $! > '{}'; sleep 60",
        ready.display(),
        daemon_pid_file.display()
    );
    let mut parent = Command::new("sh")
        .current_dir(&dir.0)
        .env("XDG_CONFIG_HOME", dir.join("xdg"))
        .env("HOME", dir.join("home"))
        .args(["-c", &script])
        .spawn()
        .expect("应能启动父进程");

    if !wait_for_file(&ready, Duration::from_secs(15)) {
        let _ = parent.kill();
        panic!("15s 内没写出就绪文件");
    }
    let daemon_pid: u32 = std::fs::read_to_string(&daemon_pid_file)
        .expect("应记录 daemon PID")
        .trim()
        .parse()
        .expect("PID 应是数字");
    assert!(process_alive(daemon_pid), "daemon 应当正在运行");

    parent.kill().expect("应能杀掉父进程");
    let _ = parent.wait();

    let deadline = Instant::now() + Duration::from_secs(15);
    while Instant::now() < deadline {
        if !process_alive(daemon_pid) {
            return;
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    // 收尸，别把孤儿留在测试机上
    unsafe {
        libc::kill(daemon_pid as libc::pid_t, libc::SIGKILL);
    }
    panic!("父进程退出 15s 后 daemon 仍在运行");
}

/// 父进程还活着时，看门狗不能误杀。
#[cfg(unix)]
#[test]
fn daemon_stays_alive_while_parent_lives() {
    let dir = TempDir::new("parent-alive");
    let ready = dir.join("ready.json");

    let mut child = command(&dir)
        .args([
            "--host",
            "127.0.0.1",
            "--port",
            "0",
            "--no-color",
            "--exit-with-parent",
            &std::process::id().to_string(),
            "--ready-file",
            &ready.to_string_lossy(),
        ])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("应能启动 daemon");

    assert!(
        wait_for_file(&ready, Duration::from_secs(15)),
        "15s 内没写出就绪文件"
    );
    std::thread::sleep(Duration::from_millis(1500));
    assert!(
        child.try_wait().unwrap().is_none(),
        "父进程（测试进程）还活着，daemon 不该退出"
    );
    let _ = child.kill();
    let _ = child.wait();
}
