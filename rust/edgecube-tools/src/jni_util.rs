//! JNI 共用辅助：异常投递与 Java 侧数据读取。

use jni::Env;
use jni::objects::{JObject, JObjectArray, JString};
use jni::strings::JNIString;

/// 按类名抛出 Java 异常。
pub fn throw_java(env: &mut Env, class: &str, msg: &str) {
    let _ = env.throw_new(JNIString::new(class), JNIString::new(msg));
}

/// 读取 `java.lang.String`；null / 解码失败返回 `None`。
pub fn jstr(env: &mut Env, s: &JString) -> Option<String> {
    s.try_to_string(env).ok()
}

pub fn jobj_to_jstr_vec(env: &mut Env, obj: &JObject) -> Option<Vec<String>> {
    if obj.is_null() {
        return None;
    }
    let arr: JObjectArray<JString> = unsafe {

        JObjectArray::<JString>::from_raw(env, obj.as_raw())
    };
    jstr_vec(env, &arr)
}

/// 读取 `String[]`；任一元素失败整体返回 `None`。
pub fn jstr_vec(env: &mut Env, arr: &JObjectArray<JString>) -> Option<Vec<String>> {
    let n = arr.len(env).ok()?;
    let mut out = Vec::with_capacity(n);
    for i in 0..n {
        let item: JString = arr.get_element(env, i).ok()?;
        out.push(jstr(env, &item)?);
    }
    Some(out)
}

/// 回调 Kotlin 后清理可能残留的 pending exception。
pub fn clear_exception(env: &mut Env) {
    if env.exception_check() {
        env.exception_clear();
    }
}
