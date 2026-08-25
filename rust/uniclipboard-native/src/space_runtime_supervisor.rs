use std::collections::{HashMap, VecDeque};
use std::future::Future;
use std::pin::Pin;
use std::sync::{Arc, Mutex, MutexGuard};

use uc_bootstrap::CliAppRuntime;
use uc_core::ids::ProfileId;

use crate::{
    SpaceFileAssembly, SpaceFileEventData, SpaceFileStatusEventData, SpaceImageEventData,
    SpaceTextEventData,
};

pub(crate) type SpaceRuntimeFuture<T> = Pin<Box<dyn Future<Output = T> + Send + 'static>>;

pub(crate) trait SupervisedSpaceRuntime: Send {
    fn shutdown(self: Box<Self>) -> SpaceRuntimeFuture<()>;
}

impl SupervisedSpaceRuntime for CliAppRuntime {
    fn shutdown(self: Box<Self>) -> SpaceRuntimeFuture<()> {
        Box::pin(async move {
            (*self).shutdown().await;
        })
    }
}

pub(crate) trait SpaceRuntimeFactory: Send + Sync {
    fn create(
        &self,
        profile_id: ProfileId,
    ) -> SpaceRuntimeFuture<Result<Box<dyn SupervisedSpaceRuntime>, String>>;
}

pub(crate) struct CliSpaceRuntimeFactory;

impl SpaceRuntimeFactory for CliSpaceRuntimeFactory {
    fn create(
        &self,
        _profile_id: ProfileId,
    ) -> SpaceRuntimeFuture<Result<Box<dyn SupervisedSpaceRuntime>, String>> {
        Box::pin(async move {
            uc_bootstrap::build_cli_app_runtime(None)
                .await
                .map(|runtime| Box::new(runtime) as Box<dyn SupervisedSpaceRuntime>)
                .map_err(|error| error.to_string())
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum SpaceRuntimeLifecycle {
    Starting,
    Running,
    Failed,
    Stopped,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct SpaceRuntimeStatus {
    pub(crate) profile_id: ProfileId,
    pub(crate) lifecycle: SpaceRuntimeLifecycle,
    pub(crate) last_error: Option<String>,
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
    pub(crate) message: String,
}

pub(crate) struct SpaceRuntimeSlot {
    lifecycle: SpaceRuntimeLifecycle,
    last_error: Option<String>,
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
    fn starting() -> Self {
        Self {
            lifecycle: SpaceRuntimeLifecycle::Starting,
            last_error: None,
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
            lifecycle: self.lifecycle,
            last_error: self.last_error.clone(),
        }
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

impl SpaceRuntimeSupervisor {
    pub(crate) fn new(factory: Arc<dyn SpaceRuntimeFactory>) -> Self {
        Self {
            factory,
            slots: Mutex::new(HashMap::new()),
        }
    }

    pub(crate) async fn start(
        &self,
        profile_id: ProfileId,
    ) -> Result<SpaceRuntimeStart, SpaceRuntimeStartError> {
        let existing = {
            let mut slots = self.lock_slots();
            match slots.get(&profile_id) {
                Some(slot)
                    if matches!(
                        slot.lifecycle,
                        SpaceRuntimeLifecycle::Starting | SpaceRuntimeLifecycle::Running
                    ) =>
                {
                    Some(slot.status(profile_id.clone()))
                }
                _ => {
                    slots.insert(profile_id.clone(), SpaceRuntimeSlot::starting());
                    None
                }
            }
        };
        if let Some(status) = existing {
            return Ok(SpaceRuntimeStart {
                disposition: SpaceRuntimeStartDisposition::Existing,
                status,
            });
        }

        match self.factory.create(profile_id.clone()).await {
            Ok(runtime) => {
                let mut runtime = Some(runtime);
                let status = {
                    let mut slots = self.lock_slots();
                    let slot = slots
                        .get_mut(&profile_id)
                        .expect("starting slot must remain registered");
                    if slot.lifecycle != SpaceRuntimeLifecycle::Starting {
                        None
                    } else {
                        slot.runtime = runtime.take();
                        slot.lifecycle = SpaceRuntimeLifecycle::Running;
                        slot.last_error = None;
                        Some(slot.status(profile_id.clone()))
                    }
                };
                match status {
                    Some(status) => Ok(SpaceRuntimeStart {
                        disposition: SpaceRuntimeStartDisposition::Started,
                        status,
                    }),
                    None => {
                        runtime
                            .expect("cancelled start must retain its runtime")
                            .shutdown()
                            .await;
                        Err(SpaceRuntimeStartError {
                            profile_id,
                            message: "space runtime start was cancelled".to_string(),
                        })
                    }
                }
            }
            Err(message) => {
                let mut slots = self.lock_slots();
                if let Some(slot) = slots.get_mut(&profile_id) {
                    if slot.lifecycle == SpaceRuntimeLifecycle::Starting {
                        slot.lifecycle = SpaceRuntimeLifecycle::Failed;
                        slot.last_error = Some(message.clone());
                    }
                }
                Err(SpaceRuntimeStartError {
                    profile_id,
                    message,
                })
            }
        }
    }

    pub(crate) async fn stop(&self, profile_id: &ProfileId) -> Option<SpaceRuntimeStatus> {
        let (runtime, status) = {
            let mut slots = self.lock_slots();
            let slot = slots.get_mut(profile_id)?;
            slot.abort_tasks();
            slot.clear_transient_state();
            slot.lifecycle = SpaceRuntimeLifecycle::Stopped;
            slot.last_error = None;
            let runtime = slot.runtime.take();
            let status = slot.status(profile_id.clone());
            (runtime, status)
        };
        if let Some(runtime) = runtime {
            runtime.shutdown().await;
        }
        Some(status)
    }

    pub(crate) fn status(&self, profile_id: &ProfileId) -> Option<SpaceRuntimeStatus> {
        self.lock_slots()
            .get(profile_id)
            .map(|slot| slot.status(profile_id.clone()))
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
    use std::sync::{Arc, Mutex};

    use uc_core::ids::ProfileId;

    use super::{
        SpaceRuntimeFactory, SpaceRuntimeFuture, SpaceRuntimeLifecycle,
        SpaceRuntimeStartDisposition, SpaceRuntimeSupervisor, SupervisedSpaceRuntime,
    };

    #[derive(Default)]
    struct FakeRuntimeFactory {
        failures: Mutex<HashMap<ProfileId, String>>,
        created: Mutex<Vec<ProfileId>>,
        stopped: Arc<Mutex<Vec<ProfileId>>>,
    }

    impl FakeRuntimeFactory {
        fn failing(profile_id: ProfileId, message: &str) -> Self {
            Self {
                failures: Mutex::new(HashMap::from([(profile_id, message.to_string())])),
                ..Self::default()
            }
        }

        fn created_count(&self, profile_id: &ProfileId) -> usize {
            self.created
                .lock()
                .unwrap()
                .iter()
                .filter(|created| *created == profile_id)
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
            profile_id: ProfileId,
        ) -> SpaceRuntimeFuture<Result<Box<dyn SupervisedSpaceRuntime>, String>> {
            self.created.lock().unwrap().push(profile_id.clone());
            let failure = self.failures.lock().unwrap().get(&profile_id).cloned();
            let stopped = Arc::clone(&self.stopped);
            Box::pin(async move {
                tokio::task::yield_now().await;
                match failure {
                    Some(message) => Err(message),
                    None => Ok(Box::new(FakeRuntime {
                        profile_id,
                        stopped,
                    }) as Box<dyn SupervisedSpaceRuntime>),
                }
            })
        }
    }

    fn profile(value: &str) -> ProfileId {
        ProfileId::from(value)
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
        let profile_a = profile("profile-a");
        let profile_b = profile("profile-b");

        run(async {
            let start_a = tokio::spawn({
                let supervisor = Arc::clone(&supervisor);
                let profile_a = profile_a.clone();
                async move { supervisor.start(profile_a).await }
            });
            let start_b = tokio::spawn({
                let supervisor = Arc::clone(&supervisor);
                let profile_b = profile_b.clone();
                async move { supervisor.start(profile_b).await }
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
        let profile_a = profile("profile-a");
        let profile_b = profile("profile-b");

        run(async {
            supervisor.start(profile_a.clone()).await.unwrap();
            supervisor.start(profile_b.clone()).await.unwrap();
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
        let profile_a = profile("profile-a");

        run(async {
            let first = supervisor.start(profile_a.clone()).await.unwrap();
            let duplicate = supervisor.start(profile_a.clone()).await.unwrap();

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
        let profile_a = profile("profile-a");
        let profile_b = profile("profile-b");
        let factory = Arc::new(FakeRuntimeFactory::failing(
            profile_a.clone(),
            "profile-a failed",
        ));
        let supervisor = SpaceRuntimeSupervisor::new(factory);

        let error = run(async {
            supervisor.start(profile_b.clone()).await.unwrap();
            supervisor.start(profile_a.clone()).await.unwrap_err()
        });

        assert_eq!(error.profile_id, profile_a);
        assert_eq!(error.message, "profile-a failed");
        let status_a = supervisor.status(&profile_a).unwrap();
        assert_eq!(status_a.lifecycle, SpaceRuntimeLifecycle::Failed);
        assert_eq!(status_a.last_error.as_deref(), Some("profile-a failed"));
        let status_b = supervisor.status(&profile_b).unwrap();
        assert_eq!(status_b.lifecycle, SpaceRuntimeLifecycle::Running);
        assert_eq!(status_b.last_error, None);
    }
}
