//! 跨模块共享句柄的槽 —— **每个 `AppState` 一份**。
//!
//! ## 为什么需要它
//!
//! 模块之间没有对象查找：`ModuleRegistry` 只回吐 `Arc<dyn Module>`，拿不到具体
//! 类型；而确实有「A 模块要用 B 模块的能力」的场景 —— 任务系统的工作流步骤要
//! 复用下载队列、要问服务端目录（mcserver）拿下载计划。
//!
//! 以前这类共享是用**模块内的 `static OnceLock`** 兜的（`download::queue()`）。
//! 那个做法在「一个进程一个 daemon」的生产形态下没问题，但**集成测试一个进程
//! 会起多个 `AppState`**（每个 harness 一套模块），于是第二个 `AppState` 会
//! 拿到第一个的句柄 —— 那个句柄绑在第一个的数据目录 / 引擎上。症状非常隐蔽：
//! 用例**单独跑通过、跟在别的用例后面就错**。
//!
//! 把槽挂在 `AppState` 上，天然是「一份实例一份句柄」，从根上避免这件事。
//!
//! ## 用法
//!
//! ```ignore
//! // 模块 start() 里：把句柄放进去（值需要 Arc，内部就是按类型存的）
//! env.app.services.insert(Arc::new(my_handle));
//!
//! // 用的时候：拿回来（类型对不上就是 None）
//! let handle = env.app.services.get::<MyHandle>();
//! ```
//!
//! 生产形态下仍然只有一份，行为与原来的进程级全局完全一致。

use std::any::{Any, TypeId};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};

/// 按类型存句柄的容器。见模块注释。
#[derive(Default)]
pub struct Services {
    map: Mutex<HashMap<TypeId, Arc<dyn Any + Send + Sync>>>,
}

impl Services {
    pub fn new() -> Self {
        Self::default()
    }

    /// 放进一个句柄，返回被顶掉的那一个（如果有）。
    #[must_use = "被顶掉的旧句柄通常说明有地方在重复注册，不该静默丢掉"]
    pub fn insert<T: Any + Send + Sync>(&self, value: Arc<T>) -> Option<Arc<T>> {
        // 键必须写 `TypeId::of::<T>()` 而不是 `value.type_id()`：`Any` 对
        // 所有 `'static` 类型都有 blanket impl，所以 `Arc<T>` 自己也是一个
        // `Any` —— 走方法调用会解析成 `TypeId::of::<Arc<T>>()`，键就对不上了
        // （症状是「刚放进去就取不到」）。
        let previous = self
            .lock()
            .insert(TypeId::of::<T>(), value as Arc<dyn Any + Send + Sync>);
        previous.and_then(|old| old.downcast::<T>().ok())
    }

    /// 取一个句柄；没放过（或类型对不上）就是 `None`。
    pub fn get<T: Any + Send + Sync>(&self) -> Option<Arc<T>> {
        self.lock()
            .get(&TypeId::of::<T>())
            .cloned()?
            .downcast()
            .ok()
    }

    /// 取一个句柄；没有就用 `create` 造一个放进去。
    ///
    /// 模块的启动顺序由模块表决定，谁先要谁负责建 —— 所以共享句柄都走这个入口，
    /// 「谁先起来」不会影响结果。
    pub fn get_or_init<T: Any + Send + Sync>(&self, create: impl FnOnce() -> T) -> Arc<T> {
        let mut map = self.lock();
        if let Some(existing) = map.get(&TypeId::of::<T>()).cloned()
            && let Ok(typed) = existing.downcast::<T>()
        {
            return typed;
        }
        let created = Arc::new(create());
        map.insert(TypeId::of::<T>(), created.clone());
        created
    }

    /// 取走一个句柄（模块停掉时想把句柄撤掉可以用）。
    pub fn remove<T: Any + Send + Sync>(&self) -> Option<Arc<T>> {
        self.lock()
            .remove(&TypeId::of::<T>())
            .and_then(|value| value.downcast::<T>().ok())
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, HashMap<TypeId, Arc<dyn Any + Send + Sync>>> {
        self.map.lock().unwrap_or_else(|e| e.into_inner())
    }
}

impl std::fmt::Debug for Services {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // 句柄内部长什么样不重要，报个数量就够排查了
        f.debug_struct("Services")
            .field("count", &self.lock().len())
            .finish()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Debug, PartialEq)]
    struct Handle(&'static str);

    #[test]
    fn insert_get_and_remove() {
        let services = Services::new();
        assert!(services.get::<Handle>().is_none());

        assert!(services.insert(Arc::new(Handle("a"))).is_none());
        assert_eq!(services.get::<Handle>().unwrap().0, "a");

        // 同类型再放一次：旧的被顶回来（调用方能看到自己在覆盖）
        let previous = services
            .insert(Arc::new(Handle("b")))
            .expect("应当顶回旧的");
        assert_eq!(previous.0, "a");
        assert_eq!(services.get::<Handle>().unwrap().0, "b");

        assert_eq!(services.remove::<Handle>().unwrap().0, "b");
        assert!(services.get::<Handle>().is_none());
    }

    #[test]
    fn get_or_init_only_builds_once() {
        let services = Services::new();
        let built = std::sync::atomic::AtomicUsize::new(0);

        for _ in 0..3 {
            let handle = services.get_or_init(|| {
                built.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                Handle("once")
            });
            assert_eq!(handle.0, "once");
        }
        assert_eq!(built.load(std::sync::atomic::Ordering::SeqCst), 1);
    }

    /// 两个 `Services` 互不影响 —— 这正是它相对「进程级 `OnceLock`」的意义。
    #[test]
    fn two_instances_do_not_share() {
        let a = Services::new();
        let b = Services::new();
        let _ = a.insert(Arc::new(Handle("a")));

        assert_eq!(a.get::<Handle>().unwrap().0, "a");
        assert!(
            b.get::<Handle>().is_none(),
            "B 不该看见 A 的句柄（进程级全局就会在这里串）"
        );
    }
}
