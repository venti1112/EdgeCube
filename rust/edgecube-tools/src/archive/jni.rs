use jni::objects::{JIntArray, JObject, JString};
use jni::sys::{JNI_FALSE, JNI_TRUE, jboolean, jint, jintArray, jstring};
use jni::{Env, EnvUnowned, JValue, errors::{Result, ThrowRuntimeExAndDefault}, jni_sig, jni_str};

use super::{ArchError, compress_to_zip, extract, extract_prefixes, has_dir_prefix, read_entry};
use crate::jni_util::{clear_exception, jobj_to_jstr_vec, jstr, throw_java};

/// `ArchError` → Java 异常类 + 消息（逐字透传）。
fn throw_arch(env: &mut Env, error: ArchError) {
    let (class, message) = match error {
        ArchError::Arg(message) => ("java/lang/IllegalArgumentException", message),
        ArchError::Security(message) => ("java/lang/SecurityException", message),
        ArchError::Io(message) => ("java/io/IOException", message),
    };
    throw_java(env, class, &message);
}

/// 参数缺失时抛 `IllegalArgumentException`，返回 `None`。
fn require<T>(env: &mut Env, value: Option<T>, message: &str) -> Option<T> {
    match value {
        Some(value) => Some(value),
        None => {
            throw_java(env, "java/lang/IllegalArgumentException", message);
            None
        }
    }
}

/// 构造进度回调：`listener` 为 null 时静默，否则按名调用
/// `ArchiveProgressListener.onProgress(II)V`。
fn listener_progress<'a, 'local>(
    env: &'a mut Env<'local>,
    listener: JObject<'local>,
) -> impl FnMut(i32, i32) + 'a {
    let is_null = listener.is_null();
    move |current, total| {
        if is_null {
            return;
        }
        let _ = env.call_method(
            &listener,
            jni_str!("onProgress"),
            jni_sig!((int) -> void),
            &[JValue::Int(current), JValue::Int(total)],
        );
        clear_exception(env);
    }
}

/// `ArchiveExtractor.compressToZip(sourcePaths, archivePath): Int`
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_venti1112_edgecube_files_ArchiveBridge_nativeCompressToZip<
    'local,
>(
    mut unowned: EnvUnowned<'local>,
    _thiz: JObject<'local>,
    sources: JObject<'local>,
    archive_path: JString<'local>,
) -> jint {
    unowned
        .with_env(|env| -> Result<jint> {
            let archive = jstr(env, &archive_path);
            let Some(archive) = require(env, archive, "缺少 archivePath") else {
                return Ok(0);
            };
            let list = jobj_to_jstr_vec(env, &sources);
            let Some(list) = require(env, list, "缺少 sourcePaths") else {
                return Ok(0);
            };
            match compress_to_zip(&list, &archive) {
                Ok(count) => Ok(count),
                Err(error) => {
                    throw_arch(env, error);
                    Ok(0)
                }
            }
        })
        .resolve::<ThrowRuntimeExAndDefault>()
}

/// `ArchiveExtractor.extract(archivePath, destDir, onProgress): Int`
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_venti1112_edgecube_files_ArchiveBridge_nativeExtract<'local>(
    mut unowned: EnvUnowned<'local>,
    _thiz: JObject<'local>,
    archive_path: JString<'local>,
    dest_dir: JString<'local>,
    listener: JObject<'local>,
) -> jint {
    unowned
        .with_env(|env| -> Result<jint> {
            let archive = jstr(env, &archive_path);
            let dest = jstr(env, &dest_dir);
            let (Some(archive), Some(dest)) = (archive, dest) else {
                throw_java(env, "java/lang/IllegalArgumentException", "缺少参数");
                return Ok(0);
            };
            let outcome = {
                let mut progress = listener_progress(env, listener);
                extract(&archive, &dest, &mut progress)
            };
            match outcome {
                Ok(count) => Ok(count),
                Err(error) => {
                    throw_arch(env, error);
                    Ok(0)
                }
            }
        })
        .resolve::<ThrowRuntimeExAndDefault>()
}

/// `RuntimeInstaller`：读取指定条目内容为文本；条目缺失抛
/// `IllegalArgumentException("ZIP 中缺少 <name>")`。
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_venti1112_edgecube_files_ArchiveBridge_nativeZipReadEntry<
    'local,
>(
    mut unowned: EnvUnowned<'local>,
    _thiz: JObject<'local>,
    archive_path: JString<'local>,
    entry_name: JString<'local>,
) -> jstring {
    unowned
        .with_env(|env| -> Result<jstring> {
            let archive = jstr(env, &archive_path);
            let entry = jstr(env, &entry_name);
            let (Some(archive), Some(entry)) = (archive, entry) else {
                throw_java(env, "java/lang/IllegalArgumentException", "缺少参数");
                return Ok(std::ptr::null_mut());
            };
            match read_entry(std::path::Path::new(&archive), &entry) {
                Ok(text) => match JString::from_str(env, &text) {
                    Ok(value) => Ok(value.into_raw()),
                    Err(error) => {
                        throw_arch(env, ArchError::io(error));
                        Ok(std::ptr::null_mut())
                    }
                },
                Err(error) => {
                    throw_arch(env, error);
                    Ok(std::ptr::null_mut())
                }
            }
        })
        .resolve::<ThrowRuntimeExAndDefault>()
}

/// `RuntimeInstaller`：ZIP 中是否存在 `dir/` 前缀条目。
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_venti1112_edgecube_files_ArchiveBridge_nativeZipHasDirPrefix<
    'local,
>(
    mut unowned: EnvUnowned<'local>,
    _thiz: JObject<'local>,
    archive_path: JString<'local>,
    dir_name: JString<'local>,
) -> jboolean {
    unowned
        .with_env(|env| -> Result<jboolean> {
            let archive = jstr(env, &archive_path);
            let dir = jstr(env, &dir_name);
            let (Some(archive), Some(dir)) = (archive, dir) else {
                throw_java(env, "java/lang/IllegalArgumentException", "缺少参数");
                return Ok(JNI_FALSE);
            };
            match has_dir_prefix(std::path::Path::new(&archive), &dir) {
                Ok(found) => Ok(if found { JNI_TRUE } else { JNI_FALSE }),
                Err(error) => {
                    throw_arch(env, error);
                    Ok(JNI_FALSE)
                }
            }
        })
        .resolve::<ThrowRuntimeExAndDefault>()
}

/// `RuntimeInstaller`：ecpkg 双前缀提取；返回 `[processed, total]`。
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_venti1112_edgecube_files_ArchiveBridge_nativeEcpkgExtract<
    'local,
>(
    mut unowned: EnvUnowned<'local>,
    _thiz: JObject<'local>,
    archive_path: JString<'local>,
    dest_dir: JString<'local>,
    universal_dir: JObject<'local>,
    arch_dir: JString<'local>,
) -> jintArray {
    unowned
        .with_env(|env| -> Result<jintArray> {
            let archive = jstr(env, &archive_path);
            let dest = jstr(env, &dest_dir);
            let arch = jstr(env, &arch_dir);
            let (Some(archive), Some(dest), Some(arch)) = (archive, dest, arch) else {
                throw_java(env, "java/lang/IllegalArgumentException", "缺少参数");
                return Ok(std::ptr::null_mut());
            };
            let universal = if universal_dir.is_null() {
                None
            } else {
                let as_string: JString = env.cast_local::<JString>(universal_dir)?;
                jstr(env, &as_string)
            };
            let outcome = extract_prefixes(
                std::path::Path::new(&archive),
                std::path::Path::new(&dest),
                universal.as_deref(),
                &arch,
            );
            match outcome {
                Ok((processed, total)) => {
                    let array: JIntArray = env.new_int_array(2)?;
                    array.set_region(env, 0, &[processed, total])?;
                    Ok(array.into_raw())
                }
                Err(error) => {
                    throw_arch(env, error);
                    Ok(std::ptr::null_mut())
                }
            }
        })
        .resolve::<ThrowRuntimeExAndDefault>()
}
