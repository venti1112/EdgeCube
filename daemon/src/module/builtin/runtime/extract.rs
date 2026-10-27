//! 解开下好的压缩包，并找出 `java` 在哪。
//!
//! Zulu 给的是「解压即用」的目录树，但**顶层目录名随平台与版本变**：
//!
//! ```text
//! linux:   zulu21.52.203-ca-jdk21.0.12.1-linux_x64/bin/java
//! windows: zulu21.52.203-ca-jdk21.0.12.1-win_x64/bin/java.exe
//! macOS:   zulu-21.jdk/Contents/Home/bin/java
//! ```
//!
//! 所以不猜顶层目录名，而是**找 `bin/java`**（见 [`find_java`]）—— 顺带这也成了
//! 「这份包到底能不能用」的验收：找不到就不算装好，整份解压结果都会被清掉。

use std::fs;
use std::io;
use std::path::{Path, PathBuf};

/// 解压 `archive` 到 `dest`。
///
/// `archive_type` 来自上游的包详情（Linux / macOS 是 `tar.gz`，Windows 是 `zip`）。
///
/// 两条防线都在库里，不用我们手写：
///
/// * **tar**：`Archive::unpack` 拒绝任何会写到 `dest` 之外的条目（绝对路径、`..`），
///   符号链接也一样；权限位默认按 `mode & 0o777` 落下，所以 `bin/java` 的可执行位
///   不用额外开关（`set_preserve_permissions` 管的是 suid 那几位，那要 root）；
/// * **zip**：用 `enclosed_name()` 判定，不安全的名字直接跳过 —— 与 `instance::files`
///   解压服务端包时用的是同一套判定。
pub fn unpack(archive: &Path, dest: &Path, archive_type: &str) -> Result<(), String> {
    fs::create_dir_all(dest).map_err(|e| format!("创建 `{}` 失败：{e}", dest.display()))?;

    match archive_type {
        "tar.gz" => unpack_tar_gz(archive, dest),
        "zip" => unpack_zip(archive, dest),
        other => Err(format!("不认识的压缩格式 `{other}`")),
    }
}

fn unpack_tar_gz(archive: &Path, dest: &Path) -> Result<(), String> {
    let file =
        fs::File::open(archive).map_err(|e| format!("打开 `{}` 失败：{e}", archive.display()))?;
    let decoder = flate2::read::GzDecoder::new(io::BufReader::new(file));
    let mut tar = tar::Archive::new(decoder);
    tar.unpack(dest)
        .map_err(|e| format!("解压 `{}` 失败：{e}", archive.display()))
}

fn unpack_zip(archive: &Path, dest: &Path) -> Result<(), String> {
    let file =
        fs::File::open(archive).map_err(|e| format!("打开 `{}` 失败：{e}", archive.display()))?;
    let mut zip = zip::ZipArchive::new(io::BufReader::new(file))
        .map_err(|e| format!("`{}` 不是合法的 zip：{e}", archive.display()))?;

    for index in 0..zip.len() {
        let mut entry = zip
            .by_index(index)
            .map_err(|e| format!("读 `{}` 的第 {index} 个条目失败：{e}", archive.display()))?;

        // 名字不安全（绝对路径、`..`）就跳过 —— 与实例文件模块同一套判定
        let Some(relative) = entry.enclosed_name() else {
            continue;
        };
        let out = dest.join(&relative);

        if entry.is_dir() {
            fs::create_dir_all(&out).map_err(|e| format!("创建 `{}` 失败：{e}", out.display()))?;
            continue;
        }
        if let Some(parent) = out.parent() {
            fs::create_dir_all(parent)
                .map_err(|e| format!("创建 `{}` 失败：{e}", parent.display()))?;
        }

        let mut writer =
            fs::File::create(&out).map_err(|e| format!("写 `{}` 失败：{e}", out.display()))?;
        io::copy(&mut entry, &mut writer)
            .map_err(|e| format!("写 `{}` 失败：{e}", out.display()))?;
        drop(writer);

        // Windows 的 zip 没有 unix 权限位（`unix_mode()` 给 None），Linux 的 zip
        // 有 —— 顺手补上，省得「Linux 上解 zip」这条路悄悄产出不可执行的 java
        #[cfg(unix)]
        if let Some(mode) = entry.unix_mode() {
            use std::os::unix::fs::PermissionsExt;
            let _ = fs::set_permissions(&out, fs::Permissions::from_mode(mode & 0o777));
        }
    }
    Ok(())
}

/// 在 `dest` 里找 `bin/java`，返回 `(home, binary)`，都是**相对 `dest`**的路径。
///
/// 下探深度 3 是照三个平台的实际布局定的（Linux/Windows 一层，macOS 三层）。
/// 找到就返回，找不到返回 `None` —— 调用方据此判定「这份包不能用」。
pub fn find_java(dest: &Path) -> Option<(String, String)> {
    #[cfg(windows)]
    const NAMES: &[&str] = &["java.exe", "java"];
    #[cfg(not(windows))]
    const NAMES: &[&str] = &["java", "java.exe"];
    find_binary(dest, "bin", NAMES)
}

/// 在自己的包里找一个可执行文件，返回 `(所在目录, 文件)`，都是**相对 `dest`**的路径。
///
/// 形状由 [`super::model::Launcher`] 描述（子目录 + 候选文件名），所以这套遍历
/// 对 JDK 与 frp 是同一份代码 —— 加厂商不用碰这里。
///
/// `sub_dir` 为空时只看「当前这一层」（frp 就是这样：`frpc` 直接躺在顶层目录里）。
pub fn find_binary(dest: &Path, sub_dir: &str, names: &[&str]) -> Option<(String, String)> {
    let (home, found) = walk(dest, 0, MAX_DEPTH, sub_dir, names)
        .into_iter()
        .next()?;
    Some((relative(dest, &home), relative(dest, &found)))
}

/// 找可执行文件时往下探几层。
///
/// 3 是照最深的实际布局定的：macOS 的 JDK 是
/// `zulu-21.jdk/Contents/Home/bin/java`（三层），Linux 与 frp 都只有一层。
const MAX_DEPTH: usize = 3;

/// 相对 `base` 的路径（`base` 之外就原样给），转成协议里的 `/` 分隔形式。
fn relative(base: &Path, path: &Path) -> String {
    match path.strip_prefix(base) {
        Ok(rest) => display_path(rest),
        Err(_) => display_path(path),
    }
}

/// 广度优先地找 `sub_dir/<names 里任意一个>`，返回 `(所在目录, 文件路径)`。
///
/// 用 BFS 而不是深度优先：浅的那份一定是包自己那份；深优先搜进去可能在某个
/// 子目录里先撞上一个无关的同名文件（比如 JDK 的 demo、test 目录里的）。
fn walk(
    dest: &Path,
    depth: usize,
    max_depth: usize,
    sub_dir: &str,
    names: &[&str],
) -> Vec<(PathBuf, PathBuf)> {
    let mut found = Vec::new();
    if depth > max_depth {
        return found;
    }

    let layer = if sub_dir.is_empty() {
        dest.to_path_buf()
    } else {
        dest.join(sub_dir)
    };
    for name in names {
        let candidate = layer.join(name);
        if candidate.is_file() {
            found.push((dest.to_path_buf(), candidate));
        }
    }
    if !found.is_empty() {
        return found;
    }

    let Ok(entries) = fs::read_dir(dest) else {
        return found;
    };
    // 目录顺序要稳定：同一份包在两次解压后应当给出同样的答案
    let mut dirs: Vec<PathBuf> = entries
        .flatten()
        .map(|entry| entry.path())
        .filter(|path| path.is_dir())
        .collect();
    dirs.sort();
    for dir in dirs {
        found.extend(walk(&dir, depth + 1, max_depth, sub_dir, names));
    }
    found
}

/// 相对路径转成协议里的 `/` 分隔形式（Windows 上 `Path` 用的是 `\`）。
fn display_path(path: &Path) -> String {
    path.components()
        .map(|part| part.as_os_str().to_string_lossy().into_owned())
        .collect::<Vec<_>>()
        .join("/")
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 一个用完就删的临时目录。
    struct TempDir(PathBuf);

    impl TempDir {
        fn new(tag: &str) -> Self {
            let path = std::env::temp_dir().join(format!(
                "edgecube-extract-{tag}-{}-{}",
                std::process::id(),
                crate::util::now_ms()
            ));
            fs::create_dir_all(&path).unwrap();
            Self(path)
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    /// 造一个「Zulu 那样」的 tar.gz：一个顶层目录 + `bin/java`（0755）。
    fn make_tar_gz(path: &Path, top: &str, with_java: bool) {
        use flate2::Compression;
        use flate2::write::GzEncoder;

        let file = fs::File::create(path).unwrap();
        let encoder = GzEncoder::new(file, Compression::default());
        let mut builder = tar::Builder::new(encoder);

        let mut header = tar::Header::new_gnu();
        if with_java {
            header.set_size(4);
            header.set_mode(0o755);
            header.set_cksum();
            builder
                .append_data(&mut header, format!("{top}/bin/java"), &b"java"[..])
                .unwrap();
        }
        // 顺带放一个普通文件，确认非可执行文件也能正常落地
        let mut header = tar::Header::new_gnu();
        header.set_size(7);
        header.set_mode(0o644);
        header.set_cksum();
        builder
            .append_data(&mut header, format!("{top}/release"), &b"release"[..])
            .unwrap();

        let encoder = builder.into_inner().unwrap();
        encoder.finish().unwrap();
    }

    /// 造一个 frp 形状的 tar.gz：实干包就长这样（实测）——
    /// 顶层目录里直接躺 `frpc` / `frps` / 两个 toml，**没有 `bin/` 那一层**。
    fn make_frp_tar_gz(path: &Path, top: &str) {
        use flate2::Compression;
        use flate2::write::GzEncoder;

        let file = fs::File::create(path).unwrap();
        let encoder = GzEncoder::new(file, Compression::default());
        let mut builder = tar::Builder::new(encoder);

        for name in ["frpc", "frps"] {
            let mut header = tar::Header::new_gnu();
            header.set_size(4);
            header.set_mode(0o755);
            header.set_cksum();
            builder
                .append_data(&mut header, format!("{top}/{name}"), &b"bin!"[..])
                .unwrap();
        }
        let mut header = tar::Header::new_gnu();
        header.set_size(8);
        header.set_mode(0o644);
        header.set_cksum();
        builder
            .append_data(&mut header, format!("{top}/frpc.toml"), &b"# frpc\n"[..])
            .unwrap();

        let encoder = builder.into_inner().unwrap();
        encoder.finish().unwrap();
    }

    /// 造一个 zip（内容同 `make_tar_gz`，unix 权限位也写进去）。
    fn make_zip(path: &Path, top: &str) {
        use std::io::Write;
        use zip::write::SimpleFileOptions;

        let file = fs::File::create(path).unwrap();
        let mut writer = zip::ZipWriter::new(file);
        let options = SimpleFileOptions::default().unix_permissions(0o755);
        writer
            .start_file(format!("{top}/bin/java"), options)
            .unwrap();
        writer.write_all(b"java").unwrap();
        writer
            .start_file(
                format!("{top}/release"),
                SimpleFileOptions::default().unix_permissions(0o644),
            )
            .unwrap();
        writer.write_all(b"release").unwrap();
        writer.finish().unwrap();
    }

    #[test]
    fn tar_gz_unpacks_and_keeps_the_executable_bit() {
        let temp = TempDir::new("tar");
        let archive = temp.0.join("zulu.tar.gz");
        make_tar_gz(&archive, "zulu21.52.203-ca-jdk21.0.12.1-linux_x64", true);

        let dest = temp.0.join("out");
        unpack(&archive, &dest, "tar.gz").expect("应当能解压");

        let java = dest.join("zulu21.52.203-ca-jdk21.0.12.1-linux_x64/bin/java");
        assert!(java.is_file(), "bin/java 该在");
        assert_eq!(fs::read(&java).unwrap(), b"java");
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = fs::metadata(&java).unwrap().permissions().mode();
            assert_eq!(mode & 0o111, 0o111, "可执行位必须留下来（{mode:o}）");
        }

        let found = find_java(&dest).expect("应当能找到 java");
        assert_eq!(
            found.0, "zulu21.52.203-ca-jdk21.0.12.1-linux_x64",
            "java_home 是顶层那个目录"
        );
        assert_eq!(found.1, "zulu21.52.203-ca-jdk21.0.12.1-linux_x64/bin/java");
    }

    #[test]
    fn zip_unpacks_and_restores_modes() {
        let temp = TempDir::new("zip");
        let archive = temp.0.join("zulu.zip");
        make_zip(&archive, "zulu21.52.203-ca-jdk21.0.12.1-win_x64");

        let dest = temp.0.join("out");
        unpack(&archive, &dest, "zip").expect("应当能解压");
        assert!(
            dest.join("zulu21.52.203-ca-jdk21.0.12.1-win_x64/bin/java")
                .is_file()
        );
        // Windows 的 JDK 也叫 java.exe；这里两个名字都找，得到的就是包里的那个
        let (home, bin) = find_java(&dest).expect("应当能找到 java");
        assert_eq!(home, "zulu21.52.203-ca-jdk21.0.12.1-win_x64");
        assert!(bin.ends_with("/bin/java"));
    }

    #[test]
    fn macos_layout_needs_looking_three_levels_down() {
        let temp = TempDir::new("mac");
        let archive = temp.0.join("zulu.tar.gz");
        make_tar_gz(&archive, "zulu-21.jdk/Contents/Home", true);

        let dest = temp.0.join("out");
        unpack(&archive, &dest, "tar.gz").expect("应当能解压");

        let (home, bin) = find_java(&dest).expect("macOS 布局要能找到 java");
        assert_eq!(home, "zulu-21.jdk/Contents/Home");
        assert_eq!(bin, "zulu-21.jdk/Contents/Home/bin/java");
    }

    #[test]
    fn a_package_without_java_is_rejected() {
        let temp = TempDir::new("nojava");
        let archive = temp.0.join("jre.tar.gz");
        make_tar_gz(&archive, "not-a-jdk", false);

        let dest = temp.0.join("out");
        unpack(&archive, &dest, "tar.gz").expect("解压本身能成功");
        assert!(find_java(&dest).is_none(), "没有 bin/java 就不算装好");
    }

    /// frp 的布局：`frpc` 就在顶层目录里，`sub_dir` 是空串 —— 与 JDK 那套
    /// 「往下找 `bin/java`」是同一份遍历，只是参数不同。
    #[test]
    fn frp_layout_has_no_bin_layer() {
        const NAMES: &[&str] = &["frpc", "frpc.exe"];
        let temp = TempDir::new("frp");
        let archive = temp.0.join("frp.tar.gz");
        let top = "frp_0.71.0_linux_amd64";
        make_frp_tar_gz(&archive, top);

        let dest = temp.0.join("out");
        unpack(&archive, &dest, "tar.gz").expect("应当能解压");

        let (home, binary) = find_binary(&dest, "", NAMES).expect("frp 包里应当有 frpc");
        assert_eq!(home, top);
        assert_eq!(binary, format!("{top}/frpc"));

        // 用 JDK 那套参数找同一个目录是找不到的 —— 这正是 launcher 要分厂商的原因
        assert!(find_binary(&dest, "bin", NAMES).is_none());
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = fs::metadata(dest.join(&binary))
                .unwrap()
                .permissions()
                .mode();
            assert_eq!(mode & 0o111, 0o111, "frpc 必须可执行（{mode:o}）");
        }
    }

    #[test]
    fn find_java_does_not_look_too_deep() {
        let temp = TempDir::new("deep");
        let dest = temp.0.join("out");
        // 四层才到 bin/java：超出下探深度，应当找不到（宁可判失败，也不认一个
        // 来路不明的 java）
        let deep = dest.join("a/b/c/d/bin");
        fs::create_dir_all(&deep).unwrap();
        fs::write(deep.join("java"), b"java").unwrap();
        assert!(find_java(&dest).is_none());
    }

    #[test]
    fn unknown_archive_type_is_an_error() {
        let temp = TempDir::new("type");
        let err = unpack(&temp.0.join("x.7z"), &temp.0.join("out"), "7z").unwrap_err();
        assert!(err.contains("7z"), "{err}");
    }
}
