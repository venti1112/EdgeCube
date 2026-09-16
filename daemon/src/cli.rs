//! 极简命令行解析。
//!
//! 刻意不引 clap：参数就这几个，手写能少一个重量级依赖，也方便
//! 「命令行覆盖配置」这条路径一眼看懂。

use std::path::PathBuf;

use crate::error::{Error, Result};

#[derive(Debug, Clone, Default)]
pub struct Cli {
    /// `-c/--config` 或 `EDGECUBE_CONFIG`。
    pub config: Option<PathBuf>,
    pub host: Option<String>,
    pub port: Option<u16>,
    pub token: Option<String>,
    pub log_level: Option<String>,
    pub log_format: Option<String>,
    /// 关掉 ANSI 颜色。
    pub no_color: bool,
    pub action: Action,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Action {
    /// 正常启动服务。
    #[default]
    Run,
    /// 生成默认配置文件后退出。
    InitConfig,
    /// 打印合并后的配置后退出。
    PrintConfig,
    /// 校验配置与模块后退出，不监听端口。
    Check,
}

pub const HELP: &str = "\
edgecube-daemon —— EdgeCube 后端守护进程

用法:
    edgecube-daemon [选项]

选项:
    -c, --config <PATH>      指定配置文件（默认查找 ./edgecube.toml，
                             再找 $XDG_CONFIG_HOME/edgecube/daemon.toml）
        --init-config        生成带注释的默认配置文件到 -c 指定路径后退出
        --print-config       打印合并后的最终配置后退出
        --check              仅校验配置与模块注册情况后退出
        --host <HOST>        覆盖监听地址
        --port <PORT>        覆盖监听端口
        --token <TOKEN>      覆盖访问令牌
        --log-level <FILTER> 覆盖日志级别，如 debug 或 edgecube_daemon=trace
        --log-format <FMT>   覆盖日志格式: pretty | json
        --no-color           关闭日志颜色
    -h, --help               显示帮助
    -V, --version            显示版本

环境变量:
    EDGECUBE_CONFIG, EDGECUBE_HOST, EDGECUBE_PORT, EDGECUBE_TOKEN,
    EDGECUBE_LOG_LEVEL, EDGECUBE_LOG_FORMAT, EDGECUBE_NO_COLOR
";

impl Cli {
    /// 解析参数。`--help` / `--version` 通过 [`Error::Other`] 之外的短路返回：
    /// 调用方拿到 `Err` 里带 help 文本的 `Other` 时按正常退出处理。
    ///
    /// 为了调用方简单，这里改成返回 [`ParseOutcome`]。
    pub fn parse<I, S>(args: I) -> Result<ParseOutcome>
    where
        I: IntoIterator<Item = S>,
        S: Into<String>,
    {
        let argv: Vec<String> = args.into_iter().map(Into::into).collect();
        // argv[0] 是程序名，跳过；用户可能直接传不含程序名的列表
        let mut iter = argv.into_iter().peekable();
        if let Some(first) = iter.peek()
            && (first.contains("edgecube") || first.ends_with("daemon"))
        {
            iter.next();
        }

        let mut cli = Cli::default();
        while let Some(arg) = iter.next() {
            // 支持 `--key=value`
            let (key, inline) = match arg.split_once('=') {
                Some((k, v)) if k.starts_with('-') => (k.to_string(), Some(v.to_string())),
                _ => (arg.clone(), None),
            };

            let mut take = |name: &str| -> Result<String> {
                if let Some(v) = inline.clone() {
                    return Ok(v);
                }
                iter.next()
                    .ok_or_else(|| Error::other(format!("{name} 缺少取值")))
            };

            match key.as_str() {
                "-h" | "--help" => return Ok(ParseOutcome::Help),
                "-V" | "--version" => return Ok(ParseOutcome::Version),
                "-c" | "--config" => cli.config = Some(PathBuf::from(take("--config")?)),
                "--init-config" => cli.action = Action::InitConfig,
                "--print-config" => cli.action = Action::PrintConfig,
                "--check" => cli.action = Action::Check,
                "--host" => cli.host = Some(take("--host")?),
                "--port" => {
                    let raw = take("--port")?;
                    cli.port = Some(
                        raw.trim()
                            .parse()
                            .map_err(|_| Error::other(format!("--port 不是合法端口: `{raw}`")))?,
                    );
                }
                "--token" => cli.token = Some(take("--token")?),
                "--log-level" => cli.log_level = Some(take("--log-level")?),
                "--log-format" => cli.log_format = Some(take("--log-format")?),
                "--no-color" => cli.no_color = true,
                other => {
                    return Err(Error::other(format!(
                        "未知参数 `{other}`（用 --help 查看用法）"
                    )));
                }
            }
        }

        Ok(ParseOutcome::Run(cli))
    }
}

#[derive(Debug, Clone)]
pub enum ParseOutcome {
    Run(Cli),
    Help,
    Version,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(args: &[&str]) -> Cli {
        match Cli::parse(args.iter().map(|s| s.to_string())).unwrap() {
            ParseOutcome::Run(c) => c,
            other => panic!("期望正常解析，得到 {other:?}"),
        }
    }

    #[test]
    fn parses_short_and_long() {
        let c = run(&[
            "edgecube-daemon",
            "-c",
            "a.toml",
            "--port",
            "9000",
            "--no-color",
        ]);
        assert_eq!(c.config, Some(PathBuf::from("a.toml")));
        assert_eq!(c.port, Some(9000));
        assert!(c.no_color);
        assert_eq!(c.action, Action::Run);
    }

    #[test]
    fn supports_inline_value() {
        let c = run(&["--log-level=debug"]);
        assert_eq!(c.log_level.as_deref(), Some("debug"));
    }

    #[test]
    fn help_and_version_short_circuit() {
        assert!(matches!(
            Cli::parse(["--help".to_string()]).unwrap(),
            ParseOutcome::Help
        ));
        assert!(matches!(
            Cli::parse(["-V".to_string()]).unwrap(),
            ParseOutcome::Version
        ));
    }

    #[test]
    fn missing_value_is_error() {
        assert!(Cli::parse(["--port".to_string()]).is_err());
    }

    #[test]
    fn unknown_flag_is_error() {
        assert!(Cli::parse(["--nope".to_string()]).is_err());
    }

    #[test]
    fn bad_port_is_error() {
        assert!(Cli::parse(["--port".to_string(), "abc".to_string()]).is_err());
    }
}
