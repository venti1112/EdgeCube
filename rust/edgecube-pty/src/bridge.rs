//! JNI 桥：`com.venti1112.edgecube.pty.PtyBridge` 的 native 实现。
//!
//! 设计要点：
//!
//! * **不抛异常**。所有可能失败的调用返回一个 JSON envelope
//!   `{"ok":true,…}` / `{"ok":false,"code":"pty_*","message":…}`，
//!   由 Kotlin 翻译成 `PtyException`。JNI 里做 `throw` 要拿异常类 + 构造器、
//!   抛完还得确认 pending exception，容易漏；而 `nativeInfo` 反正已经要返回 JSON。
//! * handle 是不透明 `jlong`，指向 [`SESSIONS`] 里的 `Arc<Session>`。
//!   会话**与进程解耦**：进程停了 handle 依然有效，历史与订阅者都还在。
//! * [`FrameSink`] 的实现 [`JniSink`] 只调 `onFrame`，**不 post、不加锁** ——
//!   搬到主线程是 Kotlin 的活，见 `frame.rs` 的契约说明。

use std::collections::HashMap;
use std::ffi::c_void;
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::{Arc, LazyLock, Mutex, OnceLock};

use jni::objects::{Global, JByteArray, JObject, JObjectArray, JString};
use jni::sys::{JNI_TRUE, jboolean, jint, jlong, jstring};
use jni::{
    Env, EnvUnowned, JavaVM, JValue,
    errors::{LogErrorAndDefault, Result},
    jni_sig, jni_str,
};

use crate::frame::{FrameSink, OutFrame, SharedSink};
use crate::lifecycle;
use crate::run::SpawnSpec;
use crate::session::{Phase, ProcessError, Session};

// ---------------------------------------------------------------------------
// JVM 句柄
// ---------------------------------------------------------------------------

/// jni 0.22 起 [`JavaVM`] 自身已实现 `Send`/`Sync`，但仍保留 `OnceLock`
/// 单例，让无 JVM 的宿主测试环境（`cargo test`）能优雅退化。
static JVM: OnceLock<JavaVM> = OnceLock::new();

fn jvm() -> Option<&'static JavaVM> {
    JVM.get()
}

/// `JNI_OnLoad`：`System.loadLibrary("edgecube_pty")` 时由 ART 调用，
/// 早于任何 `native*` 方法，因此 [`JVM`] 一定已经就位。
///
/// jni 0.22 的 `JavaVM` 不再是 FFI 安全的透明包装，所以这里按原始
/// `jni_sys::JavaVM` 指针接收，再用 `JavaVM::from_raw` 包装。
#[unsafe(no_mangle)]
#[allow(clippy::not_unsafe_ptr_arg_deref)] // JNI_OnLoad 的签名由 JVM 规定，不能标 unsafe
pub extern "system" fn JNI_OnLoad(vm: *mut jni::sys::JavaVM, _reserved: *mut c_void) -> jint {
    // SAFETY: ART 保证传入的是进程内唯一虚拟机的有效句柄。
    let vm = unsafe { JavaVM::from_raw(vm) };
    let _ = JVM.set(vm);
    jni::sys::JNI_VERSION_1_6
}

/// Rust 长驻线程（输出 / 等待线程）持有的「已 attach」凭证。
///
/// 线程起来时 attach 一次，退出时显式 detach，省掉 JNI 回调每帧
/// attach/detach 一次的开销。
///
/// jni 0.22 的 `attach_current_thread` 内部签发的守卫已经**不会**在 drop
/// 时移除别人的挂载，所以这里的 [`Drop`] 只做一次显式 `detach_current_thread`
/// （重复调用无害：线程已摘除时直接返回 `Err`，忽略即可）。
pub struct JniThreadGuard {
    vm: Option<&'static JavaVM>,
    attached: bool,
}

impl JniThreadGuard {
    pub fn acquire() -> Self {
        let Some(vm) = jvm() else {
            // 主机上跑 `cargo test` 时没有 JVM —— 直接退化成空守卫。
            return Self {
                vm: None,
                attached: false,
            };
        };
        let attached = vm
            .attach_current_thread(|_env| -> Result<()> { Ok(()) })
            .is_ok();
        Self {
            vm: Some(vm),
            attached,
        }
    }
}

impl Drop for JniThreadGuard {
    fn drop(&mut self) {
        if self.attached
            && let Some(vm) = self.vm
        {
            let _ = vm.detach_current_thread();
        }
    }
}

/// 在当前线程的前提交给 [f] 一个 `&mut Env`。
///
/// 没有 JVM（主机测试）时返回 `None`。
fn with_env<T>(f: impl FnOnce(&mut Env) -> T) -> Option<T> {
    let vm = jvm()?;
    vm.attach_current_thread(|env| -> Result<T> { Ok(f(env)) })
        .ok()
}

// ---------------------------------------------------------------------------
// handle 注册表
// ---------------------------------------------------------------------------

static SESSIONS: LazyLock<Mutex<HashMap<i64, Arc<Session>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));
static NEXT_HANDLE: AtomicI64 = AtomicI64::new(1);

/// 取一个会话；handle 不存在（拼错 / 已 destroy）→ [`ProcessError::NotRunning`]。
///
/// 这个错误码是**故意**复用的：Kotlin 侧对「没在跑」与「句柄失效」的处置
/// 完全一样（报错并让界面回到已停止态），分两个码反而要多写一条分支。
fn session_of(handle: jlong) -> std::result::Result<Arc<Session>, ProcessError> {
    SESSIONS
        .lock()
        .map_err(|_| ProcessError::Spawn("会话注册表锁损坏".into()))?
        .get(&handle)
        .cloned()
        .ok_or(ProcessError::NotRunning)
}

// ---------------------------------------------------------------------------
// 返回值
// ---------------------------------------------------------------------------

fn new_string_raw(s: &str) -> jstring {
    with_env(|env| {
        JString::from_str(env, s)
            .map(|v| v.into_raw())
            .unwrap_or(std::ptr::null_mut())
    })
    .unwrap_or(std::ptr::null_mut())
}

/// 失败 envelope。
fn err_envelope(code: &str, message: impl AsRef<str>) -> jstring {
    let json = serde_json::json!({
        "ok": false,
        "code": code,
        "message": message.as_ref(),
    });
    new_string_raw(&json.to_string())
}

/// 成功 envelope；`body` 会被塞进 `"ok": true` 后原样返回。
fn ok_envelope(body: serde_json::Value) -> jstring {
    let mut json = body;
    if let Some(obj) = json.as_object_mut() {
        obj.insert("ok".into(), serde_json::Value::Bool(true));
    }
    new_string_raw(&json.to_string())
}

/// 把 [`ProcessError`] 翻成 envelope —— `code` 就是 Rust 侧的稳定码，
/// Kotlin 直接拿它当 MethodChannel 的 errorCode。
fn error_envelope(e: ProcessError) -> jstring {
    err_envelope(e.code(), e.to_string())
}

// ---------------------------------------------------------------------------
// 字符串 / 数组辅助
// ---------------------------------------------------------------------------

fn jstr(env: &mut Env, s: &JString) -> Option<String> {
    s.try_to_string(env).ok()
}

fn jstr_vec(env: &mut Env, arr: &JObjectArray<JString>) -> Option<Vec<String>> {
    let n = arr.len(env).ok()?;
    let mut out = Vec::with_capacity(n);
    for i in 0..n {
        let item: JString = arr.get_element(env, i).ok()?;
        out.push(jstr(env, &item)?);
    }
    Some(out)
}

// ---------------------------------------------------------------------------
// 订阅者
// ---------------------------------------------------------------------------

/// 帧 kind 编号；必须与 Kotlin `FrameListener.onFrame` 里的常量一致。
const KIND_REPLAY_BEGIN: jint = 0;
const KIND_DATA: jint = 1;
const KIND_REPLAY_END: jint = 2;
const KIND_CONTROL: jint = 3;

/// 把一帧投给 Kotlin 的 `FrameListener.onFrame(kind, bytes, json)`。
///
/// **只调方法、不加任何锁、不 `post`** —— 搬到主线程是 Kotlin 的活。
/// 见 `frame.rs::FrameSink` 的契约说明。
struct JniSink {
    vm: &'static JavaVM,
    listener: Global<JObject<'static>>,
}

impl JniSink {
    fn deliver(&self, frame: &OutFrame) {
        let (kind, data, json): (jint, Option<&[u8]>, Option<&str>) = match frame {
            OutFrame::ReplayBegin => (KIND_REPLAY_BEGIN, None, None),
            OutFrame::Data(bytes) => (KIND_DATA, Some(bytes), None),
            OutFrame::ReplayEnd(state) => (KIND_REPLAY_END, None, Some(state)),
            OutFrame::Control(state) => (KIND_CONTROL, None, Some(state)),
        };

        // 任何一步失败（引擎被回收、OOM、抛了 Java 异常…）都只丢这一帧，
        // 绝不让错误冒泡进 `fan_out` —— 那会连带搞死 PTY 读线程。
        let _ = self
            .vm
            .attach_current_thread(|env| -> Result<()> {
                let bytes_obj: Option<JObject> = match data {
                    Some(d) => Some(env.byte_array_from_slice(d)?.into()),
                    None => None,
                };
                let json_obj: Option<JObject> = match json {
                    Some(j) => Some(JString::from_str(env, j)?.into()),
                    None => None,
                };
                let null = JObject::null();
                let args = [
                    JValue::Int(kind),
                    JValue::Object(bytes_obj.as_ref().unwrap_or(&null)),
                    JValue::Object(json_obj.as_ref().unwrap_or(&null)),
                ];
                let listener: &JObject = self.listener.as_ref();
                let _ = env.call_method(
                    listener,
                    jni_str!("onFrame"),
                    jni_sig!((int, byte[], java.lang.String) -> void),
                    &args,
                );
                // 调用抛了 Java 异常时必须清掉 pending 状态，否则下一次 JNI 调用
                //（哪怕与该异常毫无关系）会直接 abort。
                if env.exception_check() {
                    env.exception_clear();
                }
                Ok(())
            });
    }
}

impl FrameSink for JniSink {
    fn send(&self, frame: OutFrame) {
        self.deliver(&frame);
    }
}

// ---------------------------------------------------------------------------
// 会话
// ---------------------------------------------------------------------------

/// 建一个会话；返回 handle（0 表示注册表锁损坏）。
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_venti1112_edgecube_pty_PtyBridge_nativeCreate<'local>(
    mut unowned: EnvUnowned<'local>,
    _this: JObject<'local>,
    label: JString<'local>,
) -> jlong {
    unowned
        .with_env(|env| -> Result<jlong> {
            let label = jstr(env, &label).unwrap_or_else(|| "pty".into());
            let session = Arc::new(Session::new(label));
            let handle = NEXT_HANDLE.fetch_add(1, Ordering::Relaxed);
            Ok(match SESSIONS.lock() {
                Ok(mut map) => {
                    map.insert(handle, session);
                    handle
                }
                Err(_) => 0,
            })
        })
        .resolve::<LogErrorAndDefault>()
}

/// 销毁会话：先静默收掉进程，再丢掉历史与订阅者。
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_venti1112_edgecube_pty_PtyBridge_nativeDestroy<'local>(
    _unowned: EnvUnowned<'local>,
    _this: JObject<'local>,
    handle: jlong,
) {
    if let Ok(mut map) = SESSIONS.lock()
        && let Some(session) = map.remove(&handle)
    {
        lifecycle::shutdown_quiet(&session);
    }
}

/// 拉起一轮进程。
///
/// `initial_phase` 取 `"running"`（shell）/ `"starting"`（服务端）/ `"preparing"`。
#[allow(clippy::too_many_arguments)]
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_venti1112_edgecube_pty_PtyBridge_nativeStart<'local>(
    mut unowned: EnvUnowned<'local>,
    _this: JObject<'local>,
    handle: jlong,
    argv: JObjectArray<'local, JString<'local>>,
    envp: JObjectArray<'local, JString<'local>>,
    cwd: JString<'local>,
    rows: jint,
    cols: jint,
    cell_w: jint,
    cell_h: jint,
    initial_phase: JString<'local>,
    auto_restart: jboolean,
) -> jstring {
    unowned
        .with_env(|env| -> Result<jstring> {
            let session = match session_of(handle) {
                Ok(s) => s,
                Err(e) => return Ok(error_envelope(e)),
            };
            let (Some(argv), Some(envp)) = (jstr_vec(env, &argv), jstr_vec(env, &envp)) else {
                return Ok(err_envelope("pty_start_failed", "argv / envp 解析失败"));
            };
            let cwd = jstr(env, &cwd).unwrap_or_default();
            let phase = match jstr(env, &initial_phase).as_deref() {
                Some("starting") => Phase::Starting,
                Some("preparing") => Phase::Preparing,
                _ => Phase::Running,
            };
            let u = |v: jint| v.clamp(1, u16::MAX as jint) as u16;

            let spec = SpawnSpec {
                label: session.label.clone(),
                argv,
                cwd,
                envp,
                rows: u(rows),
                cols: u(cols),
                cell_w: u(cell_w),
                cell_h: u(cell_h),
                initial_phase: phase,
                auto_restart: auto_restart == JNI_TRUE,
            };

            Ok(match lifecycle::start(&session, spec) {
                Ok(info) => ok_envelope(serde_json::json!({ "info": info.to_json() })),
                Err(e) => error_envelope(e),
            })
        })
        .resolve::<LogErrorAndDefault>()
}

/// 优雅停止：把停止命令写进 PTY（支持 `^C` 这类 caret 记号）。
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_venti1112_edgecube_pty_PtyBridge_nativeStop<'local>(
    mut unowned: EnvUnowned<'local>,
    _this: JObject<'local>,
    handle: jlong,
    stop_command: JString<'local>,
    line_ending: JString<'local>,
) -> jstring {
    unowned
        .with_env(|env| -> Result<jstring> {
            let cmd = jstr(env, &stop_command).unwrap_or_default();
            let ending = jstr(env, &line_ending).unwrap_or_else(|| "\n".into());
            Ok(match session_of(handle) {
                Ok(session) => match lifecycle::stop(&session, &cmd, &ending) {
                    Ok(()) => ok_envelope(serde_json::json!({})),
                    Err(e) => error_envelope(e),
                },
                Err(e) => error_envelope(e),
            })
        })
        .resolve::<LogErrorAndDefault>()
}

/// 强制停止：整组 SIGKILL（**先 killpg 再 killer**，见 `lifecycle.rs`）。
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_venti1112_edgecube_pty_PtyBridge_nativeKill<'local>(
    _unowned: EnvUnowned<'local>,
    _this: JObject<'local>,
    handle: jlong,
) -> jstring {
    match session_of(handle) {
        Ok(session) => match lifecycle::kill(&session) {
            Ok(()) => ok_envelope(serde_json::json!({})),
            Err(e) => error_envelope(e),
        },
        Err(e) => error_envelope(e),
    }
}

/// 前端匹配到就绪标记后调：`starting` → `running`。
///
/// Rust 不读输出流里那个标记（`DONE_PATTERN` 在 Kotlin 的行组装里），
/// 所以状态推进必须由 Kotlin 显式点一下。
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_venti1112_edgecube_pty_PtyBridge_nativeNotifyReady<'local>(
    _unowned: EnvUnowned<'local>,
    _this: JObject<'local>,
    handle: jlong,
) {
    if let Ok(session) = session_of(handle) {
        lifecycle::notify_ready(&session);
    }
}

/// 静默收掉进程（不改阶段、不发通知）。
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_venti1112_edgecube_pty_PtyBridge_nativeShutdownQuiet<'local>(
    _unowned: EnvUnowned<'local>,
    _this: JObject<'local>,
    handle: jlong,
) {
    if let Ok(session) = session_of(handle) {
        lifecycle::shutdown_quiet(&session);
    }
}

/// 往 PTY 写原始字节。`0` = 成功，`1` = 没有在跑的进程。
///
/// 热路径（每个按键都会走），所以返回 int 而不是 JSON；
/// 且 [`Session::write`] 走无界通道，**永不阻塞主线程**（修缺陷 A6）。
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_venti1112_edgecube_pty_PtyBridge_nativeWrite<'local>(
    mut unowned: EnvUnowned<'local>,
    _this: JObject<'local>,
    handle: jlong,
    bytes: JByteArray<'local>,
) -> jint {
    unowned
        .with_env(|env| -> Result<jint> {
            let Ok(session) = session_of(handle) else {
                return Ok(1);
            };
            let Ok(data) = env.convert_byte_array(&bytes) else {
                return Ok(1);
            };
            Ok(session.write(data).map(|_| 0).unwrap_or(1))
        })
        .resolve::<LogErrorAndDefault>()
}

/// 调窗口尺寸。`0` = 成功，`1` = 没有在跑的进程。
///
/// 异步交给输入线程执行，因此这里同样不阻塞（修缺陷 A6）。
#[allow(clippy::too_many_arguments)]
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_venti1112_edgecube_pty_PtyBridge_nativeResize<'local>(
    _unowned: EnvUnowned<'local>,
    _this: JObject<'local>,
    handle: jlong,
    rows: jint,
    cols: jint,
    cell_w: jint,
    cell_h: jint,
) -> jint {
    let Ok(session) = session_of(handle) else {
        return 1;
    };
    if rows <= 0 || cols <= 0 {
        return 0;
    }
    let u = |v: jint| v.clamp(1, u16::MAX as jint) as u16;
    session
        .resize(u(cols), u(rows), u(cell_w), u(cell_h))
        .map(|_| 0)
        .unwrap_or(1)
}

/// 开关回显。`0` = 成功，`1` = 没有在跑的进程。
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_venti1112_edgecube_pty_PtyBridge_nativeSetEcho<'local>(
    _unowned: EnvUnowned<'local>,
    _this: JObject<'local>,
    handle: jlong,
    echo: jboolean,
) -> jint {
    let Ok(session) = session_of(handle) else {
        return 1;
    };
    session.set_echo(echo == JNI_TRUE).map(|_| 0).unwrap_or(1)
}

/// 订阅输出；返回 sub id（0 = 句柄 / listener 无效）。
///
/// `withHistory` 为真时，在 broadcast 锁内同步把 `ReplayBegin / 分片 / ReplayEnd`
/// 全部投给 `listener`，**投完才注册**。见 `broadcast.rs::subscribe`。
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_venti1112_edgecube_pty_PtyBridge_nativeSubscribe<'local>(
    mut unowned: EnvUnowned<'local>,
    _this: JObject<'local>,
    handle: jlong,
    listener: JObject<'local>,
    with_history: jboolean,
) -> jlong {
    unowned
        .with_env(|env| -> Result<jlong> {
            let (Ok(session), Some(vm)) = (session_of(handle), jvm()) else {
                return Ok(0);
            };
            let Ok(global) = env.new_global_ref(&listener) else {
                return Ok(0);
            };
            let sink: SharedSink = Arc::new(JniSink {
                vm,
                listener: global,
            });
            Ok(session.subscribe(sink, with_history == JNI_TRUE) as jlong)
        })
        .resolve::<LogErrorAndDefault>()
}

/// 退订；**不影响进程**（断开连接 ≠ 停服务）。
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_venti1112_edgecube_pty_PtyBridge_nativeUnsubscribe<'local>(
    _unowned: EnvUnowned<'local>,
    _this: JObject<'local>,
    handle: jlong,
    sub_id: jlong,
) {
    if let Ok(session) = session_of(handle) {
        session.unsubscribe(sub_id as u64);
    }
}

/// 清输出历史（与界面清屏同步）；**保留订阅者**。
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_venti1112_edgecube_pty_PtyBridge_nativeClearHistory<'local>(
    _unowned: EnvUnowned<'local>,
    _this: JObject<'local>,
    handle: jlong,
) {
    if let Ok(session) = session_of(handle) {
        session.clear_history();
    }
}

/// 往控制台写一条 EdgeCube 自己的提示。
///
/// 进历史 → 经 sink 同时出现在 `term`（画面）与 `log`（行组装在 sink 回调里跑）
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_venti1112_edgecube_pty_PtyBridge_nativeNotice<'local>(
    mut unowned: EnvUnowned<'local>,
    _this: JObject<'local>,
    handle: jlong,
    text: JString<'local>,
) {
    unowned
        .with_env(|env| -> Result<()> {
            if let Ok(session) = session_of(handle)
                && let Some(text) = jstr(env, &text)
            {
                session.notice(&text);
            }
            Ok(())
        })
        .resolve::<LogErrorAndDefault>();
}

/// 当前状态 JSON（`RunInfo` 的 state 载荷）；句柄无效时返回 `"{}"`。
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_venti1112_edgecube_pty_PtyBridge_nativeInfo<'local>(
    _unowned: EnvUnowned<'local>,
    _this: JObject<'local>,
    handle: jlong,
) -> jstring {
    match session_of(handle) {
        Ok(session) => new_string_raw(&session.info().state_json()),
        Err(_) => new_string_raw("{}"),
    }
}
