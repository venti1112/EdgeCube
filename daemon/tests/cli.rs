//! 针对真实二进制的「首次运行」行为。
//!
//! framework.rs 测的是库（进程内起 server），这里测的是 `main()` 那条路：
//! 没有配置文件时应当**自动释放一份默认配置并加载它**，`--init-config` 不再是必经步骤。
//! 用 `--print-config` / `--check` 这两个「加载完就退出」的动作，
//! 不监听端口，测试快且不会和别的用例撞端口。

use std::path::PathBuf;
use std::process::Command;

const BIN: &str = env!("CARGO_BIN_EXE_edgecube-daemon");

/// 一个临时目录；析构时清盘。
struct TempDir(PathBuf);

impl TempDir {
    fn new(tag: &str) -> Self {
        let dir = std::env::temp_dir().join(format!(
            "edgecube-cli-test-{tag}-{}-{}",
            std::process::id(),
            edgecube_daemon::util::now_ms()
        ));
        std::fs::create_dir_all(&dir).expect("应能建临时目录");
        Self(dir)
    }

    fn join(&self, name: &str) -> PathBuf {
        self.0.join(name)
    }

    /// 自动释放的默认配置会落在这里（`XDG_CONFIG_HOME` 指向 `xdg/` 时）。
    fn default_config(&self) -> PathBuf {
        self.join("xdg/edgecube/daemon.toml")
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

/// 在隔离环境里跑一次二进制。
///
/// `XDG_CONFIG_HOME` / `HOME` 都指向临时目录、进程 CWD 也是它 ——
/// 既不会读写真实的 `~/.config/edgecube/`，也不会撞上仓库里的 `./edgecube.toml`。
/// `EDGECUBE_*` 全部清掉，免得宿主机的环境变量改变行为。
fn run(dir: &TempDir, args: &[&str]) -> std::process::Output {
    Command::new(BIN)
        .args(args)
        .current_dir(&dir.0)
        .env("XDG_CONFIG_HOME", dir.join("xdg"))
        .env("HOME", dir.join("home"))
        .env_remove("EDGECUBE_CONFIG")
        .env_remove("EDGECUBE_HOST")
        .env_remove("EDGECUBE_PORT")
        .env_remove("EDGECUBE_TOKEN")
        .env_remove("EDGECUBE_LOG_LEVEL")
        .env_remove("EDGECUBE_LOG_FORMAT")
        .env_remove("EDGECUBE_NO_COLOR")
        .output()
        .expect("应当能启动二进制")
}

fn stdout(out: &std::process::Output) -> String {
    String::from_utf8_lossy(&out.stdout).into_owned()
}

fn stderr(out: &std::process::Output) -> String {
    String::from_utf8_lossy(&out.stderr).into_owned()
}

/// 首次运行：什么都不做，直接 `--print-config` → 默认配置就位、加载的就是它。
#[test]
fn first_run_releases_the_default_config_without_init_config() {
    let dir = TempDir::new("first-run");
    let config = dir.default_config();

    let out = run(&dir, &["--print-config"]);
    assert!(out.status.success(), "stderr: {}", stderr(&out));
    assert!(
        config.is_file(),
        "首次运行应当自动释放默认配置: {}",
        config.display()
    );
    let text = std::fs::read_to_string(&config).unwrap();
    assert!(
        text.contains("# EdgeCube Daemon 配置文件"),
        "释放的应当是带注释的模板: {text}"
    );

    // 打印出来的就是刚写下去的那份（含模板里的模块配置节 → 模块得已启用）
    let printed = stdout(&out);
    assert!(
        printed.contains("interval_ms"),
        "应当读到模块配置节:\n{printed}"
    );

    // 第二次：文件已存在 → 原样加载，不再覆盖
    std::fs::write(&config, "[server]\nmax_connections = 42\n").unwrap();
    let again = run(&dir, &["--print-config"]);
    assert!(again.status.success(), "stderr: {}", stderr(&again));
    assert!(
        stdout(&again).contains("max_connections = 42"),
        "应当读的是用户改过的配置:\n{}",
        stdout(&again)
    );
    assert_eq!(
        std::fs::read_to_string(&config).unwrap(),
        "[server]\nmax_connections = 42\n",
        "用户写的文件一个字节都不该被动"
    );
}

/// `--check` 走的是同一条加载路径：首次运行也应当先把默认配置释放出来，
/// 这样释放出来的模板必须能被模块解析（monitor / ticker 的配置节不是摆设）。
#[test]
fn check_releases_a_workable_config_on_first_run() {
    let dir = TempDir::new("check");
    let out = run(&dir, &["--check"]);
    assert!(out.status.success(), "stderr: {}", stderr(&out));

    assert!(dir.default_config().is_file());
    let printed = stdout(&out);
    assert!(printed.contains("配置自检通过"), "{printed}");
    assert!(
        printed.contains("monitor"),
        "默认配置应启用 monitor:\n{printed}"
    );
    assert!(
        printed.contains("instance"),
        "默认配置应启用 instance:\n{printed}"
    );
}

/// 显式指定的路径不存在 → 仍然报错退出，不替他生成（否则「路径写错」被盖住）。
#[test]
fn an_explicit_missing_config_path_is_still_an_error() {
    let dir = TempDir::new("explicit-missing");
    let missing = dir.join("nope.toml");

    let out = run(&dir, &["-c", &missing.to_string_lossy(), "--check"]);
    assert!(
        !out.status.success(),
        "显式路径不存在应当报错，实际 stdout: {}",
        stdout(&out)
    );
    assert!(
        stderr(&out).contains("配置文件不存在"),
        "stderr: {}",
        stderr(&out)
    );
    assert!(!missing.exists(), "不该在用户给的错误路径上生成一份");
    assert!(!dir.default_config().exists(), "也不该退到默认位置去释放");
}

/// 释放失败（默认位置的父目录被普通文件占着）→ 降级到内置默认值，
/// 启动不失败，且提示语说清楚了原因。
#[test]
fn a_failed_release_degrades_to_builtin_defaults_instead_of_dying() {
    let dir = TempDir::new("unwritable");
    // XDG_CONFIG_HOME 本身是个普通文件 → 其下的 edgecube/ 建不出来
    std::fs::write(dir.join("xdg"), b"not a directory").unwrap();

    let out = run(&dir, &["--check"]);
    assert!(
        out.status.success(),
        "写不出配置也必须能起（用内置默认值），stderr: {}",
        stderr(&out)
    );
    let combined = format!("{}{}", stdout(&out), stderr(&out));
    assert!(
        combined.contains("无法在") && combined.contains("释放默认配置"),
        "应当提示释放失败与原因: {combined}"
    );
    assert!(stdout(&out).contains("配置自检通过"));
}
