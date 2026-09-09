//! 任务队列系统(openapi §Tasks / ws.md `task/progress`)。
//!
//! - [`model`]: 任务实体/状态/类型/进度,对齐 openapi Task* schema;
//! - [`service`]: 调度服务(提交/查询/取消 + per-instance 串行队列)。

pub mod model;
pub mod service;