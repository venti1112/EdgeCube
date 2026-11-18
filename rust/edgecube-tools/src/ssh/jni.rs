use jni::objects::{JObject, JString};
use jni::sys::{JNI_FALSE, JNI_TRUE, jboolean};
use jni::{EnvUnowned, errors::{Error, Result, ThrowRuntimeExAndDefault}};

use crate::jni_util::{jstr, throw_java};

/// `SshServerManager.start(...)` 的 JSON 载荷入口。
///
/// 载荷由 Kotlin `SshServerManager.start` 组装（rootDir/port/凭据/开关/
/// hostKeyPath/shellArgv/shellCwd/env），缺失字段与服务层错误均抛
/// `IllegalStateException`。
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_venti1112_edgecube_ssh_SshBridge_nativeSshStart<'local>(
    mut unowned: EnvUnowned<'local>,
    _thiz: JObject<'local>,
    config_json: JString<'local>,
) {
    unowned
        .with_env(|env| -> Result<()> {
            let Some(json) = jstr(env, &config_json) else {
                throw_java(
                    env,
                    "java/lang/IllegalArgumentException",
                    "缺少 configJson",
                );
                return Err(Error::JavaException);
            };
            if let Err(message) = super::start(&json) {
                throw_java(env, "java/lang/IllegalStateException", &message);
                return Err(Error::JavaException);
            }
            Ok(())
        })
        .resolve::<ThrowRuntimeExAndDefault>();
}

/// `SshServerManager.stop()`
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_venti1112_edgecube_ssh_SshBridge_nativeSshStop<'local>(
    _unowned: EnvUnowned<'local>,
    _thiz: JObject<'local>,
) {
    super::stop();
}

/// `SshServerManager.isRunning: Boolean`
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_venti1112_edgecube_ssh_SshBridge_nativeSshIsRunning<'local>(
    _unowned: EnvUnowned<'local>,
    _thiz: JObject<'local>,
) -> jboolean {
    if super::is_running() {
        JNI_TRUE
    } else {
        JNI_FALSE
    }
}

/// `SshServerManager.hostKeyFingerprint(hostKeyPath): String?`
///
/// 密钥文件不存在时先生成再算指纹；任何失败返回 null。
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_venti1112_edgecube_ssh_SshBridge_nativeSshHostKeyFingerprint<
    'local,
>(
    mut unowned: EnvUnowned<'local>,
    _thiz: JObject<'local>,
    host_key_path: JString<'local>,
) -> JString<'local> {
    unowned
        .with_env(|env| -> Result<JString<'local>> {
            let Some(path) = jstr(env, &host_key_path) else {
                return Ok(JString::null());
            };
            match super::keys::fingerprint(std::path::Path::new(&path)) {
                Ok(fp) => JString::from_str(env, fp),
                Err(_) => Ok(JString::null()),
            }
        })
        .resolve::<jni::errors::LogErrorAndDefault>()
}
