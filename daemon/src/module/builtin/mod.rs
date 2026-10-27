//! 内置模块。
//!
//! * [`core`] —— 框架自省与基础运维（常驻，卸不掉）。
//! * [`ticker`] —— **示例模块模板**：一个文件里把配置、HTTP 路由、WS 方法、
//!   后台任务、事件推送、优雅停止全用上了。照它抄就能加新模块。
//! * [`monitor`] —— 系统监控：设备内存与 CPU 使用率。单文件、常驻采样，
//!   是「模板之外的常规模块」该怎么写的参考。
//! * [`instance`] —— 实例管理（真正的业务模块）：元数据存储层单独拆了
//!   `store` 子模块，多文件模块照它这个结构组织。
//! * [`frp`] —— 映射隧道：平台登录 + frpc 配置生成 / 保存。多一层 `api/`
//!   子目录放各家平台客户端，**登录与轮询跑在 daemon 里**（前端只显示）。
//! * [`download`] —— 下载队列：全局的 HTTP 下载（底层 gosh-dl），落盘以实例根目录为根。
//!   跨模块依赖的写法（借 instance 的目录布局、而不复制一份）照它看。
//! * [`mcserver`] —— 服务端目录：各个服务端源的版本列表与下载地址。多一层 `api/`
//!   子目录放各家上游客户端，一个源一个文件；纯查询，不落盘也不下载。
//! * [`mods`] —— 模组与插件：Modrinth 上的搜索 / 版本列表 / 下载计划，以及实例里
//!   已装文件的列表（含从 jar 内读到的元数据）、更新检查、启停与删除。
//!   安装由 `mods-install` 工作流（`mods/mod.rs` 里的 `install` 子模块）编排。
//! * [`runtime`] —— 运行环境：下载 / 解压 / 列出 / 删除 JDK（目前是 Zulu）。
//!   安装由 `runtime-install` 工作流（`runtime/install.rs`）编排。
//! * [`task`] —— 任务系统：基于 szal 的工作流引擎，把多步操作（创建→下载、
//!   下载→解压）编排成任务。模块只管执行与可观测性，工作流定义由各业务模块
//!   在 `start()` 里注册步骤与模板。
//! * [`upnp`] —— 路由器端口映射（UPnP）：按实例配置在实例启动时加映射、
//!   停止时撤映射。**不挂钩子，靠监听 `instance.*` 事件对齐状态** ——
//!   多实例下网关共享一份、映射各记各的（单文件监听 + 传输层拆开的写法照它看）。
//! * [`stun`] —— STUN 打洞隧道：面向不支持 UPnP 的网络，按实例配置在实例启动时
//!   向 STUN 服务器打洞并本地监听转发（nyat-core）。与 upnp 同为「监听
//!   `instance.*` 事件对齐状态」的多文件模块，打洞实现单独拆了 `mapper` 层
//!   （trait 可换假实现，测试照它看）。
//! * [`shell`] —— 主机终端：daemon 所在机器上的一个交互式 shell（单会话）。
//!   与控制台共用 `crate::pty` 的历史/订阅层，协议也一样，所以前端不用为它
//!   写第二套解析。
//!
//! **跨模块共享句柄一律走 `AppState.services`**（见 [`crate::services`]）：
//! 队列句柄、工作流注册表都在那里。别再用模块内的 `static OnceLock` ——
//! 那在「一个进程多个 `AppState`」（集成测试）下会串到别的实例上。

pub mod core;
pub mod download;
pub mod frp;
pub mod instance;
pub mod mcserver;
pub mod mods;
pub mod monitor;
pub mod runtime;
pub mod shell;
pub mod stun;
pub mod task;
pub mod ticker;
pub mod upnp;
