//! CLI dev-tools composition-root entry.
//!
//! Runs tracing init + `wire_dependencies` through the private `build_core()`
//! and returns the wired dependencies for CLI commands. The CLI does not spawn
//! background workers, so the `BackgroundRuntimeDeps` it produces are dropped.
//! Process-level runtime entry (`build_process_runtime` + `ProcessRuntimeContext`)
//! lives in [`uc_desktop::bootstrap`]; this crate stays shell-agnostic and only
//! provides composition-root tooling.

use uc_core::config::AppConfig;

use crate::layer::paths::{get_storage_paths, CliAppRuntimeProfileConfig};
use crate::wiring::deps::BackgroundRuntimeDeps;
use crate::wiring::wire::{wire_dependencies, wire_dependencies_for_profile};

/// Shared core wiring for the CLI composition-root entry.
/// Initializes tracing, resolves config, wires dependencies, and registers the
/// process-wide product analytics `EventContext`.
///
/// If `log_profile_override` is `Some`, the `UC_LOG_PROFILE` env var is set
/// before tracing initialization so the subscriber picks up the desired profile.
///
/// ## Async because of `compose_event_context`
///
/// Slice 6 / Issue #549 起 `build_core` 转 async：装配 `EventContext` 必须在
/// `wire_dependencies` 之后做，因为它要读 `member_repo` / `setup_status`
/// 这两个 async port 才能算出 `active_device_count` 与 `space_id_hash`。把
/// 装配点放在 composition root 内（一处调用）比让每个 entry 各自补一段
/// `.await` 更不容易遗漏（例如未来再加一个 entry，自动也覆盖）。
async fn build_core(
    log_profile_override: Option<uc_observability::LogProfile>,
    runtime_profile: Option<&CliAppRuntimeProfileConfig>,
) -> anyhow::Result<(
    AppConfig,
    crate::wiring::deps::WiredDependencies,
    BackgroundRuntimeDeps,
    uc_application::facade::AppPaths,
)> {
    // Apply log profile override before tracing init
    if let Some(profile) = log_profile_override {
        std::env::set_var("UC_LOG_PROFILE", profile.to_string());
    }

    // Idempotent -- safe to call multiple times
    crate::observability::tracing::init_tracing_subscriber()?;

    // 装 panic hook 把 panic 镜像到 jsonl(target = "panic")。必须在
    // tracing init 之后,否则 hook 触发时 subscriber 还没接管 stderr,
    // 等价于啥也没做。同样幂等,内部用 OnceLock 保证三个入口共用同一份。
    crate::observability::tracing::install_panic_logging_hook();

    let config = AppConfig::empty();

    let (wired, background, storage_paths) = match runtime_profile {
        Some(profile) => {
            let storage_paths = profile.resolve_layout().paths;
            let (wired, background) = wire_dependencies_for_profile(profile)
                .map_err(|e| anyhow::anyhow!("Dependency wiring failed: {}", e))?;
            (wired, background, storage_paths)
        }
        None => {
            let (wired, background) = wire_dependencies(&config)
                .map_err(|e| anyhow::anyhow!("Dependency wiring failed: {}", e))?;
            let storage_paths = get_storage_paths(&config)?;
            (wired, background, storage_paths)
        }
    };

    // 注册进程级 product analytics `EventContext`。失败不阻断启动 —— analytics
    // 是辅助通道，错误已在 compose 内 warn-log（见 `subsystem/analytics.rs` 模块
    // 文档"失败语义"）。显式 profile 路径必须沿用上面同一份布局，不能退回
    // `get_storage_paths` 的 process-env 解析。
    // 旧 CLI 进程内路径不是临时 daemon residency → 永不抑制设备级 presence 事件
    // （ADR-008 D20），保持 pre-P5 行为；P5-1/P5-2 会整体退役这条路径。
    if let Err(err) =
        crate::subsystem::analytics::compose_event_context(&wired.deps, &storage_paths, false).await
    {
        tracing::warn!(
            error = %err,
            "analytics: compose_event_context 失败，本次进程内事件 sink 将拿不到 EventContext 快照"
        );
    }

    Ok((config, wired, background, storage_paths))
}

/// CLI composition-root entry returning the full
/// [`crate::wiring::deps::WiredDependencies`] so the caller can hand it to
/// [`crate::subsystem::sync_engine::build_sync_engine_assembly`]. It preserves access to
/// `trusted_peer_repo` and other ports the `SpaceSetupFacade` needs (pairing /
/// roster / send / watch / blob 等需要 iroh 网络栈的 CLI 命令走这条路径)。
pub(crate) async fn build_cli_wiring_context(
    log_profile: Option<uc_observability::LogProfile>,
) -> anyhow::Result<(AppConfig, crate::wiring::deps::WiredDependencies)> {
    let (config, wired, _background, _storage_paths) = build_core(log_profile, None).await?;
    Ok((config, wired))
}

pub(crate) async fn build_cli_wiring_context_for_profile(
    profile: &CliAppRuntimeProfileConfig,
    log_profile: Option<uc_observability::LogProfile>,
) -> anyhow::Result<(
    AppConfig,
    crate::wiring::deps::WiredDependencies,
    uc_application::facade::AppPaths,
)> {
    let (config, wired, _background, storage_paths) =
        build_core(log_profile, Some(profile)).await?;
    Ok((config, wired, storage_paths))
}
