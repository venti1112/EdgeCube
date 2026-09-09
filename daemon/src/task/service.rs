//! 任务调度服务:注册表 + runner 管理 + per-instance 串行队列 + 取消。
//!
//! 模型:
//! - 所有任务存于 `entries`(uuid -> Entry,常驻供历史查询),对外序列化为 [`Task`];
//! - 执行体(runner)为装箱async闭包,存于 `runners`,调度器取出后调用一次;
//! - `queues` 按 `Option<Uuid>`(None = 全局任务)分组:
//!   同一实例的任务 FIFO 串行(running 期间后续排队),跨实例并行;
//! - 全局任务(None)不排队,每次提交即独立并行执行;
//! - 同实例同 kind 未终结任务重复提交 → [`TaskError_::Conflict`](409);
//! - 任务仅存内存,daemon 重启即清空(操作不可靠恢复,不做持久化);
//! - 状态变化经 broadcast 广播 [`TaskEvent`],供 P1 WS `/events` hub 订阅,
//!   目前无订阅者时消息直接丢弃(不阻塞)。

use std::collections::{HashMap, VecDeque};
use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use chrono::Utc;
use tokio::sync::{Mutex, RwLock, broadcast};
use uuid::Uuid;

use super::model::{
    Task, TaskError, TaskEvent, TaskFailure, TaskKind, TaskList, TaskProgress, TaskStatus,
};

/// TaskService 错误(handler 层映射 HTTP 状态码)。
#[derive(Debug)]
pub enum TaskError_ {
    NotFound(Uuid),
    Conflict(TaskKind, Option<Uuid>),
}

impl std::fmt::Display for TaskError_ {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            TaskError_::NotFound(id) => write!(f, "task {id} not found"),
            TaskError_::Conflict(kind, instance) => write!(
                f,
                "task conflict: kind={kind:?} instance={instance:?} already active"
            ),
        }
    }
}

/// 执行体:接收句柄,返回成功/失败。
type Runner =
    Box<dyn FnOnce(TaskHandle) -> Pin<Box<dyn Future<Output = std::result::Result<(), TaskFailure>> + Send>>
        + Send>;

/// per-instance 队列:待执行 + 执行中。
#[derive(Debug, Default)]
struct InstanceQueue {
    pending: VecDeque<Uuid>,
    running: Option<Uuid>,
}

/// 运行时条目:契约模型(常驻) + 取消标志。
#[derive(Debug)]
struct Entry {
    task: Task,
    cancel: Arc<AtomicBool>,
}

impl Entry {
    fn new(task: Task) -> Self {
        Entry {
            task,
            cancel: Arc::new(AtomicBool::new(false)),
        }
    }
}

/// 调度器内部共享状态。
struct Inner {
    entries: RwLock<HashMap<Uuid, Entry>>,
    runners: Mutex<HashMap<Uuid, Runner>>,
    queues: RwLock<HashMap<Option<Uuid>, InstanceQueue>>,
    /// 变更广播(TaskEvent),WS hub 订阅。
    tx: broadcast::Sender<TaskEvent>,
}

/// 任务调度服务(克隆 = 共享引用)。
#[derive(Clone)]
pub struct TaskService {
    inner: Arc<Inner>,
    /// 串行化提交(去重检查 + 入队 + 存 runner),避免并发提交破环同 kind 去重。
    submit_lock: Arc<Mutex<()>>,
}

impl Default for TaskService {
    fn default() -> Self {
        Self::new()
    }
}

impl TaskService {
    pub fn new() -> Self {
        let (tx, _) = broadcast::channel(256);
        TaskService {
            inner: Arc::new(Inner {
                entries: RwLock::new(HashMap::new()),
                runners: Mutex::new(HashMap::new()),
                queues: RwLock::new(HashMap::new()),
                tx,
            }),
            submit_lock: Arc::new(Mutex::new(())),
        }
    }

    /// 订阅任务状态变更(WS `task/progress`)。
    pub fn subscribe(&self) -> broadcast::Receiver<TaskEvent> {
        self.inner.tx.subscribe()
    }

    /// 提交任务并立即返回(202 语义)。
    ///
    /// - 同实例同 kind 未终结 → [`TaskError_::Conflict`](除 DownloadSingleFile);
    /// - 全局任务(None)固定并行,实例任务按队列 FIFO 串行;
    /// - 执行体收到 [`TaskHandle`],可更新 phase/progress、轮询取消;
    ///   返回 `Ok` = 成功,`Err(TaskFailure)` = 失败;
    ///   执行中发现被取消应尽快返回,状态归为 cancelled。
    pub async fn submit<F, Fut>(&self, kind: TaskKind, instance_id: Option<Uuid>, runner: F) -> Result<Task, TaskError_>
    where
        F: FnOnce(TaskHandle) -> Fut + Send + 'static,
        Fut: Future<Output = std::result::Result<(), TaskFailure>> + Send + 'static,
    {
        self.submit_named(kind, instance_id, None, runner).await
    }

    /// 同 [`Self::submit`],额外指定展示标题 [`Task::display_name`]
    /// (下载队列横幅/列表据此显示「项目名 · 版本」等可读文案)。
    pub async fn submit_named<F, Fut>(
        &self,
        kind: TaskKind,
        instance_id: Option<Uuid>,
        display_name: Option<String>,
        runner: F,
    ) -> Result<Task, TaskError_>
    where
        F: FnOnce(TaskHandle) -> Fut + Send + 'static,
        Fut: Future<Output = std::result::Result<(), TaskFailure>> + Send + 'static,
    {
        let guard = self.submit_lock.lock().await;

        // ── 1. 同实例同 kind 去重(download_single_file 例外:允许排队串行) ──
        {
            let entries = self.inner.entries.read().await;
            let queues = self.inner.queues.read().await;
            if let Some(q) = queues.get(&instance_id) {
                for id in q.pending.iter().chain(q.running.iter()) {
                    if let Some(e) = entries.get(id) {
                        if kind != TaskKind::DownloadSingleFile
                            && e.task.kind == kind
                            && e.task.status.is_active()
                        {
                            return Err(TaskError_::Conflict(kind, instance_id));
                        }
                    }
                }
            }
        }

        // ── 2. 建任务 + 存 runner + 入队 ─────────────────────────
        let id = Uuid::new_v4();
        let task = Task {
            id,
            kind,
            instance_id,
            display_name,
            status: TaskStatus::Queued,
            phase: None,
            progress: None,
            error: None,
            created_at: Utc::now(),
            started_at: None,
            finished_at: None,
        };
        let result = task.clone();
        {
            let mut entries = self.inner.entries.write().await;
            entries.insert(id, Entry::new(task));
        }
        self.inner.runners.lock().await.insert(id, box_runner(runner));
        {
            let mut queues = self.inner.queues.write().await;
            queues
                .entry(instance_id)
                .or_default()
                .pending
                .push_back(id);
        }
        drop(guard);

        // ── 3. 触发调度(首次前移;后续在 finish 后接力) ──────────
        self.dispatch(instance_id);

        Ok(result)
    }
}

/// 将泛型闭包装箱为 [`Runner`]。
fn box_runner<F, Fut>(f: F) -> Runner
where
    F: FnOnce(TaskHandle) -> Fut + Send + 'static,
    Fut: Future<Output = std::result::Result<(), TaskFailure>> + Send + 'static,
{
    Box::new(move |handle: TaskHandle| Box::pin(f(handle)))
}

// ────────────────────────── 查询 ──────────────────────────

impl TaskService {
    /// 分页列表:进行中(queued/running)优先,其余按创建时间倒序。
    pub async fn list(
        &self,
        instance_id: Option<Uuid>,
        status: Option<TaskStatus>,
        page: u64,
        page_size: u64,
    ) -> TaskList {
        let entries = self.inner.entries.read().await;
        let mut matched: Vec<&Task> = entries
            .values()
            .map(|e| &e.task)
            .filter(|t| instance_id.is_none_or(|i| t.instance_id == Some(i)))
            .filter(|t| status.is_none_or(|s| t.status == s))
            .collect();
        matched.sort_by(|a, b| {
            let a_active = a.status.is_active();
            let b_active = b.status.is_active();
            b_active
                .cmp(&a_active)
                .then_with(|| b.created_at.cmp(&a.created_at))
        });

        let total = matched.len() as u64;
        let items = matched
            .into_iter()
            .skip(page.saturating_sub(1) as usize * page_size as usize)
            .take(page_size as usize)
            .cloned()
            .collect();
        TaskList { items, total }
    }

    /// 单个任务详情。
    pub async fn get(&self, id: Uuid) -> Option<Task> {
        let entries = self.inner.entries.read().await;
        entries.get(&id).map(|e| e.task.clone())
    }

    /// 清除某实例已终结的 download_single_file 任务(下载队列「清除已完成」)。
    /// 仅移除终态(succeeded/failed/cancelled)任务;queued/running 不受影响。
    /// 返回被清除数量。
    pub async fn clear_finished_downloads(&self, instance_id: Uuid) -> usize {
        let mut entries = self.inner.entries.write().await;
        let before = entries.len();
        entries.retain(|_, e| {
            !(e.task.instance_id == Some(instance_id)
                && e.task.kind == TaskKind::DownloadSingleFile
                && e.task.status.is_terminal())
        });
        before - entries.len()
    }

    /// 取消任务:
    /// - queued: 直接移出队列并丢弃 runner,标记 cancelled;
    /// - running: 置取消标志,由执行体尽快中断;
    /// - 已终结: `Err(TaskError_::Conflict)`。
    pub async fn cancel(&self, id: Uuid) -> Result<Task, TaskError_> {
        let mut entries = self.inner.entries.write().await;
        let entry = entries.get_mut(&id).ok_or(TaskError_::NotFound(id))?;
        if entry.task.status.is_terminal() {
            return Err(TaskError_::Conflict(entry.task.kind, entry.task.instance_id));
        }

        let cancelled_while_queued = entry.task.status == TaskStatus::Queued;
        let now = Utc::now();
        if cancelled_while_queued {
            entry.task.status = TaskStatus::Cancelled;
            entry.task.finished_at = Some(now);
            if let Some(instance) = entry.task.instance_id {
                let mut queues = self.inner.queues.write().await;
                if let Some(q) = queues.get_mut(&Some(instance)) {
                    q.pending.retain(|x| *x != id);
                }
            }
            // 丢弃未执行的 runner
            self.inner.runners.lock().await.remove(&id);
        } else {
            entry.cancel.store(true, Ordering::Relaxed);
        }

        let task = entry.task.clone();
        drop(entries);
        self.broadcast(&task);
        Ok(task)
    }
}

// ────────────────────────── 调度 ──────────────────────────

impl TaskService {
    fn broadcast(&self, task: &Task) {
        let event = TaskEvent::from(task);
        let _ = self.inner.tx.send(event);
        tracing::debug!(task_id = %task.id, status = ?task.status, "task updated");
    }

    /// 从某实例队列取下一个待执行任务:仅当队列空闲时才能取到。
    ///
    /// 全局任务(None)不检查 running,取不到即返回 None(下一轮由 finish 接力)。
    async fn take_next(&self, instance_id: Option<Uuid>) -> Option<TaskHandle> {
        let entries = self.inner.entries.read().await;
        let mut queues = self.inner.queues.write().await;
        let q = queues.entry(instance_id).or_default();
        let id = if instance_id.is_none() {
            q.pending.pop_front()
        } else {
            if q.running.is_some() {
                return None;
            }
            match q.pending.pop_front() {
                Some(id) => {
                    q.running = Some(id);
                    Some(id)
                }
                None => None,
            }
        }?;
        let entry = entries.get(&id)?;
        Some(TaskHandle {
            id,
            cancel: entry.cancel.clone(),
            svc: self.clone(),
        })
    }

    /// 触发一轮调度(spawn 一个 dispatcher 协程;并发 spawn 无害,
    /// take_next 原子取任务,抢不到即退出)。
    fn dispatch(&self, instance_id: Option<Uuid>) {
        let svc = self.clone();
        tokio::spawn(async move {
            svc.run_dispatcher(instance_id).await;
        });
    }

    /// 顺序执行某队列的任务直到队列耗尽或出现执行中任务。
    async fn run_dispatcher(&self, instance_id: Option<Uuid>) {
        loop {
            let Some(handle) = self.take_next(instance_id).await else {
                return;
            };
            let result = self.run_one(&handle).await;
            self.finish(instance_id, handle.id, result).await;
        }
    }

    /// 执行单个任务:置 running → 取 runner 调用 → 返回执行结果。
    async fn run_one(
        &self,
        handle: &TaskHandle,
    ) -> std::result::Result<(), TaskFailure> {
        self.mark_running(handle).await;
        let runner = self.inner.runners.lock().await.remove(&handle.id);
        match runner {
            Some(r) => r(handle.clone()).await,
            None => Err(TaskFailure::new("internal_error", "task runner lost")),
        }
    }

    async fn mark_running(&self, handle: &TaskHandle) {
        let mut entries = self.inner.entries.write().await;
        if let Some(entry) = entries.get_mut(&handle.id) {
            if entry.task.status == TaskStatus::Queued {
                entry.task.status = TaskStatus::Running;
                entry.task.started_at = Some(Utc::now());
                let task = entry.task.clone();
                drop(entries);
                self.broadcast(&task);
            }
        }
    }

    /// 任务收尾:更新终态、释放队列占用、接力下一个任务。
    async fn finish(
        &self,
        instance_id: Option<Uuid>,
        id: Uuid,
        result: std::result::Result<(), TaskFailure>,
    ) {
        let (status, error) = match &result {
            Ok(()) => (TaskStatus::Succeeded, None),
            Err(f) if f.code == "cancelled" => (TaskStatus::Cancelled, None),
            Err(f) => (
                TaskStatus::Failed,
                Some(TaskError::new(&f.code, &f.message)),
            ),
        };
        {
            let mut entries = self.inner.entries.write().await;
            if let Some(entry) = entries.get_mut(&id) {
                entry.task.status = status;
                entry.task.finished_at = Some(Utc::now());
                entry.task.error = error;
                let task = entry.task.clone();
                drop(entries);
                self.broadcast(&task);
            }
        }
        {
            let mut queues = self.inner.queues.write().await;
            if let Some(q) = queues.get_mut(&instance_id) {
                q.running = None;
            }
        }
        // 接力下一个(若同实例仍有排队任务)
        self.dispatch(instance_id);
    }
}

// ────────────────────────── 执行体句柄 ──────────────────────────

/// 执行体句柄:查询取消、更新 phase/progress。克隆均为同一任务的指针。
#[derive(Clone)]
pub struct TaskHandle {
    id: Uuid,
    cancel: Arc<AtomicBool>,
    svc: TaskService,
}

impl TaskHandle {
    /// 任务 id(导出归档路径等按此定位)。
    pub fn id(&self) -> Uuid {
        self.id
    }

    pub fn is_cancelled(&self) -> bool {
        self.cancel.load(Ordering::Relaxed)
    }

    /// 更新执行阶段描述(如 start 的 launching / download 的 fetching)。
    pub async fn set_phase(&self, phase: impl Into<String>) {
        let mut entries = self.svc.inner.entries.write().await;
        if let Some(entry) = entries.get_mut(&self.id) {
            entry.task.phase = Some(phase.into());
            let task = entry.task.clone();
            drop(entries);
            self.svc.broadcast(&task);
        }
    }

    /// 更新进度快照(下载/导出等有字节语义的任务)。
    pub async fn set_progress(&self, progress: TaskProgress) {
        let mut entries = self.svc.inner.entries.write().await;
        if let Some(entry) = entries.get_mut(&self.id) {
            entry.task.progress = Some(progress);
            let task = entry.task.clone();
            drop(entries);
            self.svc.broadcast(&task);
        }
    }
}

// ────────────────────────── 测试 ──────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    fn svc() -> TaskService {
        TaskService::new()
    }

    #[tokio::test]
    async fn single_task_succeeds() {
        let s = svc();
        let t = s
            .submit(TaskKind::Start, Some(Uuid::new_v4()), |_| async { Ok(()) })
            .await
            .unwrap();
        tokio::time::sleep(Duration::from_millis(50)).await;
        let done = s.get(t.id).await.unwrap();
        assert_eq!(done.status, TaskStatus::Succeeded);
        assert!(done.started_at.is_some());
        assert!(done.finished_at.is_some());
    }

    /// 占位执行体:等待外部 release 或取消信号后才结束(用于测试保持 running)。
    async fn held_runner(
        h: TaskHandle,
        mut release: tokio::sync::mpsc::Receiver<()>,
    ) -> std::result::Result<(), TaskFailure> {
        tokio::select! {
            _ = release.recv() => Ok(()),
            _ = async {
                while !h.is_cancelled() {
                    tokio::time::sleep(Duration::from_millis(5)).await;
                }
            } => Err(TaskFailure::new("cancelled", "cancelled")),
        }
    }
    use tokio::sync::mpsc;

    #[tokio::test]
    async fn same_kind_conflict_and_fifo() {
        let s = svc();
        let instance = Some(Uuid::new_v4());
        let (release_tx, release_rx) = mpsc::channel::<()>(1);
        let t1 = s
            .submit(TaskKind::Start, instance, move |h| held_runner(h, release_rx))
            .await
            .unwrap();
        tokio::time::sleep(Duration::from_millis(30)).await;
        assert_eq!(s.get(t1.id).await.unwrap().status, TaskStatus::Running);

        // 同 kind 冲突
        let dup = s
            .submit(TaskKind::Start, instance, |_| async { Ok(()) })
            .await;
        assert!(matches!(dup, Err(TaskError_::Conflict(..))));

        // 不同 kind 可排队
        let t2 = s
            .submit(TaskKind::Stop, instance, |_| async { Ok(()) })
            .await
            .unwrap();
        assert_eq!(s.get(t2.id).await.unwrap().status, TaskStatus::Queued);

        // 释放第一个,队列 FIFO 自动执行第二个
        drop(release_tx);
        tokio::time::sleep(Duration::from_millis(100)).await;
        assert_eq!(s.get(t1.id).await.unwrap().status, TaskStatus::Succeeded);
        assert_eq!(s.get(t2.id).await.unwrap().status, TaskStatus::Succeeded);
    }

    #[tokio::test]
    async fn cancel_queued_task_registers_cancelled() {
        let s = svc();
        let instance = Some(Uuid::new_v4());
        let (release_tx, release_rx) = mpsc::channel::<()>(1);
        let t1 = s
            .submit(TaskKind::Start, instance, move |h| held_runner(h, release_rx))
            .await
            .unwrap();
        let t2 = s
            .submit(TaskKind::Stop, instance, |_| async { Ok(()) })
            .await
            .unwrap();
        tokio::time::sleep(Duration::from_millis(30)).await;
        assert_eq!(s.get(t2.id).await.unwrap().status, TaskStatus::Queued);

        let cancelled = s.cancel(t2.id).await.unwrap();
        assert_eq!(cancelled.status, TaskStatus::Cancelled);
        assert!(s.get(t2.id).await.unwrap().finished_at.is_some());

        // 释放 t1:取消的 t2 不执行、队列不残留
        drop(release_tx);
        tokio::time::sleep(Duration::from_millis(80)).await;
        assert_eq!(s.get(t1.id).await.unwrap().status, TaskStatus::Succeeded);
        assert_eq!(s.get(t2.id).await.unwrap().status, TaskStatus::Cancelled);
    }

    #[tokio::test]
    async fn cancel_running_task_is_observed() {
        let s = svc();
        let instance = Some(Uuid::new_v4());
        let t = s
            .submit(TaskKind::Start, instance, |h| {
                async move {
                    while !h.is_cancelled() {
                        tokio::time::sleep(Duration::from_millis(5)).await;
                    }
                    Err(TaskFailure::new("cancelled", "cancelled"))
                }
            })
            .await
            .unwrap();
        tokio::time::sleep(Duration::from_millis(30)).await;
        assert_eq!(s.get(t.id).await.unwrap().status, TaskStatus::Running);

        let c = s.cancel(t.id).await.unwrap();
        assert_eq!(c.status, TaskStatus::Running); // 异步收敛

        tokio::time::sleep(Duration::from_millis(60)).await;
        assert_eq!(s.get(t.id).await.unwrap().status, TaskStatus::Cancelled);
    }

    #[tokio::test]
    async fn task_failure_sets_error() {
        let s = svc();
        let t = s
            .submit(TaskKind::Kill, Some(Uuid::new_v4()), |_| async {
                Err(TaskFailure::new("spawn_error", "cannot start process"))
            })
            .await
            .unwrap();
        tokio::time::sleep(Duration::from_millis(50)).await;
        let done = s.get(t.id).await.unwrap();
        assert_eq!(done.status, TaskStatus::Failed);
        let err = done.error.unwrap();
        assert_eq!(err.code, "spawn_error");
    }

    #[tokio::test]
    async fn cancel_terminal_task_conflicts() {
        let s = svc();
        let t = s
            .submit(TaskKind::Start, Some(Uuid::new_v4()), |_| async { Ok(()) })
            .await
            .unwrap();
        tokio::time::sleep(Duration::from_millis(50)).await;
        assert!(matches!(s.cancel(t.id).await, Err(TaskError_::Conflict(..))));
    }

    #[tokio::test]
    async fn list_filters_and_active_first() {
        let s = svc();
        let instance = Some(Uuid::new_v4());
        let (release_tx, release_rx) = mpsc::channel::<()>(1);
        let t1 = s
            .submit(TaskKind::Start, instance, move |h| held_runner(h, release_rx))
            .await
            .unwrap();
        let t2 = s
            .submit(TaskKind::Stop, instance, |_| async { Ok(()) })
            .await
            .unwrap();
        // 全局任务(并行)
        let t3 = s
            .submit(TaskKind::Download, None, |_| async { Ok(()) })
            .await
            .unwrap();
        tokio::time::sleep(Duration::from_millis(40)).await;

        let all = s.list(None, None, 1, 100).await;
        assert_eq!(all.total, 3);
        // 进行中(t1 running + t2 queued)优先于 t3(succeeded)
        let active: Vec<&Task> = all.items.iter().filter(|t| t.status.is_active()).collect();
        assert_eq!(active.len(), 2);
        assert!(active.iter().all(|t| t.id == t1.id || t.id == t2.id));

        let per_instance = s.list(instance, None, 1, 100).await;
        assert_eq!(per_instance.total, 2);

        let queued_only = s.list(instance, Some(TaskStatus::Queued), 1, 100).await;
        assert_eq!(queued_only.total, 1);
        assert_eq!(queued_only.items[0].id, t2.id);

        assert!(s.get(Uuid::new_v4()).await.is_none());
        drop(release_tx);
    }

    #[tokio::test]
    async fn handle_updates_phase_and_progress() {
        let s = svc();
        let t = s
            .submit(TaskKind::Download, None, |h| {
                async move {
                    h.set_phase("fetching").await;
                    h.set_progress(TaskProgress::received(100, 40)).await;
                    Ok(())
                }
            })
            .await
            .unwrap();
        tokio::time::sleep(Duration::from_millis(50)).await;
        let done = s.get(t.id).await.unwrap();
        assert_eq!(done.phase.as_deref(), Some("fetching"));
        let p = done.progress.unwrap();
        assert_eq!(p.received_bytes, Some(40));
        assert_eq!(p.total_bytes, Some(100));
    }
}