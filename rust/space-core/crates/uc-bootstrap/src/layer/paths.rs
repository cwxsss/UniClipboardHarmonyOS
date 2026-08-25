//! Directory-layout resolution.
//!
//! Resolves either legacy platform/env directories or explicit per-runtime
//! profile roots into the `AppPaths` consumed by wiring. The authoritative
//! directory layout lives in `uc-app-paths`; this module adapts it to the
//! composition root without letting explicit profiles fall back to ambient env.

use std::path::PathBuf;

use uc_core::config::AppConfig;
use uc_platform::app_dirs::DirsAppDirsAdapter;
use uc_platform::ports::AppDirsPort;

use crate::wiring::deps::{WiringError, WiringResult};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CliAppRuntimeProfileConfig {
    paths: uc_app_paths::ProfilePathConfig,
}

impl CliAppRuntimeProfileConfig {
    pub fn builder(profile_id: impl Into<String>) -> CliAppRuntimeProfileConfigBuilder {
        CliAppRuntimeProfileConfigBuilder {
            inner: uc_app_paths::ProfilePathConfig::builder(profile_id),
        }
    }

    pub fn profile_id(&self) -> &str {
        self.paths.profile_id()
    }

    pub fn secure_storage_namespace(&self) -> &str {
        self.paths.secure_storage_namespace()
    }

    pub fn namespace_for_profile(
        profile_id: &str,
    ) -> Result<String, uc_app_paths::ProfilePathConfigError> {
        uc_app_paths::ProfilePathConfig::namespace_for_profile(profile_id)
    }

    pub(crate) fn resolve_layout(&self) -> CliAppRuntimeProfileLayout {
        let app_dirs = uc_core::app_dirs::AppDirs {
            app_data_root: self.paths.data_root().to_path_buf(),
            app_cache_root: self.paths.cache_root().to_path_buf(),
            app_log_dir: self.paths.log_dir(),
        };
        let paths = uc_application::facade::AppPaths::from_app_dirs(&app_dirs);
        debug_assert_eq!(paths.db_path, self.paths.db_path());
        debug_assert_eq!(paths.vault_dir, self.paths.vault_root());

        CliAppRuntimeProfileLayout {
            profile_id: self.paths.profile_id().to_string(),
            paths,
            iroh_blob_dir: self.paths.blob_root(),
            iroh_identity_dir: self.paths.identity_root(),
            secure_storage_namespace: self.paths.secure_storage_namespace().to_string(),
        }
    }
}

pub struct CliAppRuntimeProfileConfigBuilder {
    inner: uc_app_paths::ProfilePathConfigBuilder,
}

impl CliAppRuntimeProfileConfigBuilder {
    pub fn data_root(mut self, data_root: impl Into<PathBuf>) -> Self {
        self.inner = self.inner.data_root(data_root);
        self
    }

    pub fn cache_root(mut self, cache_root: impl Into<PathBuf>) -> Self {
        self.inner = self.inner.cache_root(cache_root);
        self
    }

    pub fn secure_storage_namespace(mut self, namespace: impl Into<String>) -> Self {
        self.inner = self.inner.secure_storage_namespace(namespace);
        self
    }

    pub fn build(self) -> Result<CliAppRuntimeProfileConfig, uc_app_paths::ProfilePathConfigError> {
        self.inner
            .build()
            .map(|paths| CliAppRuntimeProfileConfig { paths })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct CliAppRuntimeProfileLayout {
    pub(crate) profile_id: String,
    pub(crate) paths: uc_application::facade::AppPaths,
    pub(crate) iroh_blob_dir: PathBuf,
    pub(crate) iroh_identity_dir: PathBuf,
    pub(crate) secure_storage_namespace: String,
}

/// Resolves the application's default directories for storing data and configuration.
pub fn get_default_app_dirs() -> WiringResult<uc_core::app_dirs::AppDirs> {
    let adapter = DirsAppDirsAdapter::new();
    adapter
        .get_app_dirs()
        .map_err(|e| WiringError::ConfigInit(e.to_string()))
}

/// Get resolved storage paths from configuration.
pub fn get_storage_paths(
    config: &uc_core::config::AppConfig,
) -> WiringResult<uc_application::facade::AppPaths> {
    let platform_dirs = get_default_app_dirs()?;
    resolve_app_paths(&platform_dirs, config)
}

/// Build `AppPaths` from platform dirs and config overrides.
pub fn resolve_app_paths(
    platform_dirs: &uc_core::app_dirs::AppDirs,
    config: &AppConfig,
) -> WiringResult<uc_application::facade::AppPaths> {
    let mut paths = uc_application::facade::AppPaths::from_app_dirs(platform_dirs);

    let is_in_memory_db = config.database_path.as_os_str() == ":memory:";

    if is_in_memory_db {
        paths.db_path = config.database_path.clone();
    } else if !config.database_path.as_os_str().is_empty() {
        if config.database_path.is_absolute() {
            // Absolute path: use as-is. In production the path is already inside
            // app_data_root_dir; tests use temp dirs and need the full path respected.
            paths.db_path = config.database_path.clone();
        } else {
            let db_file_name = config
                .database_path
                .file_name()
                .map(|name| name.to_os_string())
                .unwrap_or_else(|| std::ffi::OsString::from("uniclipboard.db"));
            paths.db_path = paths.app_data_root_dir.join(db_file_name);
        }
    }

    if !config.vault_key_path.as_os_str().is_empty() {
        let configured_vault_root = config
            .vault_key_path
            .parent()
            .unwrap_or(&config.vault_key_path)
            .to_path_buf();

        if config.database_path.as_os_str().is_empty() {
            paths.vault_dir = apply_profile_suffix(configured_vault_root);
        } else {
            let configured_db_root = config
                .database_path
                .parent()
                .unwrap_or(&config.database_path)
                .to_path_buf();

            if configured_vault_root.starts_with(&configured_db_root) {
                let relative = configured_vault_root
                    .strip_prefix(&configured_db_root)
                    .unwrap_or(std::path::Path::new(""));
                paths.vault_dir = paths.app_data_root_dir.join(relative);
            } else {
                paths.vault_dir = apply_profile_suffix(configured_vault_root);
            }
        }
    }

    Ok(paths)
}

pub fn apply_profile_suffix(path: PathBuf) -> PathBuf {
    let profile = match std::env::var("UC_PROFILE") {
        Ok(value) if !value.is_empty() => sanitize_profile(&value),
        _ => return path,
    };

    let file_name = match path.file_name().and_then(|name| name.to_str()) {
        Some(name) => name.to_string(),
        None => return path,
    };

    let mut updated = path;
    updated.set_file_name(format!("{file_name}_{profile}"));
    updated
}

#[cfg(test)]
mod profile_runtime_tests {
    use super::*;

    static ENV_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

    struct EnvRestore {
        key: &'static str,
        value: Option<std::ffi::OsString>,
    }

    impl EnvRestore {
        fn set(key: &'static str, value: &str) -> Self {
            let restore = Self {
                key,
                value: std::env::var_os(key),
            };
            std::env::set_var(key, value);
            restore
        }
    }

    impl Drop for EnvRestore {
        fn drop(&mut self) {
            match self.value.take() {
                Some(value) => std::env::set_var(self.key, value),
                None => std::env::remove_var(self.key),
            }
        }
    }

    #[test]
    fn explicit_cli_runtime_layout_uses_every_profile_owned_path() {
        // Regression target: deriving any member from process env or default
        // AppDirs would let two Harmony runtimes share persistent state.
        let _guard = ENV_LOCK.lock().unwrap();
        let _profile = EnvRestore::set("UC_PROFILE", "ambient-profile");
        let _data = EnvRestore::set("UC_OHOS_DATA_DIR", "ambient-data");
        let _cache = EnvRestore::set("UC_OHOS_CACHE_DIR", "ambient-cache");
        let root = std::env::temp_dir().join("uc-bootstrap-explicit-profile");
        let data_root_a = root.join("profile-a-data");
        let cache_root_a = root.join("profile-a-cache");
        let data_root_b = root.join("profile-b-data");
        let cache_root_b = root.join("profile-b-cache");
        let config_a = CliAppRuntimeProfileConfig::builder("profile-a")
            .data_root(&data_root_a)
            .cache_root(&cache_root_a)
            .secure_storage_namespace("harmony-profile-a")
            .build()
            .unwrap();
        let config_b = CliAppRuntimeProfileConfig::builder("profile-b")
            .data_root(&data_root_b)
            .cache_root(&cache_root_b)
            .secure_storage_namespace("harmony-profile-b")
            .build()
            .unwrap();
        let layout_a = config_a.resolve_layout();
        let layout_b = config_b.resolve_layout();

        assert_eq!(layout_a.profile_id, "profile-a");
        assert_eq!(layout_a.paths.db_path, data_root_a.join("uniclipboard.db"));
        assert_eq!(layout_a.iroh_blob_dir, data_root_a.join("iroh-blobs"));
        assert_eq!(
            layout_a.iroh_identity_dir,
            data_root_a.join("iroh-identity")
        );
        assert_eq!(layout_a.paths.vault_dir, data_root_a.join("vault"));
        assert_eq!(layout_a.paths.cache_dir, cache_root_a);
        assert_eq!(layout_a.secure_storage_namespace, "harmony-profile-a");

        assert_ne!(layout_a.paths.db_path, layout_b.paths.db_path);
        assert_ne!(layout_a.iroh_blob_dir, layout_b.iroh_blob_dir);
        assert_ne!(layout_a.iroh_identity_dir, layout_b.iroh_identity_dir);
        assert_ne!(layout_a.paths.vault_dir, layout_b.paths.vault_dir);
        assert_ne!(layout_a.paths.cache_dir, layout_b.paths.cache_dir);
        assert_ne!(
            layout_a.secure_storage_namespace,
            layout_b.secure_storage_namespace
        );
    }
}

/// Normalize a `UC_PROFILE` value into a filesystem-safe suffix.
///
/// Maps every character that is invalid in a Windows filename
/// (`< > : " / \ | ? *` and ASCII control characters) to `_`, so the profile
/// can be safely appended to a file name on any platform. Other platforms only
/// reject `/` (and the NUL byte), so this is a superset of their constraints.
fn sanitize_profile(value: &str) -> String {
    value
        .chars()
        .map(|c| match c {
            '<' | '>' | ':' | '"' | '/' | '\\' | '|' | '?' | '*' => '_',
            c if c.is_control() => '_',
            c => c,
        })
        .collect()
}
