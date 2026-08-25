use std::collections::{HashMap, VecDeque};
use std::future::Future;
use std::path::PathBuf;
use std::pin::Pin;
use std::sync::{Arc, Mutex, MutexGuard};

use uc_core::ids::ProfileId;

use crate::{
    SpaceFileAssembly, SpaceFileEventData, SpaceFileStatusEventData, SpaceImageEventData,
    SpaceTextEventData,
};

pub(crate) type SpaceRuntimeFuture<T> = Pin<Box<dyn Future<Output = T> + Send + 'static>>;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct SpaceRuntimeProfileConfig {
    pub(crate) profile_id: ProfileId,
    pub(crate) data_root: PathBuf,
    pub(crate) cache_root: PathBuf,
    pub(crate) namespace: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum SpaceRuntimeFailureCategory {
    Bootstrap,
    Runtime,
    Storage,
    Network,
    Superseded,
}

pub(crate) trait SupervisedSpaceRuntime: Send {
    fn shutdown(self: Box<Self>) -> SpaceRuntimeFuture<()>;
}

pub(crate) trait SpaceRuntimeFactory: Send + Sync {
    fn create(
        &self,
        config: SpaceRuntimeProfileConfig,
    ) -> SpaceRuntimeFuture<Result<Box<dyn SupervisedSpaceRuntime>, SpaceRuntimeFailureCategory>>;
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum SpaceRuntimeLifecycle {
    Starting,
    Running,
    Stopping,
    Failed,
    Stopped,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct SpaceRuntimeStatus {
    pub(crate) profile_id: ProfileId,
    pub(crate) generation: u64,
    pub(crate) lifecycle: SpaceRuntimeLifecycle,
    pub(crate) last_failure: Option<SpaceRuntimeFailureCategory>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum SpaceRuntimeStartDisposition {
    Started,
    Existing,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct SpaceRuntimeStart {
    pub(crate) disposition: SpaceRuntimeStartDisposition,
    pub(crate) status: SpaceRuntimeStatus,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct SpaceRuntimeStartError {
    pub(crate) profile_id: ProfileId,
    pub(crate) generation: u64,
    pub(crate) category: SpaceRuntimeFailureCategory,
}

pub(crate) struct SpaceRuntimeSlot {
    generation: u64,
    lifecycle: SpaceRuntimeLifecycle,
    last_failure: Option<SpaceRuntimeFailureCategory>,
    pending_start_generation: Option<u64>,
    lifecycle_notify: Arc<tokio::sync::Notify>,
    runtime: Option<Box<dyn SupervisedSpaceRuntime>>,
    inbound_task: Option<tokio::task::JoinHandle<()>>,
    keepalive_task: Option<tokio::task::JoinHandle<()>>,
    materialized_file_task: Option<tokio::task::JoinHandle<()>>,
    keepalive_wake: Arc<tokio::sync::Notify>,
    keepalive_force_verify: bool,
    background_sync_active: bool,
    text_events: VecDeque<SpaceTextEventData>,
    image_events: VecDeque<SpaceImageEventData>,
    file_events: VecDeque<SpaceFileEventData>,
    file_status_events: VecDeque<SpaceFileStatusEventData>,
    file_assemblies: HashMap<String, SpaceFileAssembly>,
    file_transfer_seq: u64,
    device_types: HashMap<String, String>,
    local_device_type: String,
    profile_announced: bool,
}

impl SpaceRuntimeSlot {
    fn starting(generation: u64) -> Self {
        Self {
            generation,
            lifecycle: SpaceRuntimeLifecycle::Starting,
            last_failure: None,
            pending_start_generation: Some(generation),
            lifecycle_notify: Arc::new(tokio::sync::Notify::new()),
            runtime: None,
            inbound_task: None,
            keepalive_task: None,
            materialized_file_task: None,
            keepalive_wake: Arc::new(tokio::sync::Notify::new()),
            keepalive_force_verify: false,
            background_sync_active: false,
            text_events: VecDeque::new(),
            image_events: VecDeque::new(),
            file_events: VecDeque::new(),
            file_status_events: VecDeque::new(),
            file_assemblies: HashMap::new(),
            file_transfer_seq: 1,
            device_types: HashMap::new(),
            local_device_type: "unknown".to_string(),
            profile_announced: false,
        }
    }

    fn status(&self, profile_id: ProfileId) -> SpaceRuntimeStatus {
        SpaceRuntimeStatus {
            profile_id,
            generation: self.generation,
            lifecycle: self.lifecycle,
            last_failure: self.last_failure,
        }
    }

    fn advance_generation(&mut self) -> u64 {
        self.generation = self
            .generation
            .checked_add(1)
            .expect("space runtime generation exhausted");
        self.generation
    }

    fn begin_start(&mut self) -> u64 {
        let generation = self.advance_generation();
        self.lifecycle = SpaceRuntimeLifecycle::Starting;
        self.last_failure = None;
        self.pending_start_generation = Some(generation);
        self.runtime = None;
        self.clear_transient_state();
        generation
    }

    fn abort_tasks(&mut self) {
        for task in [
            self.inbound_task.take(),
            self.keepalive_task.take(),
            self.materialized_file_task.take(),
        ]
        .into_iter()
        .flatten()
        {
            task.abort();
        }
    }

    fn clear_transient_state(&mut self) {
        self.text_events.clear();
        self.image_events.clear();
        self.file_events.clear();
        self.file_status_events.clear();
        self.file_assemblies.clear();
        self.device_types.clear();
        self.keepalive_force_verify = false;
        self.background_sync_active = false;
        self.local_device_type = "unknown".to_string();
        self.profile_announced = false;
    }
}

pub(crate) struct SpaceRuntimeSupervisor {
    factory: Arc<dyn SpaceRuntimeFactory>,
    slots: Mutex<HashMap<ProfileId, SpaceRuntimeSlot>>,
}

enum SpaceRuntimeStopAction {
    Return(SpaceRuntimeStatus),
    Wait {
        generation: u64,
        notify: Arc<tokio::sync::Notify>,
    },
    Shutdown {
        generation: u64,
        pending_start_generation: Option<u64>,
        runtime: Option<Box<dyn SupervisedSpaceRuntime>>,
        notify: Arc<tokio::sync::Notify>,
    },
}

impl SpaceRuntimeSupervisor {
    pub(crate) fn new(factory: Arc<dyn SpaceRuntimeFactory>) -> Self {
        Self {
            factory,
            slots: Mutex::new(HashMap::new()),
        }
    }

    pub(crate) async fn start(
        &self,
        config: SpaceRuntimeProfileConfig,
    ) -> Result<SpaceRuntimeStart, SpaceRuntimeStartError> {
        let profile_id = config.profile_id.clone();
        let generation = {
            let mut slots = self.lock_slots();
            match slots.get_mut(&profile_id) {
                Some(slot)
                    if matches!(
                        slot.lifecycle,
                        SpaceRuntimeLifecycle::Starting
                            | SpaceRuntimeLifecycle::Running
                            | SpaceRuntimeLifecycle::Stopping
                    ) =>
                {
                    return Ok(SpaceRuntimeStart {
                        disposition: SpaceRuntimeStartDisposition::Existing,
                        status: slot.status(profile_id),
                    });
                }
                Some(slot) => slot.begin_start(),
                None => {
                    let generation = 1;
                    slots.insert(profile_id.clone(), SpaceRuntimeSlot::starting(generation));
                    generation
                }
            }
        };

        match self.factory.create(config).await {
            Ok(runtime) => {
                let mut runtime = Some(runtime);
                let committed = {
                    let mut slots = self.lock_slots();
                    let slot = slots
                        .get_mut(&profile_id)
                        .expect("starting slot must remain registered");
                    if slot.generation != generation
                        || slot.lifecycle != SpaceRuntimeLifecycle::Starting
                        || slot.pending_start_generation != Some(generation)
                    {
                        None
                    } else {
                        slot.runtime = runtime.take();
                        slot.pending_start_generation = None;
                        slot.lifecycle = SpaceRuntimeLifecycle::Running;
                        slot.last_failure = None;
                        Some((
                            slot.status(profile_id.clone()),
                            Arc::clone(&slot.lifecycle_notify),
                        ))
                    }
                };
                match committed {
                    Some((status, notify)) => {
                        notify.notify_waiters();
                        Ok(SpaceRuntimeStart {
                            disposition: SpaceRuntimeStartDisposition::Started,
                            status,
                        })
                    }
                    None => {
                        runtime
                            .expect("cancelled start must retain its runtime")
                            .shutdown()
                            .await;
                        self.finish_pending_start(&profile_id, generation);
                        Err(SpaceRuntimeStartError {
                            profile_id,
                            generation,
                            category: SpaceRuntimeFailureCategory::Superseded,
                        })
                    }
                }
            }
            Err(category) => {
                let notify = {
                    let mut slots = self.lock_slots();
                    let slot = slots
                        .get_mut(&profile_id)
                        .expect("starting slot must remain registered");
                    if slot.generation == generation
                        && slot.lifecycle == SpaceRuntimeLifecycle::Starting
                        && slot.pending_start_generation == Some(generation)
                    {
                        slot.pending_start_generation = None;
                        slot.lifecycle = SpaceRuntimeLifecycle::Failed;
                        slot.last_failure = Some(category);
                        Some(Arc::clone(&slot.lifecycle_notify))
                    } else {
                        None
                    }
                };
                if let Some(notify) = notify {
                    notify.notify_waiters();
                } else {
                    self.finish_pending_start(&profile_id, generation);
                }
                Err(SpaceRuntimeStartError {
                    profile_id,
                    generation,
                    category,
                })
            }
        }
    }

    pub(crate) async fn stop(&self, profile_id: &ProfileId) -> Option<SpaceRuntimeStatus> {
        loop {
            let action = {
                let mut slots = self.lock_slots();
                let slot = slots.get_mut(profile_id)?;
                match slot.lifecycle {
                    SpaceRuntimeLifecycle::Stopped => {
                        SpaceRuntimeStopAction::Return(slot.status(profile_id.clone()))
                    }
                    SpaceRuntimeLifecycle::Stopping => SpaceRuntimeStopAction::Wait {
                        generation: slot.generation,
                        notify: Arc::clone(&slot.lifecycle_notify),
                    },
                    SpaceRuntimeLifecycle::Failed => {
                        slot.lifecycle = SpaceRuntimeLifecycle::Stopped;
                        slot.last_failure = None;
                        SpaceRuntimeStopAction::Return(slot.status(profile_id.clone()))
                    }
                    SpaceRuntimeLifecycle::Starting | SpaceRuntimeLifecycle::Running => {
                        let pending_start_generation = slot.pending_start_generation;
                        let generation = slot.advance_generation();
                        slot.lifecycle = SpaceRuntimeLifecycle::Stopping;
                        slot.last_failure = None;
                        slot.abort_tasks();
                        slot.clear_transient_state();
                        SpaceRuntimeStopAction::Shutdown {
                            generation,
                            pending_start_generation,
                            runtime: slot.runtime.take(),
                            notify: Arc::clone(&slot.lifecycle_notify),
                        }
                    }
                }
            };

            match action {
                SpaceRuntimeStopAction::Return(status) => return Some(status),
                SpaceRuntimeStopAction::Wait { generation, notify } => {
                    self.wait_until_not_stopping(profile_id, generation, &notify)
                        .await;
                }
                SpaceRuntimeStopAction::Shutdown {
                    generation,
                    pending_start_generation,
                    runtime,
                    notify,
                } => {
                    if let Some(runtime) = runtime {
                        runtime.shutdown().await;
                    }
                    if let Some(pending_start_generation) = pending_start_generation {
                        self.wait_for_pending_start(
                            profile_id,
                            generation,
                            pending_start_generation,
                            &notify,
                        )
                        .await;
                    }
                    return self.complete_stopping(
                        profile_id,
                        generation,
                        SpaceRuntimeLifecycle::Stopped,
                        None,
                    );
                }
            }
        }
    }

    pub(crate) async fn report_failure(
        &self,
        profile_id: &ProfileId,
        generation: u64,
        category: SpaceRuntimeFailureCategory,
    ) -> bool {
        let transition = {
            let mut slots = self.lock_slots();
            let Some(slot) = slots.get_mut(profile_id) else {
                return false;
            };
            if slot.generation != generation || slot.lifecycle != SpaceRuntimeLifecycle::Running {
                return false;
            }
            let failure_generation = slot.advance_generation();
            slot.lifecycle = SpaceRuntimeLifecycle::Stopping;
            slot.last_failure = None;
            slot.abort_tasks();
            slot.clear_transient_state();
            (failure_generation, slot.runtime.take())
        };

        if let Some(runtime) = transition.1 {
            runtime.shutdown().await;
        }
        self.complete_stopping(
            profile_id,
            transition.0,
            SpaceRuntimeLifecycle::Failed,
            Some(category),
        );
        true
    }

    pub(crate) fn status(&self, profile_id: &ProfileId) -> Option<SpaceRuntimeStatus> {
        self.lock_slots()
            .get(profile_id)
            .map(|slot| slot.status(profile_id.clone()))
    }

    fn finish_pending_start(&self, profile_id: &ProfileId, generation: u64) {
        let notify = {
            let mut slots = self.lock_slots();
            let slot = slots
                .get_mut(profile_id)
                .expect("pending start slot must remain registered");
            if slot.pending_start_generation == Some(generation) {
                slot.pending_start_generation = None;
                Some(Arc::clone(&slot.lifecycle_notify))
            } else {
                None
            }
        };
        if let Some(notify) = notify {
            notify.notify_waiters();
        }
    }

    async fn wait_for_pending_start(
        &self,
        profile_id: &ProfileId,
        stopping_generation: u64,
        pending_start_generation: u64,
        notify: &Arc<tokio::sync::Notify>,
    ) {
        loop {
            let notified = notify.notified();
            let is_pending = {
                let slots = self.lock_slots();
                slots.get(profile_id).is_some_and(|slot| {
                    slot.generation == stopping_generation
                        && slot.lifecycle == SpaceRuntimeLifecycle::Stopping
                        && slot.pending_start_generation == Some(pending_start_generation)
                })
            };
            if !is_pending {
                return;
            }
            notified.await;
        }
    }

    async fn wait_until_not_stopping(
        &self,
        profile_id: &ProfileId,
        generation: u64,
        notify: &Arc<tokio::sync::Notify>,
    ) {
        loop {
            let notified = notify.notified();
            let is_stopping = {
                let slots = self.lock_slots();
                slots.get(profile_id).is_some_and(|slot| {
                    slot.generation == generation
                        && slot.lifecycle == SpaceRuntimeLifecycle::Stopping
                })
            };
            if !is_stopping {
                return;
            }
            notified.await;
        }
    }

    fn complete_stopping(
        &self,
        profile_id: &ProfileId,
        generation: u64,
        lifecycle: SpaceRuntimeLifecycle,
        last_failure: Option<SpaceRuntimeFailureCategory>,
    ) -> Option<SpaceRuntimeStatus> {
        let completed = {
            let mut slots = self.lock_slots();
            let slot = slots.get_mut(profile_id)?;
            if slot.generation == generation && slot.lifecycle == SpaceRuntimeLifecycle::Stopping {
                slot.lifecycle = lifecycle;
                slot.last_failure = last_failure;
                Some((
                    slot.status(profile_id.clone()),
                    Arc::clone(&slot.lifecycle_notify),
                ))
            } else {
                None
            }
        };
        if let Some((status, notify)) = completed {
            notify.notify_waiters();
            Some(status)
        } else {
            self.status(profile_id)
        }
    }

    fn lock_slots(&self) -> MutexGuard<'_, HashMap<ProfileId, SpaceRuntimeSlot>> {
        match self.slots.lock() {
            Ok(slots) => slots,
            Err(poisoned) => poisoned.into_inner(),
        }
    }
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;
    use std::future::Future;
    use std::path::PathBuf;
    use std::sync::{Arc, Mutex};

    use uc_core::ids::ProfileId;

    use super::{
        SpaceRuntimeFactory, SpaceRuntimeFailureCategory, SpaceRuntimeFuture,
        SpaceRuntimeLifecycle, SpaceRuntimeProfileConfig, SpaceRuntimeStartDisposition,
        SpaceRuntimeSupervisor, SupervisedSpaceRuntime,
    };

    #[derive(Default)]
    struct FakeRuntimeFactory {
        failures: Mutex<HashMap<ProfileId, SpaceRuntimeFailureCategory>>,
        created: Mutex<Vec<SpaceRuntimeProfileConfig>>,
        stopped: Arc<Mutex<Vec<ProfileId>>>,
    }

    impl FakeRuntimeFactory {
        fn failing(profile_id: ProfileId, category: SpaceRuntimeFailureCategory) -> Self {
            Self {
                failures: Mutex::new(HashMap::from([(profile_id, category)])),
                ..Self::default()
            }
        }

        fn created_count(&self, profile_id: &ProfileId) -> usize {
            self.created
                .lock()
                .unwrap()
                .iter()
                .filter(|created| &created.profile_id == profile_id)
                .count()
        }

        fn stopped_profiles(&self) -> Vec<ProfileId> {
            self.stopped.lock().unwrap().clone()
        }
    }

    struct FakeRuntime {
        profile_id: ProfileId,
        stopped: Arc<Mutex<Vec<ProfileId>>>,
    }

    impl SupervisedSpaceRuntime for FakeRuntime {
        fn shutdown(self: Box<Self>) -> SpaceRuntimeFuture<()> {
            Box::pin(async move {
                self.stopped.lock().unwrap().push(self.profile_id);
            })
        }
    }

    impl SpaceRuntimeFactory for FakeRuntimeFactory {
        fn create(
            &self,
            config: SpaceRuntimeProfileConfig,
        ) -> SpaceRuntimeFuture<Result<Box<dyn SupervisedSpaceRuntime>, SpaceRuntimeFailureCategory>>
        {
            self.created.lock().unwrap().push(config.clone());
            let failure = self
                .failures
                .lock()
                .unwrap()
                .get(&config.profile_id)
                .copied();
            let stopped = Arc::clone(&self.stopped);
            Box::pin(async move {
                tokio::task::yield_now().await;
                match failure {
                    Some(category) => Err(category),
                    None => Ok(Box::new(FakeRuntime {
                        profile_id: config.profile_id,
                        stopped,
                    }) as Box<dyn SupervisedSpaceRuntime>),
                }
            })
        }
    }

    fn config(value: &str) -> SpaceRuntimeProfileConfig {
        SpaceRuntimeProfileConfig {
            profile_id: ProfileId::from(value),
            data_root: PathBuf::from(format!("data/{value}")),
            cache_root: PathBuf::from(format!("cache/{value}")),
            namespace: format!("namespace-{value}"),
        }
    }

    fn run<T>(future: impl Future<Output = T>) -> T {
        tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap()
            .block_on(future)
    }

    #[test]
    fn two_profiles_can_start_simultaneously() {
        let factory = Arc::new(FakeRuntimeFactory::default());
        let supervisor = Arc::new(SpaceRuntimeSupervisor::new(factory));
        let config_a = config("profile-a");
        let config_b = config("profile-b");
        let profile_a = config_a.profile_id.clone();
        let profile_b = config_b.profile_id.clone();

        run(async {
            let start_a = tokio::spawn({
                let supervisor = Arc::clone(&supervisor);
                async move { supervisor.start(config_a).await }
            });
            let start_b = tokio::spawn({
                let supervisor = Arc::clone(&supervisor);
                async move { supervisor.start(config_b).await }
            });

            assert_eq!(
                start_a.await.unwrap().unwrap().disposition,
                SpaceRuntimeStartDisposition::Started
            );
            assert_eq!(
                start_b.await.unwrap().unwrap().disposition,
                SpaceRuntimeStartDisposition::Started
            );
        });

        assert_eq!(
            supervisor.status(&profile_a).unwrap().lifecycle,
            SpaceRuntimeLifecycle::Running
        );
        assert_eq!(
            supervisor.status(&profile_b).unwrap().lifecycle,
            SpaceRuntimeLifecycle::Running
        );
    }

    #[test]
    fn stopping_one_profile_does_not_stop_another() {
        let factory = Arc::new(FakeRuntimeFactory::default());
        let supervisor = SpaceRuntimeSupervisor::new(factory.clone());
        let config_a = config("profile-a");
        let config_b = config("profile-b");
        let profile_a = config_a.profile_id.clone();
        let profile_b = config_b.profile_id.clone();

        run(async {
            supervisor.start(config_a).await.unwrap();
            supervisor.start(config_b).await.unwrap();
            let stopped = supervisor.stop(&profile_a).await.unwrap();
            assert_eq!(stopped.lifecycle, SpaceRuntimeLifecycle::Stopped);
        });

        assert_eq!(factory.stopped_profiles(), vec![profile_a.clone()]);
        assert_eq!(
            supervisor.status(&profile_a).unwrap().lifecycle,
            SpaceRuntimeLifecycle::Stopped
        );
        assert_eq!(
            supervisor.status(&profile_b).unwrap().lifecycle,
            SpaceRuntimeLifecycle::Running
        );
    }

    #[test]
    fn duplicate_start_returns_existing_status_without_rebuilding() {
        let factory = Arc::new(FakeRuntimeFactory::default());
        let supervisor = SpaceRuntimeSupervisor::new(factory.clone());
        let profile_config = config("profile-a");
        let profile_a = profile_config.profile_id.clone();

        run(async {
            let first = supervisor.start(profile_config.clone()).await.unwrap();
            let duplicate = supervisor.start(profile_config.clone()).await.unwrap();

            assert_eq!(first.disposition, SpaceRuntimeStartDisposition::Started);
            assert_eq!(
                duplicate.disposition,
                SpaceRuntimeStartDisposition::Existing
            );
            assert_eq!(duplicate.status.lifecycle, SpaceRuntimeLifecycle::Running);
        });

        assert_eq!(factory.created_count(&profile_a), 1);
    }

    #[test]
    fn failed_start_records_error_only_on_its_profile() {
        let config_a = config("profile-a");
        let config_b = config("profile-b");
        let profile_a = config_a.profile_id.clone();
        let profile_b = config_b.profile_id.clone();
        let factory = Arc::new(FakeRuntimeFactory::failing(
            profile_a.clone(),
            SpaceRuntimeFailureCategory::Bootstrap,
        ));
        let supervisor = SpaceRuntimeSupervisor::new(factory);

        let error = run(async {
            supervisor.start(config_b).await.unwrap();
            supervisor.start(config_a).await.unwrap_err()
        });

        assert_eq!(error.profile_id, profile_a);
        assert_eq!(error.category, SpaceRuntimeFailureCategory::Bootstrap);
        let status_a = supervisor.status(&profile_a).unwrap();
        assert_eq!(status_a.lifecycle, SpaceRuntimeLifecycle::Failed);
        assert_eq!(
            status_a.last_failure,
            Some(SpaceRuntimeFailureCategory::Bootstrap)
        );
        let status_b = supervisor.status(&profile_b).unwrap();
        assert_eq!(status_b.lifecycle, SpaceRuntimeLifecycle::Running);
        assert_eq!(status_b.last_failure, None);
    }
}

#[cfg(test)]
mod review_tests {
    use std::collections::{HashMap, VecDeque};
    use std::future::Future;
    use std::path::PathBuf;
    use std::sync::{Arc, Mutex};

    use tokio::sync::Barrier;
    use uc_core::ids::ProfileId;

    use super::{
        SpaceRuntimeFactory, SpaceRuntimeFailureCategory, SpaceRuntimeFuture,
        SpaceRuntimeLifecycle, SpaceRuntimeProfileConfig, SpaceRuntimeStartDisposition,
        SpaceRuntimeStatus, SpaceRuntimeSupervisor, SupervisedSpaceRuntime,
    };

    #[derive(Clone)]
    struct TestGate {
        entered: Arc<Barrier>,
        release: Arc<Barrier>,
    }

    impl TestGate {
        fn new() -> Self {
            Self {
                entered: Arc::new(Barrier::new(2)),
                release: Arc::new(Barrier::new(2)),
            }
        }

        async fn wait_until_entered(&self) {
            self.entered.wait().await;
        }

        async fn release(&self) {
            self.release.wait().await;
        }
    }

    struct StartScript {
        config: SpaceRuntimeProfileConfig,
        start_gate: Option<TestGate>,
        outcome: Result<(), SpaceRuntimeFailureCategory>,
        shutdown_gate: Option<TestGate>,
    }

    impl StartScript {
        fn success(config: SpaceRuntimeProfileConfig) -> Self {
            Self {
                config,
                start_gate: None,
                outcome: Ok(()),
                shutdown_gate: None,
            }
        }

        fn pending_success(config: SpaceRuntimeProfileConfig, gate: TestGate) -> Self {
            Self {
                config,
                start_gate: Some(gate),
                outcome: Ok(()),
                shutdown_gate: None,
            }
        }

        fn pending_failure(
            config: SpaceRuntimeProfileConfig,
            gate: TestGate,
            category: SpaceRuntimeFailureCategory,
        ) -> Self {
            Self {
                config,
                start_gate: Some(gate),
                outcome: Err(category),
                shutdown_gate: None,
            }
        }

        fn with_shutdown_gate(mut self, gate: TestGate) -> Self {
            self.shutdown_gate = Some(gate);
            self
        }
    }

    #[derive(Default)]
    struct RuntimeTracker {
        active: HashMap<ProfileId, usize>,
        max_active: HashMap<ProfileId, usize>,
    }

    impl RuntimeTracker {
        fn started(&mut self, profile_id: &ProfileId) {
            let active = self.active.entry(profile_id.clone()).or_default();
            *active += 1;
            let max_active = self.max_active.entry(profile_id.clone()).or_default();
            *max_active = (*max_active).max(*active);
        }

        fn stopped(&mut self, profile_id: &ProfileId) {
            let active = self.active.entry(profile_id.clone()).or_default();
            *active = active.saturating_sub(1);
        }
    }

    struct ScriptedRuntimeFactory {
        scripts: Mutex<VecDeque<StartScript>>,
        created_configs: Mutex<Vec<SpaceRuntimeProfileConfig>>,
        stopped_profiles: Arc<Mutex<Vec<ProfileId>>>,
        tracker: Arc<Mutex<RuntimeTracker>>,
    }

    impl ScriptedRuntimeFactory {
        fn new(scripts: Vec<StartScript>) -> Self {
            Self {
                scripts: Mutex::new(scripts.into()),
                created_configs: Mutex::new(Vec::new()),
                stopped_profiles: Arc::new(Mutex::new(Vec::new())),
                tracker: Arc::new(Mutex::new(RuntimeTracker::default())),
            }
        }

        fn created_configs(&self) -> Vec<SpaceRuntimeProfileConfig> {
            self.created_configs.lock().unwrap().clone()
        }

        fn created_count(&self, profile_id: &ProfileId) -> usize {
            self.created_configs
                .lock()
                .unwrap()
                .iter()
                .filter(|config| &config.profile_id == profile_id)
                .count()
        }

        fn max_active(&self, profile_id: &ProfileId) -> usize {
            self.tracker
                .lock()
                .unwrap()
                .max_active
                .get(profile_id)
                .copied()
                .unwrap_or_default()
        }
    }

    struct ScriptedRuntime {
        profile_id: ProfileId,
        shutdown_gate: Option<TestGate>,
        stopped_profiles: Arc<Mutex<Vec<ProfileId>>>,
        tracker: Arc<Mutex<RuntimeTracker>>,
    }

    impl SupervisedSpaceRuntime for ScriptedRuntime {
        fn shutdown(self: Box<Self>) -> SpaceRuntimeFuture<()> {
            Box::pin(async move {
                if let Some(gate) = self.shutdown_gate {
                    gate.wait_until_entered().await;
                    gate.release().await;
                }
                self.tracker.lock().unwrap().stopped(&self.profile_id);
                self.stopped_profiles.lock().unwrap().push(self.profile_id);
            })
        }
    }

    impl SpaceRuntimeFactory for ScriptedRuntimeFactory {
        fn create(
            &self,
            config: SpaceRuntimeProfileConfig,
        ) -> SpaceRuntimeFuture<Result<Box<dyn SupervisedSpaceRuntime>, SpaceRuntimeFailureCategory>>
        {
            self.created_configs.lock().unwrap().push(config.clone());
            let script = self
                .scripts
                .lock()
                .unwrap()
                .pop_front()
                .expect("a start script must be queued");
            assert_eq!(script.config, config);
            let stopped_profiles = Arc::clone(&self.stopped_profiles);
            let tracker = Arc::clone(&self.tracker);
            Box::pin(async move {
                if let Some(gate) = script.start_gate {
                    gate.wait_until_entered().await;
                    gate.release().await;
                }
                script.outcome?;
                tracker.lock().unwrap().started(&config.profile_id);
                Ok(Box::new(ScriptedRuntime {
                    profile_id: config.profile_id,
                    shutdown_gate: script.shutdown_gate,
                    stopped_profiles,
                    tracker,
                }) as Box<dyn SupervisedSpaceRuntime>)
            })
        }
    }

    fn config(value: &str) -> SpaceRuntimeProfileConfig {
        SpaceRuntimeProfileConfig {
            profile_id: ProfileId::from(value),
            data_root: PathBuf::from(format!("data/{value}")),
            cache_root: PathBuf::from(format!("cache/{value}")),
            namespace: format!("namespace-{value}"),
        }
    }

    fn run<T>(future: impl Future<Output = T>) -> T {
        tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap()
            .block_on(future)
    }

    async fn wait_for_lifecycle(
        supervisor: &SpaceRuntimeSupervisor,
        profile_id: &ProfileId,
        lifecycle: SpaceRuntimeLifecycle,
    ) -> SpaceRuntimeStatus {
        for _ in 0..1_000 {
            if let Some(status) = supervisor.status(profile_id) {
                if status.lifecycle == lifecycle {
                    return status;
                }
            }
            tokio::task::yield_now().await;
        }
        panic!("profile {profile_id} did not reach {lifecycle:?}");
    }

    #[test]
    fn stale_success_cannot_resurrect_after_stop_and_restart_attempt() {
        let profile_config = config("profile-a");
        let profile_id = profile_config.profile_id.clone();
        let first_start_gate = TestGate::new();
        let factory = Arc::new(ScriptedRuntimeFactory::new(vec![
            StartScript::pending_success(profile_config.clone(), first_start_gate.clone()),
            StartScript::success(profile_config.clone()),
        ]));
        let supervisor = Arc::new(SpaceRuntimeSupervisor::new(factory.clone()));

        run(async {
            let first_start = tokio::spawn({
                let supervisor = Arc::clone(&supervisor);
                let profile_config = profile_config.clone();
                async move { supervisor.start(profile_config).await }
            });
            first_start_gate.wait_until_entered().await;

            let stop = tokio::spawn({
                let supervisor = Arc::clone(&supervisor);
                let profile_id = profile_id.clone();
                async move { supervisor.stop(&profile_id).await }
            });
            let stopping =
                wait_for_lifecycle(&supervisor, &profile_id, SpaceRuntimeLifecycle::Stopping).await;
            assert_eq!(stopping.generation, 2);

            let restart_attempt = supervisor.start(profile_config.clone()).await.unwrap();
            assert_eq!(
                restart_attempt.disposition,
                SpaceRuntimeStartDisposition::Existing
            );
            assert_eq!(
                restart_attempt.status.lifecycle,
                SpaceRuntimeLifecycle::Stopping
            );
            assert_eq!(factory.created_count(&profile_id), 1);

            first_start_gate.release().await;
            let stale_error = first_start.await.unwrap().unwrap_err();
            assert_eq!(stale_error.generation, 1);
            assert_eq!(
                stale_error.category,
                SpaceRuntimeFailureCategory::Superseded
            );
            let stopped = stop.await.unwrap().unwrap();
            assert_eq!(stopped.lifecycle, SpaceRuntimeLifecycle::Stopped);
            assert_eq!(stopped.generation, 2);
            assert_eq!(stopped.last_failure, None);

            let restarted = supervisor.start(profile_config.clone()).await.unwrap();
            assert_eq!(restarted.disposition, SpaceRuntimeStartDisposition::Started);
            assert_eq!(restarted.status.generation, 3);
            assert_eq!(restarted.status.lifecycle, SpaceRuntimeLifecycle::Running);
        });

        assert_eq!(factory.max_active(&profile_id), 1);
    }

    #[test]
    fn stale_failure_cannot_pollute_replacement_generation() {
        let profile_config = config("profile-a");
        let profile_id = profile_config.profile_id.clone();
        let first_start_gate = TestGate::new();
        let factory = Arc::new(ScriptedRuntimeFactory::new(vec![
            StartScript::pending_failure(
                profile_config.clone(),
                first_start_gate.clone(),
                SpaceRuntimeFailureCategory::Bootstrap,
            ),
            StartScript::success(profile_config.clone()),
        ]));
        let supervisor = Arc::new(SpaceRuntimeSupervisor::new(factory));

        run(async {
            let first_start = tokio::spawn({
                let supervisor = Arc::clone(&supervisor);
                let profile_config = profile_config.clone();
                async move { supervisor.start(profile_config).await }
            });
            first_start_gate.wait_until_entered().await;
            let stop = tokio::spawn({
                let supervisor = Arc::clone(&supervisor);
                let profile_id = profile_id.clone();
                async move { supervisor.stop(&profile_id).await }
            });
            wait_for_lifecycle(&supervisor, &profile_id, SpaceRuntimeLifecycle::Stopping).await;

            let restart_attempt = supervisor.start(profile_config.clone()).await.unwrap();
            assert_eq!(
                restart_attempt.status.lifecycle,
                SpaceRuntimeLifecycle::Stopping
            );

            first_start_gate.release().await;
            let stale_error = first_start.await.unwrap().unwrap_err();
            assert_eq!(stale_error.generation, 1);
            assert_eq!(stale_error.category, SpaceRuntimeFailureCategory::Bootstrap);
            let stopped = stop.await.unwrap().unwrap();
            assert_eq!(stopped.generation, 2);
            assert_eq!(stopped.last_failure, None);

            let restarted = supervisor.start(profile_config.clone()).await.unwrap();
            assert_eq!(restarted.status.generation, 3);
            assert_eq!(restarted.status.last_failure, None);
        });
    }

    #[test]
    fn shutdown_blocks_restart_and_same_profile_runtimes_never_overlap() {
        let profile_config = config("profile-a");
        let profile_id = profile_config.profile_id.clone();
        let shutdown_gate = TestGate::new();
        let factory = Arc::new(ScriptedRuntimeFactory::new(vec![
            StartScript::success(profile_config.clone()).with_shutdown_gate(shutdown_gate.clone()),
            StartScript::success(profile_config.clone()),
        ]));
        let supervisor = Arc::new(SpaceRuntimeSupervisor::new(factory.clone()));

        run(async {
            let first = supervisor.start(profile_config.clone()).await.unwrap();
            assert_eq!(first.status.generation, 1);

            let stop = tokio::spawn({
                let supervisor = Arc::clone(&supervisor);
                let profile_id = profile_id.clone();
                async move { supervisor.stop(&profile_id).await }
            });
            shutdown_gate.wait_until_entered().await;
            let stopping = supervisor.status(&profile_id).unwrap();
            assert_eq!(stopping.lifecycle, SpaceRuntimeLifecycle::Stopping);
            assert_eq!(stopping.generation, 2);

            let restart_attempt = supervisor.start(profile_config.clone()).await.unwrap();
            assert_eq!(
                restart_attempt.status.lifecycle,
                SpaceRuntimeLifecycle::Stopping
            );
            assert_eq!(factory.created_count(&profile_id), 1);

            shutdown_gate.release().await;
            let stopped = stop.await.unwrap().unwrap();
            assert_eq!(stopped.lifecycle, SpaceRuntimeLifecycle::Stopped);

            let restarted = supervisor.start(profile_config.clone()).await.unwrap();
            assert_eq!(restarted.status.generation, 3);
            assert_eq!(factory.max_active(&profile_id), 1);
        });
    }

    #[test]
    fn generation_scoped_runtime_failure_affects_only_target_profile() {
        let config_a = config("profile-a");
        let config_b = config("profile-b");
        let profile_a = config_a.profile_id.clone();
        let profile_b = config_b.profile_id.clone();
        let factory = Arc::new(ScriptedRuntimeFactory::new(vec![
            StartScript::success(config_a.clone()),
            StartScript::success(config_b.clone()),
        ]));
        let supervisor = SpaceRuntimeSupervisor::new(factory);

        run(async {
            let started_a = supervisor.start(config_a).await.unwrap();
            let started_b = supervisor.start(config_b).await.unwrap();
            assert!(
                supervisor
                    .report_failure(
                        &profile_a,
                        started_a.status.generation,
                        SpaceRuntimeFailureCategory::Runtime,
                    )
                    .await
            );

            let failed_a = supervisor.status(&profile_a).unwrap();
            assert_eq!(failed_a.lifecycle, SpaceRuntimeLifecycle::Failed);
            assert_eq!(failed_a.generation, 2);
            assert_eq!(
                failed_a.last_failure,
                Some(SpaceRuntimeFailureCategory::Runtime)
            );
            let running_b = supervisor.status(&profile_b).unwrap();
            assert_eq!(running_b.lifecycle, SpaceRuntimeLifecycle::Running);
            assert_eq!(running_b.generation, started_b.status.generation);
            assert_eq!(running_b.last_failure, None);
            assert!(
                !supervisor
                    .report_failure(
                        &profile_b,
                        started_b.status.generation + 1,
                        SpaceRuntimeFailureCategory::Network,
                    )
                    .await
            );
            assert_eq!(supervisor.status(&profile_b).unwrap().last_failure, None);
        });
    }

    #[test]
    fn factory_receives_explicit_profile_scoped_config() {
        let profile_config = config("profile-a");
        let factory = Arc::new(ScriptedRuntimeFactory::new(vec![StartScript::success(
            profile_config.clone(),
        )]));
        let supervisor = SpaceRuntimeSupervisor::new(factory.clone());

        run(supervisor.start(profile_config.clone())).unwrap();

        assert_eq!(factory.created_configs(), vec![profile_config]);
    }
}
