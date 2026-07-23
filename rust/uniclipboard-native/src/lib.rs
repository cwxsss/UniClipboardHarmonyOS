use std::collections::{HashMap, VecDeque};
use std::io::Read;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

use napi_derive_ohos::napi;
use napi_ohos::bindgen_prelude::Uint8Array;
use napi_ohos::{Error, Result, Status};
use uc_mobile::{
    ClipboardKind, ClipboardMeta, HistoryPatch, MobileSyncClient, PlatformBridge, ProbeResult,
    ServerConfig as MobileServerConfig, SseHandle, SseListener,
};
use uc_mobile::client::{HistoryQuery, HistoryRecord};
use uc_application::facade::space_setup::{
    InitializeSpaceInput, RedeemPairingInvitationInput, SwitchSpaceInput,
};
use uc_application::facade::mobile_sync::{
    RegisterMobileShortcutDeviceInput, RevokeMobileDeviceInput,
    UpdateMobileSyncSettingsInput,
};
use uc_application::facade::{
    connection_channel_to_wire, decode_v3_bytes_to_snapshot,
    decode_v3_bytes_to_snapshot_and_blob_refs, BatchPosition, ClipboardHostEvent,
    ClipboardOriginKind, ContentTypesPatch, EmitError,
    FetchBlobToPathCommand, FetchTransferContext, HostEvent, HostEventEmitterPort, InboundAction,
    MemberSyncPreferencesPatch, MemberSyncPreferencesView, PublishBlobPathCommand,
    TransferHostEvent, V3BlobRef,
};
use uc_bootstrap::CliAppRuntime;
use uc_core::ids::{DeviceId, EntryId, FormatId, RepresentationId};
use uc_core::mobile_sync::MobileDeviceId;
use uc_core::ports::ReachabilityState;
use uc_core::{
    ClipboardChangeOrigin, MimeType, ObservedClipboardRepresentation, SystemClipboardSnapshot,
};

mod mobile_sync_server;

static MOBILE_CLIENT: OnceLock<Arc<MobileSyncClient>> = OnceLock::new();
static SSE_HANDLE: OnceLock<Mutex<Option<Arc<SseHandle>>>> = OnceLock::new();
static SSE_EVENTS: OnceLock<Mutex<VecDeque<SseEventData>>> = OnceLock::new();
static SSE_GENERATION: AtomicU64 = AtomicU64::new(0);
static SPACE_RUNTIME: OnceLock<tokio::sync::Mutex<Option<CliAppRuntime>>> = OnceLock::new();
static SPACE_INBOUND_TASK: OnceLock<Mutex<Option<tokio::task::JoinHandle<()>>>> = OnceLock::new();
static SPACE_KEEPALIVE_TASK: OnceLock<Mutex<Option<tokio::task::JoinHandle<()>>>> = OnceLock::new();
static SPACE_MATERIALIZED_FILE_TASK: OnceLock<Mutex<Option<tokio::task::JoinHandle<()>>>> =
    OnceLock::new();
static SPACE_KEEPALIVE_WAKE: OnceLock<Arc<tokio::sync::Notify>> = OnceLock::new();
static SPACE_KEEPALIVE_FORCE_VERIFY: AtomicBool = AtomicBool::new(false);
static SPACE_BACKGROUND_SYNC_ACTIVE: AtomicBool = AtomicBool::new(false);
static SPACE_TEXT_EVENTS: OnceLock<Mutex<VecDeque<SpaceTextEventData>>> = OnceLock::new();
static SPACE_IMAGE_EVENTS: OnceLock<Mutex<VecDeque<SpaceImageEventData>>> = OnceLock::new();
static SPACE_FILE_EVENTS: OnceLock<Mutex<VecDeque<SpaceFileEventData>>> = OnceLock::new();
static SPACE_FILE_STATUS_EVENTS: OnceLock<Mutex<VecDeque<SpaceFileStatusEventData>>> =
    OnceLock::new();
static SPACE_FILE_ASSEMBLIES: OnceLock<Mutex<HashMap<String, SpaceFileAssembly>>> = OnceLock::new();
static SPACE_FILE_TRANSFER_SEQ: AtomicU64 = AtomicU64::new(1);
static SPACE_DEVICE_TYPES: OnceLock<Mutex<HashMap<String, String>>> = OnceLock::new();
static SPACE_LOCAL_DEVICE_TYPE: OnceLock<Mutex<String>> = OnceLock::new();
static SPACE_PROFILE_ANNOUNCED: AtomicBool = AtomicBool::new(false);

const MAX_PENDING_SSE_EVENTS: usize = 64;
const MAX_PENDING_SPACE_EVENTS: usize = 64;
const MAX_SPACE_TEXT_BYTES: usize = 1024 * 1024;
const MAX_SPACE_IMAGE_BYTES: usize = 1536 * 1024;
const MAX_SPACE_FILE_BYTES: usize = 64 * 1024 * 1024;
const SPACE_FILE_CHUNK_BYTES: usize = 512 * 1024;
const SPACE_FILE_HEADER_BYTES: usize = 27;
const SPACE_DEVICE_PROFILE_MIME: &str = "application/x-uniclipboard-device-profile";
const SPACE_FILE_MIME: &str = "application/x-uniclipboard-file";
const SPACE_BACKGROUND_VERIFY_INTERVAL: Duration = Duration::from_secs(15);

struct HarmonyPlatformBridge;

struct HarmonySseListener {
    generation: u64,
}

struct SseEventData {
    event_type: String,
    detail: String,
}

struct SpaceTextEventData {
    text: String,
    from_device_id: String,
    snapshot_hash: String,
}

struct SpaceImageEventData {
    data: Vec<u8>,
    mime_type: String,
    from_device_id: String,
    snapshot_hash: String,
}

struct SpaceFileEventData {
    data: Vec<u8>,
    file_name: String,
    from_device_id: String,
    snapshot_hash: String,
    local_path: String,
    file_size: u64,
}

struct SpaceFileStatusEventData {
    transfer_id: String,
    status: String,
    reason: String,
}

enum MaterializedFileSignal {
    Pending {
        entry_id: String,
        from_device: String,
    },
    Ready {
        entry_id: String,
    },
    TransferStatus {
        transfer_id: String,
        status: String,
        reason: String,
    },
}

struct HarmonyHostEventEmitter {
    sender: tokio::sync::mpsc::UnboundedSender<MaterializedFileSignal>,
}

impl HostEventEmitterPort for HarmonyHostEventEmitter {
    fn emit(&self, event: HostEvent) -> std::result::Result<(), EmitError> {
        let signal = match event {
            HostEvent::Clipboard(ClipboardHostEvent::IncomingPending {
                entry_id,
                from_device,
                filenames: _,
                total_bytes: _,
            }) => Some(MaterializedFileSignal::Pending {
                entry_id,
                from_device,
            }),
            HostEvent::Clipboard(ClipboardHostEvent::NewContent {
                entry_id,
                origin: ClipboardOriginKind::Remote,
                preview: _,
            }) => Some(MaterializedFileSignal::Ready { entry_id }),
            HostEvent::Transfer(TransferHostEvent::StatusChanged {
                transfer_id,
                entry_id: _,
                status,
                reason,
            }) => Some(MaterializedFileSignal::TransferStatus {
                transfer_id,
                status,
                reason: reason.unwrap_or_default(),
            }),
            _ => None,
        };
        if let Some(signal) = signal {
            self.sender
                .send(signal)
                .map_err(|_| EmitError::Failed("HarmonyOS file event channel closed".to_string()))?;
        }
        Ok(())
    }
}

struct SpaceFileAssembly {
    file_name: String,
    total_size: usize,
    chunks: Vec<Option<Vec<u8>>>,
    received_chunks: usize,
    updated_at_ms: u64,
}

impl PlatformBridge for HarmonyPlatformBridge {
    fn app_group_dir(&self) -> String {
        String::new()
    }
}

impl SseListener for HarmonySseListener {
    fn on_hello(&self, server_time_ms: i64) {
        self.enqueue("hello", server_time_ms.to_string());
    }

    fn on_update(&self, content_id: String) {
        self.enqueue("update", content_id);
    }

    fn on_resync(&self) {
        self.enqueue("resync", String::new());
    }

    fn on_disconnected(&self, reason: String) {
        self.enqueue("disconnected", reason);
    }
}

impl HarmonySseListener {
    fn enqueue(&self, event_type: &str, detail: String) {
        if SSE_GENERATION.load(Ordering::Acquire) != self.generation {
            return;
        }
        let mut events = match sse_events().lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
        if events.len() >= MAX_PENDING_SSE_EVENTS {
            events.pop_front();
        }
        events.push_back(SseEventData {
            event_type: event_type.to_string(),
            detail,
        });
    }
}

#[napi(object)]
pub struct ConnectPayload {
    pub url: String,
    pub urls: Vec<String>,
    pub user: String,
    pub pwd: String,
}

#[napi(object)]
pub struct NativeServerConfig {
    pub base_url: String,
    pub username: String,
    pub password: String,
}

#[napi(object)]
pub struct LatestText {
    pub text: String,
    pub content_id: String,
}

#[napi(object)]
pub struct NativeClipboardContent {
    pub kind: String,
    pub text: String,
    pub content_id: String,
    pub data_name: String,
    pub data: Uint8Array,
}

#[napi(object)]
pub struct NativeHistoryItem {
    pub id: String,
    pub text: String,
    pub kind: String,
    pub timestamp_ms: f64,
    pub starred: bool,
    pub pinned: bool,
    pub has_data: bool,
    pub version: f64,
}

#[napi(object)]
pub struct NativeSseEvent {
    pub event_type: String,
    pub detail: String,
}

#[napi(object)]
pub struct NativeSpaceStatus {
    pub running: bool,
    pub joined: bool,
    pub device_name: String,
    pub space_id: String,
}

#[napi(object)]
pub struct NativeJoinSpaceResult {
    pub space_id: String,
    pub sponsor_device_id: String,
    pub self_device_id: String,
}

#[napi(object)]
pub struct NativeCreateSpaceResult {
    pub space_id: String,
    pub self_device_id: String,
}

#[napi(object)]
pub struct NativeSpaceInvitation {
    pub code: String,
    pub expires_at_ms: f64,
}

#[napi(object)]
pub struct NativeSpaceTextEvent {
    pub text: String,
    pub from_device_id: String,
    pub snapshot_hash: String,
}

#[napi(object)]
pub struct NativeSpaceImageEvent {
    pub data: Uint8Array,
    pub mime_type: String,
    pub from_device_id: String,
    pub snapshot_hash: String,
}

#[napi(object)]
pub struct NativeSpaceFileEvent {
    pub data: Uint8Array,
    pub file_name: String,
    pub from_device_id: String,
    pub snapshot_hash: String,
    pub local_path: String,
    pub file_size: f64,
}

#[napi(object)]
pub struct NativeSpaceFileStatusEvent {
    pub transfer_id: String,
    pub status: String,
    pub reason: String,
}

#[napi(object)]
pub struct NativeSpaceFileSendResult {
    pub accepted_count: u32,
    pub transfer_id: String,
}

#[napi(object)]
pub struct NativeSpaceDevice {
    pub device_id: String,
    pub device_name: String,
    pub device_type: String,
    pub is_local: bool,
    pub online: bool,
    pub state: String,
    pub channel: String,
}

#[napi(object)]
pub struct NativeSpaceMemberSyncPreferences {
    pub send_enabled: bool,
    pub text: bool,
    pub image: bool,
    pub file: bool,
    pub link: bool,
    pub rich_text: bool,
}

impl From<MemberSyncPreferencesView> for NativeSpaceMemberSyncPreferences {
    fn from(value: MemberSyncPreferencesView) -> Self {
        Self {
            send_enabled: value.send_enabled,
            text: value.send_content_types.text,
            image: value.send_content_types.image,
            file: value.send_content_types.file,
            link: value.send_content_types.link,
            rich_text: value.send_content_types.rich_text,
        }
    }
}

#[napi(object)]
pub struct NativeMobileSyncStatus {
    pub enabled: bool,
    pub lan_listen_enabled: bool,
    pub running: bool,
    pub port: u32,
    pub urls: Vec<String>,
}

#[napi(object)]
pub struct NativeMobileSyncDevice {
    pub device_id: String,
    pub label: String,
    pub username: String,
    pub online: bool,
    pub created_at_ms: f64,
    pub last_seen_at_ms: f64,
    pub last_seen_ip: String,
}

#[napi(object)]
pub struct NativeMobileSyncCredential {
    pub device_id: String,
    pub label: String,
    pub username: String,
    pub password: String,
    pub connect_uri: String,
    pub urls: Vec<String>,
}

#[napi(object)]
pub struct NativeMobileSyncInboundEvent {
    pub kind: String,
    pub text: String,
    pub data_name: String,
    pub mime_type: String,
    pub data: Uint8Array,
    pub content_id: String,
    pub source_label: String,
}

impl From<NativeServerConfig> for MobileServerConfig {
    fn from(config: NativeServerConfig) -> Self {
        Self {
            base_url: config.base_url,
            username: config.username,
            password: config.password,
        }
    }
}

fn sync_error(error: uc_mobile::SyncError) -> Error {
    Error::new(Status::GenericFailure, error.to_string())
}

fn mobile_client() -> Result<Arc<MobileSyncClient>> {
    if let Some(client) = MOBILE_CLIENT.get() {
        return Ok(client.clone());
    }

    uc_mobile::uc_mobile_init();
    let created = MobileSyncClient::new(Arc::new(HarmonyPlatformBridge), false)
        .map_err(sync_error)?;
    if MOBILE_CLIENT.set(created.clone()).is_ok() {
        return Ok(created);
    }

    MOBILE_CLIENT
        .get()
        .cloned()
        .ok_or_else(|| Error::new(Status::GenericFailure, "initialize mobile client failed"))
}

fn sse_handle() -> &'static Mutex<Option<Arc<SseHandle>>> {
    SSE_HANDLE.get_or_init(|| Mutex::new(None))
}

fn sse_events() -> &'static Mutex<VecDeque<SseEventData>> {
    SSE_EVENTS.get_or_init(|| Mutex::new(VecDeque::new()))
}

fn space_runtime() -> &'static tokio::sync::Mutex<Option<CliAppRuntime>> {
    SPACE_RUNTIME.get_or_init(|| tokio::sync::Mutex::new(None))
}

fn space_inbound_task() -> &'static Mutex<Option<tokio::task::JoinHandle<()>>> {
    SPACE_INBOUND_TASK.get_or_init(|| Mutex::new(None))
}

fn space_keepalive_task() -> &'static Mutex<Option<tokio::task::JoinHandle<()>>> {
    SPACE_KEEPALIVE_TASK.get_or_init(|| Mutex::new(None))
}

fn space_materialized_file_task() -> &'static Mutex<Option<tokio::task::JoinHandle<()>>> {
    SPACE_MATERIALIZED_FILE_TASK.get_or_init(|| Mutex::new(None))
}

fn space_keepalive_wake() -> &'static Arc<tokio::sync::Notify> {
    SPACE_KEEPALIVE_WAKE.get_or_init(|| Arc::new(tokio::sync::Notify::new()))
}

fn space_text_events() -> &'static Mutex<VecDeque<SpaceTextEventData>> {
    SPACE_TEXT_EVENTS.get_or_init(|| Mutex::new(VecDeque::new()))
}

fn space_image_events() -> &'static Mutex<VecDeque<SpaceImageEventData>> {
    SPACE_IMAGE_EVENTS.get_or_init(|| Mutex::new(VecDeque::new()))
}

fn space_file_events() -> &'static Mutex<VecDeque<SpaceFileEventData>> {
    SPACE_FILE_EVENTS.get_or_init(|| Mutex::new(VecDeque::new()))
}

fn space_file_status_events() -> &'static Mutex<VecDeque<SpaceFileStatusEventData>> {
    SPACE_FILE_STATUS_EVENTS.get_or_init(|| Mutex::new(VecDeque::new()))
}

fn space_file_assemblies() -> &'static Mutex<HashMap<String, SpaceFileAssembly>> {
    SPACE_FILE_ASSEMBLIES.get_or_init(|| Mutex::new(HashMap::new()))
}

fn space_device_types() -> &'static Mutex<HashMap<String, String>> {
    SPACE_DEVICE_TYPES.get_or_init(|| Mutex::new(HashMap::new()))
}

fn clear_space_transient_state() {
    if let Ok(mut queue) = space_text_events().lock() {
        queue.clear();
    }
    if let Ok(mut queue) = space_image_events().lock() {
        queue.clear();
    }
    if let Ok(mut queue) = space_file_events().lock() {
        queue.clear();
    }
    if let Ok(mut queue) = space_file_status_events().lock() {
        queue.clear();
    }
    if let Ok(mut assemblies) = space_file_assemblies().lock() {
        assemblies.clear();
    }
    if let Ok(mut device_types) = space_device_types().lock() {
        device_types.clear();
    }
    SPACE_PROFILE_ANNOUNCED.store(false, Ordering::Release);
}

fn space_local_device_type() -> &'static Mutex<String> {
    SPACE_LOCAL_DEVICE_TYPE.get_or_init(|| Mutex::new("unknown".to_string()))
}

fn normalize_device_type(device_type: &str) -> String {
    match device_type.trim().to_ascii_lowercase().as_str() {
        "phone" => "phone",
        "tablet" => "tablet",
        "2in1" => "2in1",
        "tv" => "tv",
        "wearable" => "wearable",
        "car" => "car",
        _ => "unknown",
    }
    .to_string()
}

fn set_known_device_type(device_id: String, device_type: String) -> bool {
    let normalized = normalize_device_type(&device_type);
    let mut types = match space_device_types().lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };
    let changed = types
        .get(&device_id)
        .map(|existing| existing != &normalized)
        .unwrap_or(true);
    types.insert(device_id, normalized);
    changed
}

fn known_device_type(device_id: &str) -> String {
    let types = match space_device_types().lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };
    types
        .get(device_id)
        .cloned()
        .unwrap_or_else(|| "unknown".to_string())
}

fn current_local_device_type() -> String {
    let device_type = match space_local_device_type().lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };
    device_type.clone()
}

fn reachability_name(state: ReachabilityState) -> String {
    match state {
        ReachabilityState::Online => "online",
        ReachabilityState::Offline => "offline",
        ReachabilityState::Unknown => "unknown",
    }
    .to_string()
}

fn replace_space_inbound_task(task: tokio::task::JoinHandle<()>) {
    let previous = {
        let mut guard = match space_inbound_task().lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
        guard.replace(task)
    };
    if let Some(previous) = previous {
        previous.abort();
    }
}

fn abort_space_inbound_task() {
    let task = {
        let mut guard = match space_inbound_task().lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
        guard.take()
    };
    if let Some(task) = task {
        task.abort();
    }
}

fn replace_space_keepalive_task(task: tokio::task::JoinHandle<()>) {
    let previous = {
        let mut guard = match space_keepalive_task().lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
        guard.replace(task)
    };
    if let Some(previous) = previous {
        previous.abort();
    }
}

fn abort_space_keepalive_task() {
    let task = {
        let mut guard = match space_keepalive_task().lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
        guard.take()
    };
    if let Some(task) = task {
        task.abort();
    }
}

fn replace_space_materialized_file_task(task: tokio::task::JoinHandle<()>) {
    let previous = {
        let mut guard = match space_materialized_file_task().lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
        guard.replace(task)
    };
    if let Some(previous) = previous {
        previous.abort();
    }
}

fn abort_space_materialized_file_task() {
    let task = {
        let mut guard = match space_materialized_file_task().lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
        guard.take()
    };
    if let Some(task) = task {
        task.abort();
    }
}

fn enqueue_space_text_event(event: SpaceTextEventData) {
    let mut events = match space_text_events().lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };
    if events.len() >= MAX_PENDING_SPACE_EVENTS {
        events.pop_front();
    }
    events.push_back(event);
}

fn enqueue_space_image_event(event: SpaceImageEventData) {
    let mut events = match space_image_events().lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };
    if events.len() >= MAX_PENDING_SPACE_EVENTS {
        events.pop_front();
    }
    events.push_back(event);
}

fn enqueue_space_file_event(event: SpaceFileEventData) {
    let mut events = match space_file_events().lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };
    if events.len() >= MAX_PENDING_SPACE_EVENTS {
        events.pop_front();
    }
    events.push_back(event);
}

fn enqueue_space_file_status_event(event: SpaceFileStatusEventData) {
    let mut events = match space_file_status_events().lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };
    if events.len() >= MAX_PENDING_SPACE_EVENTS {
        events.pop_front();
    }
    events.push_back(event);
}

fn sanitize_space_file_name(file_name: &str) -> String {
    let sanitized: String = file_name
        .chars()
        .filter(|character| !matches!(character, '/' | '\\' | '\0'))
        .collect();
    let trimmed = sanitized.trim();
    if trimmed.is_empty() {
        "shared-file".to_string()
    } else {
        trimmed.to_string()
    }
}

fn space_error(error: impl std::fmt::Display) -> Error {
    Error::new(Status::GenericFailure, error.to_string())
}

async fn current_space_status() -> Result<NativeSpaceStatus> {
    let app_facade = {
        let guard = space_runtime().lock().await;
        guard.as_ref().map(|runtime| runtime.app_facade.clone())
    };
    let Some(app_facade) = app_facade else {
        return Ok(NativeSpaceStatus {
            running: false,
            joined: false,
            device_name: String::new(),
            space_id: String::new(),
        });
    };
    let setup = app_facade.space_setup.get().cloned().ok_or_else(|| {
        Error::new(Status::GenericFailure, "space setup service is unavailable")
    })?;
    let state = setup.query_setup_state().await.map_err(space_error)?;
    Ok(NativeSpaceStatus {
        running: true,
        joined: state.has_completed,
        device_name: state.device_name.unwrap_or_default(),
        space_id: state
            .space_id
            .map(|space_id| space_id.to_string())
            .unwrap_or_default(),
    })
}

fn cancel_sse_subscription() {
    SSE_GENERATION.fetch_add(1, Ordering::AcqRel);
    let old_handle = {
        let mut current = match sse_handle().lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
        current.take()
    };
    if let Some(handle) = old_handle {
        handle.cancel();
    }
}

fn history_kind(kind: ClipboardKind) -> String {
    match kind {
        ClipboardKind::Text => "Text",
        ClipboardKind::Image => "Image",
        ClipboardKind::File => "File",
        ClipboardKind::Group => "Group",
    }
    .to_string()
}

fn parse_history_kind(kind: &str) -> Result<ClipboardKind> {
    match kind {
        "Text" => Ok(ClipboardKind::Text),
        "Image" => Ok(ClipboardKind::Image),
        "File" => Ok(ClipboardKind::File),
        "Group" | "Folder" => Ok(ClipboardKind::Group),
        _ => Err(Error::new(
            Status::InvalidArg,
            format!("unsupported clipboard history kind: {kind}"),
        )),
    }
}

fn native_history_item(record: HistoryRecord) -> NativeHistoryItem {
    let timestamp_ms = record
        .last_modified_ms
        .or(record.create_time_ms)
        .unwrap_or_default() as f64;
    NativeHistoryItem {
        id: record.hash,
        text: record.text.unwrap_or_default(),
        kind: history_kind(record.kind),
        timestamp_ms,
        starred: record.starred,
        pinned: record.pinned,
        has_data: record.has_data,
        version: record.version.unwrap_or_default() as f64,
    }
}

#[napi]
pub fn parse_connect_uri(uri: String) -> Result<ConnectPayload> {
    let payload = uc_mobile_proto::parse_mobile_sync_connect_uri(&uri).map_err(|error| {
        Error::new(Status::InvalidArg, error.to_string())
    })?;

    Ok(ConnectPayload {
        url: payload.url,
        urls: payload.urls,
        user: payload.user,
        pwd: payload.pwd,
    })
}

#[napi]
pub fn sha256_hex_upper(text: String) -> String {
    uc_mobile_proto::sha256_hex_upper(text.as_bytes())
}

/// Start the embedded UniClipboard P2P node inside the HarmonyOS application
/// sandbox. This must be called once before redeeming a space invitation.
#[napi]
pub async fn start_space_node(
    data_dir: String,
    cache_dir: String,
    device_type: String,
) -> Result<NativeSpaceStatus> {
    if data_dir.trim().is_empty() || cache_dir.trim().is_empty() {
        return Err(Error::new(
            Status::InvalidArg,
            "HarmonyOS data and cache directories are required",
        ));
    }

    {
        let guard = space_runtime().lock().await;
        if guard.is_some() {
            drop(guard);
            return current_space_status().await;
        }
    }

    std::fs::create_dir_all(&data_dir).map_err(space_error)?;
    std::fs::create_dir_all(&cache_dir).map_err(space_error)?;
    std::env::set_var("UC_OHOS_DATA_DIR", &data_dir);
    std::env::set_var("UC_OHOS_CACHE_DIR", &cache_dir);
    std::env::set_var("UC_DISABLE_SYSTEM_CLIPBOARD", "1");
    {
        let mut local_type = match space_local_device_type().lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
        *local_type = normalize_device_type(&device_type);
    }
    SPACE_PROFILE_ANNOUNCED.store(false, Ordering::Release);

    let runtime = uc_bootstrap::build_cli_app_runtime(None)
        .await
        .map_err(space_error)?;
    let session_resumed = runtime
        .app_facade
        .try_resume_session()
        .await
        .map_err(space_error)?;
    let keepalive_facade = runtime.app_facade.clone();
    let keepalive_wake = Arc::clone(space_keepalive_wake());
    let keepalive_task = tokio::spawn(async move {
        // Mobile hosts do not run the desktop daemon's peer scheduler. Keep
        // dialing from the native node itself so connection recovery does not
        // depend on which ArkUI page is visible or which device opened first.
        let mut last_background_verify: Option<Instant> = None;
        loop {
            let background_active = SPACE_BACKGROUND_SYNC_ACTIVE.load(Ordering::Acquire);
            let periodic_force_verify = if background_active {
                match last_background_verify {
                    Some(last_verify) => {
                        last_verify.elapsed() >= SPACE_BACKGROUND_VERIFY_INTERVAL
                    }
                    None => true,
                }
            } else {
                last_background_verify = None;
                false
            };
            if let Ok(peers) = keepalive_facade.list_paired_peer_device_ids().await {
                let requested_force_verify =
                    SPACE_KEEPALIVE_FORCE_VERIFY.swap(false, Ordering::AcqRel);
                let force_verify = requested_force_verify || periodic_force_verify;
                if force_verify {
                    last_background_verify = Some(Instant::now());
                }
                let mut set = tokio::task::JoinSet::new();
                for peer in peers {
                    let facade = keepalive_facade.clone();
                    set.spawn(async move {
                        let result = if force_verify {
                            facade.verify_reachable_one(&peer).await
                        } else {
                            facade.ensure_reachable_one(&peer).await
                        };
                        if let Err(error) = result {
                            eprintln!("UniClipboard peer recovery failed: {error}");
                        }
                    });
                }
                while set.join_next().await.is_some() {}
            }
            tokio::select! {
                _ = tokio::time::sleep(std::time::Duration::from_secs(5)) => {},
                _ = keepalive_wake.notified() => {},
            }
        }
    });
    replace_space_keepalive_task(keepalive_task);
    if session_resumed {
        space_keepalive_wake().notify_one();
    }
    let mut inbound_notices = runtime
        .app_facade
        .subscribe_inbound_clipboard_notices()
        .map_err(space_error)?;
    let inbound_facade = runtime.app_facade.clone();
    let inbound_file_root = std::path::PathBuf::from(&cache_dir).join("uniclipboard-received");
    let inbound_task = tokio::spawn(async move {
        loop {
            let notice = match inbound_notices.recv().await {
                Ok(notice) => notice,
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
            };
            if notice.action != InboundAction::NewEntry {
                continue;
            }
            let (snapshot, blob_refs) = match
                decode_v3_bytes_to_snapshot_and_blob_refs(notice.plaintext.as_ref())
            {
                Ok(decoded) => decoded,
                Err(_) => continue,
            };
            if !blob_refs.is_empty() {
                for blob_ref in blob_refs {
                    if blob_ref.representation_index.is_some() {
                        continue;
                    }
                    let file_name = sanitize_space_file_name(
                        blob_ref.filename.as_deref().unwrap_or("shared-file"),
                    );
                    let receiver_entry_id = EntryId::new();
                    let target_dir = inbound_file_root.join(receiver_entry_id.as_str());
                    if tokio::fs::create_dir_all(&target_dir).await.is_err() {
                        continue;
                    }
                    let target_path = target_dir.join(&file_name);
                    let sender_entry_id = blob_ref.entry_id.clone();
                    let transfer_context = FetchTransferContext {
                        transfer_id: receiver_entry_id.as_str().to_string(),
                        entry_id: receiver_entry_id.as_str().to_string(),
                        peer_id: notice.from_device.as_str().to_string(),
                        total_bytes: Some(blob_ref.size_bytes),
                        filename: file_name.clone(),
                        outbound_transfer_id: Some(sender_entry_id.as_str().to_string()),
                        outbound_target: Some(notice.from_device.clone()),
                        batch_position: BatchPosition::Only,
                        individual_lifecycle: false,
                    };
                    let fetched = inbound_facade
                        .fetch_blob_to_path(FetchBlobToPathCommand {
                            ticket: blob_ref.ticket,
                            entry_id: sender_entry_id,
                            target_path: target_path.clone(),
                            transfer_context: Some(transfer_context),
                        })
                        .await;
                    let Ok(result) = fetched else {
                        continue;
                    };
                    enqueue_space_file_event(SpaceFileEventData {
                        data: Vec::new(),
                        file_name,
                        from_device_id: notice.from_device.as_str().to_string(),
                        snapshot_hash: notice.snapshot_hash.clone(),
                        local_path: target_path.to_string_lossy().into_owned(),
                        file_size: result.bytes_written,
                    });
                }
                continue;
            }
            for representation in snapshot.representations {
                let is_device_profile = representation
                    .mime
                    .as_ref()
                    .map(|mime| mime.as_str() == SPACE_DEVICE_PROFILE_MIME)
                    .unwrap_or(false);
                if is_device_profile {
                    if let Some(bytes) = representation.inline_bytes() {
                        if let Ok(device_type) = String::from_utf8(bytes.to_vec()) {
                            if set_known_device_type(notice.from_device.to_string(), device_type) {
                                // First profile from a peer doubles as a request for our own
                                // profile. Reset once so an upgraded legacy peer learns this
                                // device without requiring either side to re-pair or restart.
                                SPACE_PROFILE_ANNOUNCED.store(false, Ordering::Release);
                            }
                        }
                    }
                    break;
                }
                let is_space_file = representation
                    .mime
                    .as_ref()
                    .map(|mime| mime.as_str() == SPACE_FILE_MIME)
                    .unwrap_or(false);
                if is_space_file {
                    let Some(bytes) = representation.inline_bytes() else {
                        continue;
                    };
                    if bytes.len() < SPACE_FILE_HEADER_BYTES || bytes[0] != 1 {
                        continue;
                    }
                    let transfer_id = u64::from_le_bytes(bytes[1..9].try_into().unwrap());
                    let chunk_index = u32::from_le_bytes(bytes[9..13].try_into().unwrap()) as usize;
                    let chunk_count = u32::from_le_bytes(bytes[13..17].try_into().unwrap()) as usize;
                    let total_size = u64::from_le_bytes(bytes[17..25].try_into().unwrap()) as usize;
                    let name_len = u16::from_le_bytes(bytes[25..27].try_into().unwrap()) as usize;
                    let expected_chunk_count = total_size.div_ceil(SPACE_FILE_CHUNK_BYTES);
                    if name_len == 0
                        || total_size == 0
                        || chunk_count == 0
                        || chunk_count > 128
                        || chunk_count != expected_chunk_count
                        || chunk_index >= chunk_count
                        || total_size > MAX_SPACE_FILE_BYTES
                        || bytes.len() < SPACE_FILE_HEADER_BYTES + name_len
                    {
                        continue;
                    }
                    let Ok(file_name) = String::from_utf8(
                        bytes[SPACE_FILE_HEADER_BYTES..SPACE_FILE_HEADER_BYTES + name_len].to_vec(),
                    ) else {
                        continue;
                    };
                    let chunk = bytes[SPACE_FILE_HEADER_BYTES + name_len..].to_vec();
                    let chunk_start = chunk_index * SPACE_FILE_CHUNK_BYTES;
                    let expected_chunk_len = SPACE_FILE_CHUNK_BYTES.min(total_size - chunk_start);
                    if chunk.len() != expected_chunk_len {
                        continue;
                    }
                    let from_device_id = notice.from_device.to_string();
                    let assembly_key = format!("{from_device_id}:{transfer_id}");
                    let now_ms = std::time::SystemTime::now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .map(|duration| duration.as_millis().min(u64::MAX as u128) as u64)
                        .unwrap_or(0);
                    let completed = {
                        let mut assemblies = match space_file_assemblies().lock() {
                            Ok(guard) => guard,
                            Err(poisoned) => poisoned.into_inner(),
                        };
                        assemblies.retain(|_, assembly| {
                            now_ms.saturating_sub(assembly.updated_at_ms) < 5 * 60 * 1000
                        });
                        let assembly = assemblies.entry(assembly_key.clone()).or_insert_with(|| {
                            SpaceFileAssembly {
                                file_name: file_name.clone(),
                                total_size,
                                chunks: vec![None; chunk_count],
                                received_chunks: 0,
                                updated_at_ms: now_ms,
                            }
                        });
                        if assembly.total_size != total_size
                            || assembly.chunks.len() != chunk_count
                            || assembly.file_name != file_name
                        {
                            assemblies.remove(&assembly_key);
                            None
                        } else {
                            assembly.updated_at_ms = now_ms;
                            if assembly.chunks[chunk_index].is_none() {
                                assembly.chunks[chunk_index] = Some(chunk);
                                assembly.received_chunks += 1;
                            }
                            if assembly.received_chunks == chunk_count {
                                assemblies.remove(&assembly_key)
                            } else {
                                None
                            }
                        }
                    };
                    if let Some(mut assembly) = completed {
                        let mut data = Vec::with_capacity(assembly.total_size);
                        for stored_chunk in &mut assembly.chunks {
                            if let Some(part) = stored_chunk.take() {
                                data.extend_from_slice(&part);
                            }
                        }
                        if data.len() == assembly.total_size {
                            enqueue_space_file_event(SpaceFileEventData {
                                data,
                                file_name: assembly.file_name,
                                from_device_id,
                                snapshot_hash: notice.snapshot_hash.clone(),
                                local_path: String::new(),
                                file_size: assembly.total_size as u64,
                            });
                        }
                    }
                    break;
                }
                let image_mime = representation
                    .mime
                    .as_ref()
                    .map(|mime| mime.as_str().to_string())
                    .filter(|mime| mime.starts_with("image/"));
                if let Some(mime_type) = image_mime {
                    let Some(bytes) = representation.inline_bytes() else {
                        continue;
                    };
                    enqueue_space_image_event(SpaceImageEventData {
                        data: bytes.to_vec(),
                        mime_type,
                        from_device_id: notice.from_device.to_string(),
                        snapshot_hash: notice.snapshot_hash.clone(),
                    });
                    break;
                }
                let is_plain_text = representation
                    .mime
                    .as_ref()
                    .map(|mime| mime.as_str().starts_with("text/plain"))
                    .unwrap_or(false);
                if !is_plain_text {
                    continue;
                }
                let Some(bytes) = representation.inline_bytes() else {
                    continue;
                };
                let Ok(text) = String::from_utf8(bytes.to_vec()) else {
                    continue;
                };
                enqueue_space_text_event(SpaceTextEventData {
                    text,
                    from_device_id: notice.from_device.to_string(),
                    snapshot_hash: notice.snapshot_hash.clone(),
                });
                break;
            }
        }
    });
    replace_space_inbound_task(inbound_task);
    let (materialized_sender, mut materialized_receiver) = tokio::sync::mpsc::unbounded_channel();
    runtime.host_event_bus.register(
        "harmony_materialized_files",
        Arc::new(HarmonyHostEventEmitter {
            sender: materialized_sender,
        }),
    );
    let materialized_facade = runtime.app_facade.clone();
    let materialized_task = tokio::spawn(async move {
        let mut source_devices: HashMap<String, String> = HashMap::new();
        while let Some(signal) = materialized_receiver.recv().await {
            match signal {
                MaterializedFileSignal::Pending {
                    entry_id,
                    from_device,
                } => {
                    source_devices.insert(entry_id, from_device);
                }
                MaterializedFileSignal::Ready { entry_id } => {
                    let location = match materialized_facade
                        .resource
                        .entry_file_location(&entry_id)
                        .await
                    {
                        Ok(location) => location,
                        Err(_) => continue,
                    };
                    let from_device_id = source_devices.remove(&entry_id).unwrap_or_default();
                    enqueue_space_file_event(SpaceFileEventData {
                        data: Vec::new(),
                        file_name: location.filename,
                        from_device_id,
                        snapshot_hash: entry_id,
                        local_path: location.path.to_string_lossy().into_owned(),
                        file_size: location.size_bytes,
                    });
                }
                MaterializedFileSignal::TransferStatus {
                    transfer_id,
                    status,
                    reason,
                } => {
                    enqueue_space_file_status_event(SpaceFileStatusEventData {
                        transfer_id,
                        status,
                        reason,
                    });
                }
            }
        }
    });
    replace_space_materialized_file_task(materialized_task);
    let mut guard = space_runtime().lock().await;
    if guard.is_none() {
        *guard = Some(runtime);
    }
    drop(guard);
    current_space_status().await
}

#[napi]
pub async fn get_space_status() -> Result<NativeSpaceStatus> {
    current_space_status().await
}

/// Wake the native peer scheduler and force-revalidate cached connections.
/// HarmonyOS calls this after returning to the foreground so a connection
/// invalidated by lock-screen network suspension is redialed immediately
/// instead of waiting for the 30-second fast-path TTL or QUIC idle timeout.
#[napi]
pub fn wake_space_connections() {
    SPACE_KEEPALIVE_FORCE_VERIFY.store(true, Ordering::Release);
    space_keepalive_wake().notify_one();
}

/// Enable or disable the stricter background connection monitor. While a
/// HarmonyOS long-running task is active, cached peer connections are
/// revalidated every 15 seconds so lock-screen network suspension cannot
/// leave the application silently attached to a dead QUIC connection.
#[napi]
pub fn set_space_background_mode(active: bool) {
    SPACE_BACKGROUND_SYNC_ACTIVE.store(active, Ordering::Release);
    if active {
        SPACE_KEEPALIVE_FORCE_VERIFY.store(true, Ordering::Release);
        space_keepalive_wake().notify_one();
    }
}

/// Actively dial one paired space device instead of waiting for the periodic
/// keepalive pass. Returns true only when the core reports the peer online.
#[napi]
pub async fn connect_space_device(device_id: String) -> Result<bool> {
    let trimmed = device_id.trim();
    let device = DeviceId::try_new(trimmed)
        .ok_or_else(|| Error::new(Status::InvalidArg, "invalid space device id"))?;
    let app_facade = {
        let guard = space_runtime().lock().await;
        guard
            .as_ref()
            .map(|runtime| runtime.app_facade.clone())
            .ok_or_else(|| Error::new(Status::GenericFailure, "space node has not been started"))?
    };
    let state = app_facade
        .ensure_reachable_one(&device)
        .await
        .map_err(space_error)?;
    Ok(matches!(state, ReachabilityState::Online))
}

/// Return the persisted member roster enriched with live reachability and the
/// HarmonyOS device type announced by each peer through the encrypted space.
#[napi]
pub async fn get_space_devices() -> Result<Vec<NativeSpaceDevice>> {
    let app_facade = {
        let guard = space_runtime().lock().await;
        guard
            .as_ref()
            .map(|runtime| runtime.app_facade.clone())
            .ok_or_else(|| Error::new(Status::GenericFailure, "space node has not been started"))?
    };
    let local = app_facade.device.local_device_info().await.map_err(space_error)?;
    let local_type = current_local_device_type();
    let _ = set_known_device_type(local.peer_id.clone(), local_type.clone());
    let entries = app_facade.list_roster_entries().await.map_err(space_error)?;
    let peer_snapshots = app_facade.list_peer_snapshots().await.map_err(space_error)?;
    let mut devices = Vec::with_capacity(entries.len() + 1);
    let mut has_local = false;
    let mut has_online_peer = false;
    for entry in entries {
        if entry.is_local {
            has_local = true;
        } else if entry.state == ReachabilityState::Online {
            has_online_peer = true;
        }
        let channel = if entry.is_local {
            "direct".to_string()
        } else {
            peer_snapshots
                .iter()
                .find(|snapshot| snapshot.peer_id == entry.device_id.as_str())
                .map(|snapshot| connection_channel_to_wire(snapshot.channel).to_string())
                .unwrap_or_else(|| "unknown".to_string())
        };
        devices.push(NativeSpaceDevice {
            device_id: entry.device_id.to_string(),
            device_name: entry.device_name,
            device_type: known_device_type(entry.device_id.as_str()),
            is_local: entry.is_local,
            online: entry.is_local || entry.state == ReachabilityState::Online,
            state: if entry.is_local {
                "online".to_string()
            } else {
                reachability_name(entry.state)
            },
            channel,
        });
    }
    if !has_local {
        devices.insert(
            0,
            NativeSpaceDevice {
                device_id: local.peer_id,
                device_name: local.device_name,
                device_type: local_type.clone(),
                is_local: true,
                online: true,
                state: "online".to_string(),
                channel: "direct".to_string(),
            },
        );
    }
    if has_online_peer && !SPACE_PROFILE_ANNOUNCED.load(Ordering::Acquire) {
        let now_ms = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_err(space_error)?
            .as_millis()
            .min(i64::MAX as u128) as i64;
        let snapshot = SystemClipboardSnapshot {
            ts_ms: now_ms,
            representations: vec![ObservedClipboardRepresentation::new(
                RepresentationId::new(),
                FormatId::from("uniclipboard-device-profile"),
                Some(MimeType(SPACE_DEVICE_PROFILE_MIME.to_string())),
                local_type.into_bytes(),
            )],
            file_content_digests: Vec::new(),
            file_set_v1_component: None,
        };
        let outcome = app_facade
            .dispatch_clipboard_snapshot(snapshot, ClipboardChangeOrigin::LocalCapture, None)
            .await
            .map_err(space_error)?;
        if outcome.total_accepted > 0 {
            SPACE_PROFILE_ANNOUNCED.store(true, Ordering::Release);
        }
    }
    Ok(devices)
}

/// Return the local device's outbound sync preferences for one paired member.
#[napi]
pub async fn get_space_member_sync_preferences(
    device_id: String,
) -> Result<NativeSpaceMemberSyncPreferences> {
    let trimmed = device_id.trim();
    if trimmed.is_empty() {
        return Err(Error::new(Status::InvalidArg, "space device id is required"));
    }
    let member_roster = {
        let guard = space_runtime().lock().await;
        let app_facade = guard
            .as_ref()
            .map(|runtime| runtime.app_facade.clone())
            .ok_or_else(|| Error::new(Status::GenericFailure, "space node has not been started"))?;
        app_facade
            .member_roster
            .get()
            .cloned()
            .ok_or_else(|| Error::new(Status::GenericFailure, "space roster is unavailable"))?
    };
    let preferences = member_roster
        .get_sync_preferences(trimmed)
        .await
        .map_err(space_error)?;
    Ok(preferences.into())
}

/// Update all outbound controls shown by the HarmonyOS device details page.
/// The unexposed code-snippet and all receive-side preferences are preserved.
#[napi]
pub async fn update_space_member_send_preferences(
    device_id: String,
    send_enabled: bool,
    text: bool,
    image: bool,
    file: bool,
    link: bool,
    rich_text: bool,
) -> Result<NativeSpaceMemberSyncPreferences> {
    let trimmed = device_id.trim();
    if trimmed.is_empty() {
        return Err(Error::new(Status::InvalidArg, "space device id is required"));
    }
    let member_roster = {
        let guard = space_runtime().lock().await;
        let app_facade = guard
            .as_ref()
            .map(|runtime| runtime.app_facade.clone())
            .ok_or_else(|| Error::new(Status::GenericFailure, "space node has not been started"))?;
        app_facade
            .member_roster
            .get()
            .cloned()
            .ok_or_else(|| Error::new(Status::GenericFailure, "space roster is unavailable"))?
    };
    let preferences = member_roster
        .update_sync_preferences(
            trimmed,
            MemberSyncPreferencesPatch {
                send_enabled: Some(send_enabled),
                receive_enabled: None,
                send_content_types: Some(ContentTypesPatch {
                    text: Some(text),
                    image: Some(image),
                    link: Some(link),
                    file: Some(file),
                    code_snippet: None,
                    rich_text: Some(rich_text),
                }),
                receive_content_types: None,
            },
        )
        .await
        .map_err(space_error)?;
    Ok(preferences.into())
}

/// Restore both outbound and inbound preferences for one member to defaults.
#[napi]
pub async fn reset_space_member_sync_preferences(
    device_id: String,
) -> Result<NativeSpaceMemberSyncPreferences> {
    let trimmed = device_id.trim();
    if trimmed.is_empty() {
        return Err(Error::new(Status::InvalidArg, "space device id is required"));
    }
    let member_roster = {
        let guard = space_runtime().lock().await;
        let app_facade = guard
            .as_ref()
            .map(|runtime| runtime.app_facade.clone())
            .ok_or_else(|| Error::new(Status::GenericFailure, "space node has not been started"))?;
        app_facade
            .member_roster
            .get()
            .cloned()
            .ok_or_else(|| Error::new(Status::GenericFailure, "space roster is unavailable"))?
    };
    let enabled_types = ContentTypesPatch {
        text: Some(true),
        image: Some(true),
        link: Some(true),
        file: Some(true),
        code_snippet: Some(true),
        rich_text: Some(true),
    };
    let preferences = member_roster
        .update_sync_preferences(
            trimmed,
            MemberSyncPreferencesPatch {
                send_enabled: Some(true),
                receive_enabled: Some(true),
                send_content_types: Some(enabled_types.clone()),
                receive_content_types: Some(enabled_types),
            },
        )
        .await
        .map_err(space_error)?;
    Ok(preferences.into())
}

/// Remove a paired device from the current space. The target device will be
/// evicted from the member roster, its peer address cache, and the trusted
/// peer table so it must re-pair to rejoin.
#[napi]
pub async fn revoke_space_member(device_id: String) -> Result<()> {
    let app_facade = {
        let guard = space_runtime().lock().await;
        guard
            .as_ref()
            .map(|runtime| runtime.app_facade.clone())
            .ok_or_else(|| Error::new(Status::GenericFailure, "space node has not been started"))?
    };
    app_facade
        .revoke_member(&device_id)
        .await
        .map_err(space_error)?;
    Ok(())
}

/// Initialize a new encrypted UniClipboard space on this device. Invitation
/// issuance is intentionally a separate action so the owner can retry or
/// refresh a code without attempting to initialize the space again.
#[napi]
pub async fn create_space(
    passphrase: String,
    device_name: String,
) -> Result<NativeCreateSpaceResult> {
    let name = device_name.trim().to_string();
    if passphrase.is_empty() || name.is_empty() {
        return Err(Error::new(
            Status::InvalidArg,
            "space passphrase and device name are required",
        ));
    }
    let app_facade = {
        let guard = space_runtime().lock().await;
        guard
            .as_ref()
            .map(|runtime| runtime.app_facade.clone())
            .ok_or_else(|| {
                Error::new(Status::GenericFailure, "space node has not been started")
            })?
    };
    let result = app_facade
        .initialize_space(InitializeSpaceInput {
            passphrase: passphrase.clone(),
            passphrase_confirm: passphrase,
            device_name: Some(name),
        })
        .await
        .map_err(space_error)?;
    Ok(NativeCreateSpaceResult {
        space_id: result.space_id.to_string(),
        self_device_id: result.self_device_id.to_string(),
    })
}

/// Issue a fresh, short-lived invitation for the space owned by this device.
#[napi]
pub async fn issue_space_invitation() -> Result<NativeSpaceInvitation> {
    let app_facade = {
        let guard = space_runtime().lock().await;
        guard
            .as_ref()
            .map(|runtime| runtime.app_facade.clone())
            .ok_or_else(|| {
                Error::new(Status::GenericFailure, "space node has not been started")
            })?
    };
    let result = app_facade
        .issue_pairing_invitation()
        .await
        .map_err(space_error)?;
    Ok(NativeSpaceInvitation {
        code: result.code.as_str().to_string(),
        expires_at_ms: result.expires_at.timestamp_millis() as f64,
    })
}

#[napi]
pub async fn join_space(
    invitation_code: String,
    passphrase: String,
    device_name: String,
) -> Result<NativeJoinSpaceResult> {
    let code = invitation_code.trim().to_ascii_uppercase();
    let name = device_name.trim().to_string();
    if code.is_empty() || passphrase.is_empty() || name.is_empty() {
        return Err(Error::new(
            Status::InvalidArg,
            "invitation code, space passphrase, and device name are required",
        ));
    }
    let app_facade = {
        let guard = space_runtime().lock().await;
        guard
            .as_ref()
            .map(|runtime| runtime.app_facade.clone())
            .ok_or_else(|| {
                Error::new(Status::GenericFailure, "space node has not been started")
            })?
    };
    app_facade
        .set_device_name(name)
        .await
        .map_err(space_error)?;
    let result = app_facade
        .redeem_pairing_invitation(RedeemPairingInvitationInput { code, passphrase })
        .await
        .map_err(space_error)?;
    Ok(NativeJoinSpaceResult {
        space_id: result.space_id.to_string(),
        sponsor_device_id: result.sponsor_device_id.to_string(),
        self_device_id: result.self_device_id.to_string(),
    })
}

/// Switch an already configured device to another encrypted space. Local
/// clipboard history is preserved by the application layer's crash-safe
/// re-encryption migration; the invitation must be issued by a member of the
/// target space.
#[napi]
pub async fn switch_space(
    invitation_code: String,
    new_passphrase: String,
) -> Result<NativeJoinSpaceResult> {
    let code = invitation_code.trim().to_ascii_uppercase();
    if code.is_empty() || new_passphrase.is_empty() {
        return Err(Error::new(
            Status::InvalidArg,
            "invitation code and target space passphrase are required",
        ));
    }
    let app_facade = {
        let guard = space_runtime().lock().await;
        guard
            .as_ref()
            .map(|runtime| runtime.app_facade.clone())
            .ok_or_else(|| {
                Error::new(Status::GenericFailure, "space node has not been started")
            })?
    };
    let result = app_facade
        .switch_space(SwitchSpaceInput {
            code,
            new_passphrase,
        })
        .await
        .map_err(space_error)?;

    // Do not surface already-buffered clipboard frames or remote device
    // profile announcements from the previous space after the selector moves
    // to the new active space.
    clear_space_transient_state();
    wake_space_connections();

    Ok(NativeJoinSpaceResult {
        space_id: result.space_id.to_string(),
        sponsor_device_id: result.sponsor_device_id.to_string(),
        self_device_id: result.self_device_id.to_string(),
    })
}

/// Replace the currently active space with a newly self-owned space without
/// uninstalling the application. Old peer membership/trust records are
/// removed before the new owner record is created.
#[napi]
pub async fn replace_space(
    passphrase: String,
    device_name: String,
) -> Result<NativeCreateSpaceResult> {
    let name = device_name.trim().to_string();
    if passphrase.len() < 8 || name.is_empty() {
        return Err(Error::new(
            Status::InvalidArg,
            "space passphrase must contain at least 8 characters and device name is required",
        ));
    }
    let app_facade = {
        let guard = space_runtime().lock().await;
        guard
            .as_ref()
            .map(|runtime| runtime.app_facade.clone())
            .ok_or_else(|| {
                Error::new(Status::GenericFailure, "space node has not been started")
            })?
    };

    // Snapshot peer ids before reset. The local owner row is retained and
    // overwritten by InitializeSpaceUseCase; every non-local row is revoked
    // through the roster facade so member/address/trust invariants stay intact.
    let roster = app_facade
        .list_roster_entries()
        .await
        .map_err(space_error)?;
    app_facade
        .factory_reset_space()
        .await
        .map_err(space_error)?;
    for entry in roster {
        if !entry.is_local {
            app_facade
                .revoke_member(entry.device_id.as_str())
                .await
                .map_err(space_error)?;
        }
    }

    let result = app_facade
        .initialize_space(InitializeSpaceInput {
            passphrase: passphrase.clone(),
            passphrase_confirm: passphrase,
            device_name: Some(name),
        })
        .await
        .map_err(space_error)?;
    clear_space_transient_state();
    wake_space_connections();

    Ok(NativeCreateSpaceResult {
        space_id: result.space_id.to_string(),
        self_device_id: result.self_device_id.to_string(),
    })
}

/// Dispatch UTF-8 text through the joined UniClipboard space. The return
/// value is the number of online peers that accepted the encrypted frame.
async fn send_space_text_with_filter(
    text: String,
    target_filter: Option<Vec<DeviceId>>,
) -> Result<u32> {
    if text.is_empty() {
        return Err(Error::new(Status::InvalidArg, "clipboard text is required"));
    }
    if text.len() > MAX_SPACE_TEXT_BYTES {
        return Err(Error::new(
            Status::InvalidArg,
            "clipboard text exceeds the 1 MiB inline limit",
        ));
    }
    let app_facade = {
        let guard = space_runtime().lock().await;
        guard
            .as_ref()
            .map(|runtime| runtime.app_facade.clone())
            .ok_or_else(|| Error::new(Status::GenericFailure, "space node has not been started"))?
    };
    let now_ms = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(space_error)?
        .as_millis()
        .min(i64::MAX as u128) as i64;
    // Presence is intentionally cached by the core dispatch path. Refresh it
    // for an explicit user send so a peer that came online after app startup
    // is dialed before the online-only fan-out selects its targets.
    app_facade
        .refresh_presence()
        .await
        .map_err(space_error)?;
    let snapshot = SystemClipboardSnapshot {
        ts_ms: now_ms,
        representations: vec![ObservedClipboardRepresentation::new(
            RepresentationId::new(),
            FormatId::from("text"),
            Some(MimeType("text/plain;charset=utf-8".to_string())),
            text.into_bytes(),
        )],
        file_content_digests: Vec::new(),
        file_set_v1_component: None,
    };
    let outcome = app_facade
        .dispatch_clipboard_snapshot(
            snapshot,
            ClipboardChangeOrigin::LocalCapture,
            target_filter,
        )
        .await
        .map_err(space_error)?;
    Ok(outcome.total_accepted.min(u32::MAX as usize) as u32)
}

#[napi]
pub async fn send_space_text(text: String) -> Result<u32> {
    send_space_text_with_filter(text, None).await
}

#[napi]
pub async fn send_space_text_to_device(text: String, device_id: String) -> Result<u32> {
    let target = device_id.trim();
    if target.is_empty() {
        return Err(Error::new(Status::InvalidArg, "target device id is required"));
    }
    send_space_text_with_filter(text, Some(vec![DeviceId::new(target)])).await
}

/// Dispatch a compressed image through the joined UniClipboard space. The
/// HarmonyOS layer keeps this payload below the encrypted wire inline limit.
async fn send_space_image_with_filter(
    data: Uint8Array,
    mime_type: String,
    target_filter: Option<Vec<DeviceId>>,
) -> Result<u32> {
    if data.is_empty() {
        return Err(Error::new(Status::InvalidArg, "clipboard image is required"));
    }
    if data.len() > MAX_SPACE_IMAGE_BYTES {
        return Err(Error::new(
            Status::InvalidArg,
            "clipboard image exceeds the 1.5 MiB space transfer limit",
        ));
    }
    let normalized_mime = mime_type.trim().to_ascii_lowercase();
    if normalized_mime != "image/jpeg" && normalized_mime != "image/png" {
        return Err(Error::new(Status::InvalidArg, "unsupported clipboard image type"));
    }
    let app_facade = {
        let guard = space_runtime().lock().await;
        guard
            .as_ref()
            .map(|runtime| runtime.app_facade.clone())
            .ok_or_else(|| Error::new(Status::GenericFailure, "space node has not been started"))?
    };
    let now_ms = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(space_error)?
        .as_millis()
        .min(i64::MAX as u128) as i64;
    app_facade
        .refresh_presence()
        .await
        .map_err(space_error)?;
    let snapshot = SystemClipboardSnapshot {
        ts_ms: now_ms,
        representations: vec![ObservedClipboardRepresentation::new(
            RepresentationId::new(),
            FormatId::from("image"),
            Some(MimeType(normalized_mime)),
            data.as_ref().to_vec(),
        )],
        file_content_digests: Vec::new(),
        file_set_v1_component: None,
    };
    let outcome = app_facade
        .dispatch_clipboard_snapshot(
            snapshot,
            ClipboardChangeOrigin::LocalCapture,
            target_filter,
        )
        .await
        .map_err(space_error)?;
    Ok(outcome.total_accepted.min(u32::MAX as usize) as u32)
}

#[napi]
pub async fn send_space_image(data: Uint8Array, mime_type: String) -> Result<u32> {
    send_space_image_with_filter(data, mime_type, None).await
}

#[napi]
pub async fn send_space_image_to_device(
    data: Uint8Array,
    mime_type: String,
    device_id: String,
) -> Result<u32> {
    let target = device_id.trim();
    if target.is_empty() {
        return Err(Error::new(Status::InvalidArg, "target device id is required"));
    }
    send_space_image_with_filter(data, mime_type, Some(vec![DeviceId::new(target)])).await
}

/// Dispatch one user-selected file through the joined encrypted space in bounded chunks.
#[napi]
pub async fn send_space_file(data: Uint8Array, file_name: String) -> Result<u32> {
    if data.is_empty() {
        return Err(Error::new(Status::InvalidArg, "file data is required"));
    }
    if data.len() > MAX_SPACE_FILE_BYTES {
        return Err(Error::new(
            Status::InvalidArg,
            "file exceeds the 64 MiB space transfer limit",
        ));
    }
    let normalized_name = file_name.trim();
    let name_bytes = normalized_name.as_bytes();
    if name_bytes.is_empty() || name_bytes.len() > u16::MAX as usize {
        return Err(Error::new(Status::InvalidArg, "invalid file name"));
    }
    let chunk_count = data.len().div_ceil(SPACE_FILE_CHUNK_BYTES);
    if chunk_count > 128 {
        return Err(Error::new(Status::InvalidArg, "file requires too many chunks"));
    }
    let app_facade = {
        let guard = space_runtime().lock().await;
        guard
            .as_ref()
            .map(|runtime| runtime.app_facade.clone())
            .ok_or_else(|| Error::new(Status::GenericFailure, "space node has not been started"))?
    };
    let now_ms = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(space_error)?
        .as_millis()
        .min(i64::MAX as u128) as i64;
    app_facade.refresh_presence().await.map_err(space_error)?;
    let sequence = SPACE_FILE_TRANSFER_SEQ.fetch_add(1, Ordering::Relaxed);
    let transfer_id = (now_ms as u64).rotate_left(16) ^ sequence;
    let mut minimum_accepted = usize::MAX;
    for chunk_index in 0..chunk_count {
        let chunk_start = chunk_index * SPACE_FILE_CHUNK_BYTES;
        let chunk_end = (chunk_start + SPACE_FILE_CHUNK_BYTES).min(data.len());
        let chunk = &data.as_ref()[chunk_start..chunk_end];
        let mut payload = Vec::with_capacity(SPACE_FILE_HEADER_BYTES + name_bytes.len() + chunk.len());
        payload.push(1);
        payload.extend_from_slice(&transfer_id.to_le_bytes());
        payload.extend_from_slice(&(chunk_index as u32).to_le_bytes());
        payload.extend_from_slice(&(chunk_count as u32).to_le_bytes());
        payload.extend_from_slice(&(data.len() as u64).to_le_bytes());
        payload.extend_from_slice(&(name_bytes.len() as u16).to_le_bytes());
        payload.extend_from_slice(name_bytes);
        payload.extend_from_slice(chunk);
        let snapshot = SystemClipboardSnapshot {
            ts_ms: now_ms.saturating_add(chunk_index as i64),
            representations: vec![ObservedClipboardRepresentation::new(
                RepresentationId::new(),
                FormatId::from("file"),
                Some(MimeType(SPACE_FILE_MIME.to_string())),
                payload,
            )],
            file_content_digests: Vec::new(),
            file_set_v1_component: None,
        };
        let outcome = app_facade
            .dispatch_clipboard_snapshot(snapshot, ClipboardChangeOrigin::LocalCapture, None)
            .await
            .map_err(space_error)?;
        if outcome.total_accepted == 0 {
            return Ok(0);
        }
        minimum_accepted = minimum_accepted.min(outcome.total_accepted);
    }
    Ok(minimum_accepted.min(u32::MAX as usize) as u32)
}

/// Publish a user-selected file through iroh-blobs using its open HarmonyOS
/// file descriptor.  The descriptor remains owned by ArkTS and is never
/// closed here; `/proc/self/fd/<n>` lets iroh stream/copy it without loading
/// the full file into memory.
async fn send_space_file_from_fd_with_filter(
    fd: i32,
    file_size: f64,
    file_name: String,
    target_filter: Option<Vec<DeviceId>>,
) -> Result<NativeSpaceFileSendResult> {
    if fd < 0 || !file_size.is_finite() || file_size <= 0.0 {
        return Err(Error::new(Status::InvalidArg, "valid non-empty file is required"));
    }
    let normalized_name = file_name.trim();
    if normalized_name.is_empty() {
        return Err(Error::new(Status::InvalidArg, "valid file name is required"));
    }
    let app_facade = {
        let guard = space_runtime().lock().await;
        guard
            .as_ref()
            .map(|runtime| runtime.app_facade.clone())
            .ok_or_else(|| Error::new(Status::GenericFailure, "space node has not been started"))?
    };
    let fd_path = std::path::PathBuf::from(format!("/proc/self/fd/{fd}"));
    let metadata = tokio::fs::metadata(&fd_path).await.map_err(space_error)?;
    if metadata.len() == 0 {
        return Err(Error::new(Status::InvalidArg, "file is empty"));
    }
    let entry_id = EntryId::new();
    app_facade.refresh_presence().await.map_err(space_error)?;
    let published = app_facade
        .publish_blob_path(PublishBlobPathCommand {
            path: fd_path,
            entry_id: Some(entry_id),
        })
        .await
        .map_err(space_error)?;
    let transfer_id = published.entry_id.as_str().to_string();
    let now_ms = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(space_error)?
        .as_millis()
        .min(i64::MAX as u128) as i64;
    let placeholder_uri = "file:///uniclipboard/payload\n";
    let snapshot = SystemClipboardSnapshot {
        ts_ms: now_ms,
        representations: vec![ObservedClipboardRepresentation::new(
            RepresentationId::new(),
            FormatId::from("files"),
            Some(MimeType("text/uri-list".to_string())),
            placeholder_uri.as_bytes().to_vec(),
        )],
        file_content_digests: vec![*published.plaintext_hash.as_bytes()],
        file_set_v1_component: None,
    };
    let blob_ref = V3BlobRef {
        ticket: published.ticket,
        entry_id: published.entry_id,
        filename: Some(normalized_name.to_string()),
        mime: None,
        size_bytes: metadata.len(),
        representation_index: None,
    };
    let outcome = app_facade
        .dispatch_clipboard_snapshot_with_blob_refs(
            snapshot,
            vec![blob_ref],
            ClipboardChangeOrigin::LocalCapture,
            target_filter,
        )
        .await
        .map_err(space_error)?;
    Ok(NativeSpaceFileSendResult {
        accepted_count: outcome.total_accepted.min(u32::MAX as usize) as u32,
        transfer_id,
    })
}

#[napi]
pub async fn send_space_file_from_fd(
    fd: i32,
    file_size: f64,
    file_name: String,
) -> Result<NativeSpaceFileSendResult> {
    send_space_file_from_fd_with_filter(fd, file_size, file_name, None).await
}

#[napi]
pub async fn send_space_file_from_fd_to_device(
    fd: i32,
    file_size: f64,
    file_name: String,
    device_id: String,
) -> Result<NativeSpaceFileSendResult> {
    let target = device_id.trim();
    if target.is_empty() {
        return Err(Error::new(Status::InvalidArg, "target device id is required"));
    }
    send_space_file_from_fd_with_filter(
        fd,
        file_size,
        file_name,
        Some(vec![DeviceId::new(target)]),
    )
    .await
}

/// Stream a materialized received file into an open HarmonyOS save target.
#[napi]
pub async fn copy_space_file_to_fd(source_path: String, target_fd: i32) -> Result<()> {
    if source_path.trim().is_empty() || target_fd < 0 {
        return Err(Error::new(Status::InvalidArg, "source path and target fd are required"));
    }
    tokio::task::spawn_blocking(move || -> std::io::Result<()> {
        let mut source = std::fs::File::open(source_path)?;
        let target_path = format!("/proc/self/fd/{target_fd}");
        let mut target = std::fs::OpenOptions::new()
            .write(true)
            .truncate(true)
            .open(target_path)?;
        std::io::copy(&mut source, &mut target)?;
        target.sync_all()?;
        Ok(())
    })
    .await
    .map_err(space_error)?
    .map_err(space_error)
}

/// Drain text clipboard frames received from peers since the previous call.
#[napi]
pub fn drain_space_text_events() -> Vec<NativeSpaceTextEvent> {
    let mut events = match space_text_events().lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };
    events
        .drain(..)
        .map(|event| NativeSpaceTextEvent {
            text: event.text,
            from_device_id: event.from_device_id,
            snapshot_hash: event.snapshot_hash,
        })
        .collect()
}

/// Drain image clipboard frames received from peers since the previous call.
#[napi]
pub fn drain_space_image_events() -> Vec<NativeSpaceImageEvent> {
    let mut events = match space_image_events().lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };
    events
        .drain(..)
        .map(|event| NativeSpaceImageEvent {
            data: event.data.into(),
            mime_type: event.mime_type,
            from_device_id: event.from_device_id,
            snapshot_hash: event.snapshot_hash,
        })
        .collect()
}

/// Drain file clipboard frames received from peers since the previous call.
#[napi]
pub fn drain_space_file_events() -> Vec<NativeSpaceFileEvent> {
    let mut events = match space_file_events().lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };
    events
        .drain(..)
        .map(|event| NativeSpaceFileEvent {
            data: event.data.into(),
            file_name: event.file_name,
            from_device_id: event.from_device_id,
            snapshot_hash: event.snapshot_hash,
            local_path: event.local_path,
            file_size: event.file_size as f64,
        })
        .collect()
}

/// Drain sender-side status changes reported by the receiving peer.
#[napi]
pub fn drain_space_file_status_events() -> Vec<NativeSpaceFileStatusEvent> {
    let mut events = match space_file_status_events().lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };
    events
        .drain(..)
        .map(|event| NativeSpaceFileStatusEvent {
            transfer_id: event.transfer_id,
            status: event.status,
            reason: event.reason,
        })
        .collect()
}

#[napi]
pub async fn stop_space_node() {
    mobile_sync_server::stop();
    abort_space_inbound_task();
    abort_space_keepalive_task();
    abort_space_materialized_file_task();
    {
        let mut events = match space_text_events().lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
        events.clear();
    }
    {
        let mut events = match space_image_events().lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
        events.clear();
    }
    {
        let mut events = match space_file_events().lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
        events.clear();
    }
    {
        let mut events = match space_file_status_events().lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
        events.clear();
    }
    {
        let mut assemblies = match space_file_assemblies().lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
        assemblies.clear();
    }
    let runtime = {
        let mut guard = space_runtime().lock().await;
        guard.take()
    };
    if let Some(runtime) = runtime {
        runtime.shutdown().await;
    }
}

fn mobile_sync_error(error: impl std::fmt::Display) -> Error {
    Error::new(Status::GenericFailure, error.to_string())
}

async fn mobile_sync_app_facade() -> Result<Arc<uc_application::facade::AppFacade>> {
    let guard = space_runtime().lock().await;
    guard
        .as_ref()
        .map(|runtime| runtime.app_facade.clone())
        .ok_or_else(|| Error::new(Status::GenericFailure, "native node is not ready"))
}

async fn mobile_sync_urls(
    facade: &uc_application::facade::MobileSyncFacade,
    port: u16,
) -> Result<Vec<String>> {
    let interfaces = facade
        .list_lan_interfaces()
        .await
        .map_err(mobile_sync_error)?;
    Ok(interfaces
        .into_iter()
        .map(|interface| format!("http://{}:{port}", interface.ipv4))
        .collect())
}

/// Return persisted mobile-sync settings plus the actual in-process listener state.
#[napi]
pub async fn get_mobile_sync_server_status() -> Result<NativeMobileSyncStatus> {
    let app_facade = mobile_sync_app_facade().await?;
    let facade = app_facade
        .mobile_sync
        .get()
        .cloned()
        .ok_or_else(|| Error::new(Status::GenericFailure, "mobile sync is unavailable"))?;
    let settings = facade.get_settings().await.map_err(mobile_sync_error)?;
    let port = settings.lan_port.unwrap_or(42720);
    let urls = mobile_sync_urls(&facade, port).await.unwrap_or_else(|_| Vec::new());
    Ok(NativeMobileSyncStatus {
        enabled: settings.enabled,
        lan_listen_enabled: settings.lan_listen_enabled,
        running: mobile_sync_server::running_port() == port,
        port: u32::from(port),
        urls,
    })
}

/// Enable/disable the embedded SyncClipboard-compatible LAN HTTP server.
#[napi]
pub async fn set_mobile_sync_server_enabled(enabled: bool, port: u32) -> Result<NativeMobileSyncStatus> {
    if port == 0 || port > u32::from(u16::MAX) {
        return Err(Error::new(Status::InvalidArg, "port must be in 1..=65535"));
    }
    let port = port as u16;
    let app_facade = mobile_sync_app_facade().await?;
    let facade = app_facade
        .mobile_sync
        .get()
        .cloned()
        .ok_or_else(|| Error::new(Status::GenericFailure, "mobile sync is unavailable"))?;
    facade
        .update_settings(UpdateMobileSyncSettingsInput {
            enabled: Some(enabled),
            lan_listen_enabled: Some(enabled),
            lan_advertise_ip: None,
            lan_advertise_base_url: None,
            lan_port: Some(Some(port)),
        })
        .await
        .map_err(mobile_sync_error)?;
    if enabled {
        mobile_sync_server::start(app_facade, port)
            .await
            .map_err(mobile_sync_error)?;
    } else {
        mobile_sync_server::stop();
    }
    let urls = mobile_sync_urls(&facade, port).await.unwrap_or_else(|_| Vec::new());
    Ok(NativeMobileSyncStatus {
        enabled,
        lan_listen_enabled: enabled,
        running: enabled && mobile_sync_server::running_port() == port,
        port: u32::from(port),
        urls,
    })
}

/// Create long-lived Basic Auth credentials and the official UniClipboard connect URI.
#[napi]
pub async fn register_mobile_sync_device(
    label: String,
    custom_username: String,
    custom_password: String,
    port: u32,
) -> Result<NativeMobileSyncCredential> {
    if port == 0 || port > u32::from(u16::MAX) {
        return Err(Error::new(Status::InvalidArg, "port must be in 1..=65535"));
    }
    let port = port as u16;
    let app_facade = mobile_sync_app_facade().await?;
    let facade = app_facade
        .mobile_sync
        .get()
        .cloned()
        .ok_or_else(|| Error::new(Status::GenericFailure, "mobile sync is unavailable"))?;
    facade
        .update_settings(UpdateMobileSyncSettingsInput {
            enabled: Some(true),
            lan_listen_enabled: Some(true),
            lan_advertise_ip: None,
            lan_advertise_base_url: None,
            lan_port: Some(Some(port)),
        })
        .await
        .map_err(mobile_sync_error)?;
    mobile_sync_server::start(app_facade, port)
        .await
        .map_err(mobile_sync_error)?;
    let username = if custom_username.trim().is_empty() {
        None
    } else {
        Some(custom_username.trim().to_string())
    };
    let password = if custom_password.is_empty() {
        None
    } else {
        Some(custom_password)
    };
    let output = facade
        .register_device(RegisterMobileShortcutDeviceInput {
            label: label.trim().to_string(),
            username,
            password,
        })
        .await
        .map_err(mobile_sync_error)?;
    let payload = uc_mobile_proto::parse_mobile_sync_connect_uri(&output.connect_uri)
        .map_err(mobile_sync_error)?;
    Ok(NativeMobileSyncCredential {
        device_id: output.device.device_id.into_string(),
        label: output.device.label,
        username: output.username,
        password: output.password,
        connect_uri: output.connect_uri,
        urls: payload.urls,
    })
}

#[napi]
pub async fn list_mobile_sync_devices() -> Result<Vec<NativeMobileSyncDevice>> {
    let app_facade = mobile_sync_app_facade().await?;
    let facade = app_facade
        .mobile_sync
        .get()
        .cloned()
        .ok_or_else(|| Error::new(Status::GenericFailure, "mobile sync is unavailable"))?;
    let devices = facade.list_devices().await.map_err(mobile_sync_error)?;
    Ok(devices
        .into_iter()
        .map(|device| {
            let device_id: String = device.device_id.into_string();
            let live_activity_ms: u64 = mobile_sync_server::device_last_activity_ms(&device_id);
            let stored_activity_ms: u64 = device.last_seen_at_ms.unwrap_or(0).max(0) as u64;
            NativeMobileSyncDevice {
                online: mobile_sync_server::is_device_online(&device_id),
                device_id,
                label: device.label,
                username: device.username,
                created_at_ms: device.created_at_ms as f64,
                last_seen_at_ms: live_activity_ms.max(stored_activity_ms) as f64,
                last_seen_ip: device.last_seen_ip.unwrap_or_default(),
            }
        })
        .collect())
}

#[napi]
pub async fn revoke_mobile_sync_device(device_id: String) -> Result<()> {
    let app_facade = mobile_sync_app_facade().await?;
    let facade = app_facade
        .mobile_sync
        .get()
        .cloned()
        .ok_or_else(|| Error::new(Status::GenericFailure, "mobile sync is unavailable"))?;
    facade
        .revoke_device(RevokeMobileDeviceInput {
            device_id: MobileDeviceId::new(device_id),
        })
        .await
        .map_err(mobile_sync_error)
}

#[napi]
pub fn publish_mobile_sync_text(text: String) -> Result<String> {
    if mobile_sync_server::running_port() == 0 {
        return Err(Error::new(Status::GenericFailure, "mobile sync server is not running"));
    }
    Ok(mobile_sync_server::publish_text(text))
}

#[napi]
pub fn publish_mobile_sync_image(data: Uint8Array, mime_type: String) -> Result<String> {
    if mobile_sync_server::running_port() == 0 {
        return Err(Error::new(Status::GenericFailure, "mobile sync server is not running"));
    }
    Ok(mobile_sync_server::publish_data(
        "image",
        "image.png".to_string(),
        "image.png".to_string(),
        mime_type,
        data.to_vec(),
    ))
}

#[napi]
pub fn publish_mobile_sync_file_from_fd(
    fd: i32,
    file_size: f64,
    file_name: String,
    mime_type: String,
) -> Result<String> {
    if mobile_sync_server::running_port() == 0 {
        return Err(Error::new(Status::GenericFailure, "mobile sync server is not running"));
    }
    if file_size <= 0.0 || file_size > (64 * 1024 * 1024) as f64 {
        return Err(Error::new(Status::InvalidArg, "file must be between 1 byte and 64 MiB"));
    }
    let mut file = std::fs::File::open(format!("/proc/self/fd/{fd}"))
        .map_err(mobile_sync_error)?;
    let mut data = Vec::with_capacity(file_size as usize);
    file.take(file_size as u64)
        .read_to_end(&mut data)
        .map_err(mobile_sync_error)?;
    if data.len() != file_size as usize {
        return Err(Error::new(Status::GenericFailure, "selected file changed while reading"));
    }
    Ok(mobile_sync_server::publish_data(
        "file",
        file_name.clone(),
        file_name,
        mime_type,
        data,
    ))
}

#[napi]
pub fn drain_mobile_sync_inbound_events() -> Vec<NativeMobileSyncInboundEvent> {
    mobile_sync_server::drain_events()
        .into_iter()
        .map(|event| NativeMobileSyncInboundEvent {
            kind: event.kind,
            text: event.text,
            data_name: event.data_name,
            mime_type: event.mime_type,
            data: event.data.into(),
            content_id: event.content_id,
            source_label: event.source_label,
        })
        .collect()
}

#[napi]
pub async fn probe_server(config: NativeServerConfig) -> Result<()> {
    let client = mobile_client()?;
    let outcome = client.test_connection(config.into(), false).await;
    match outcome {
        ProbeResult::Success => Ok(()),
        ProbeResult::AuthFailed => Err(Error::new(
            Status::GenericFailure,
            "unauthorized (401): check username/password",
        )),
        ProbeResult::MissingFields => Err(Error::new(
            Status::InvalidArg,
            "server URL, username, and password are required",
        )),
        ProbeResult::Unreachable => Err(Error::new(
            Status::GenericFailure,
            "server is unreachable or returned an invalid response",
        )),
    }
}

#[napi]
pub async fn get_latest_text(config: NativeServerConfig) -> Result<LatestText> {
    let client = mobile_client()?;
    let latest = client.get_latest(config.into()).await.map_err(sync_error)?;
    if latest.kind != ClipboardKind::Text {
        return Err(Error::new(
            Status::GenericFailure,
            "latest clipboard is not text",
        ));
    }

    Ok(LatestText {
        text: latest.text,
        content_id: latest.content_id.unwrap_or_default(),
    })
}

#[napi]
pub async fn get_latest_content(config: NativeServerConfig) -> Result<NativeClipboardContent> {
    let client = mobile_client()?;
    let server: MobileServerConfig = config.into();
    let latest = client
        .get_latest(server.clone())
        .await
        .map_err(sync_error)?;
    let data_name = latest.data_name.clone().unwrap_or_default();
    let data = if latest.kind == ClipboardKind::Image && latest.has_data {
        if data_name.is_empty() {
            return Err(Error::new(
                Status::GenericFailure,
                "clipboard payload is missing dataName",
            ));
        }
        client
            .get_file(server, data_name.clone())
            .await
            .map_err(sync_error)?
    } else {
        Vec::new()
    };
    Ok(NativeClipboardContent {
        kind: history_kind(latest.kind),
        text: latest.text,
        content_id: latest.content_id.unwrap_or_default(),
        data_name,
        data: data.into(),
    })
}

#[napi]
pub async fn put_text(config: NativeServerConfig, text: String) -> Result<Option<String>> {
    let client = mobile_client()?;
    let (entry, payload) = uc_mobile_proto::publish_text(&text);
    let meta = ClipboardMeta {
        kind: ClipboardKind::Text,
        text: entry.text,
        data_name: entry.data_name,
        has_data: entry.has_data,
        size: entry.size.unwrap_or(0).max(0) as u64,
        hash: entry.hash,
        content_id: None,
    };

    client
        .put_clipboard(config.into(), meta, payload)
        .await
        .map_err(sync_error)
}

#[napi]
pub async fn put_image(config: NativeServerConfig, data: Uint8Array) -> Result<Option<String>> {
    if data.is_empty() {
        return Err(Error::new(Status::InvalidArg, "image data is empty"));
    }
    let client = mobile_client()?;
    let bytes: Vec<u8> = data.as_ref().to_vec();
    let (entry, payload) = uc_mobile_proto::publish_image(&bytes, "png");
    let meta = ClipboardMeta {
        kind: ClipboardKind::Image,
        text: entry.text,
        data_name: entry.data_name,
        has_data: entry.has_data,
        size: entry.size.unwrap_or(0).max(0) as u64,
        hash: entry.hash,
        content_id: None,
    };
    client
        .put_clipboard(config.into(), meta, Some(payload))
        .await
        .map_err(sync_error)
}

/// Upload a user-selected file to the configured desktop mobile-sync endpoint
/// and activate it there. The descriptor remains owned by ArkTS; this bridge
/// only reads it through `/proc/self/fd/<n>` while the async call is pending.
#[napi]
pub async fn put_file_from_fd(
    config: NativeServerConfig,
    fd: i32,
    file_size: f64,
    file_name: String,
) -> Result<Option<String>> {
    if fd < 0 || !file_size.is_finite() || file_size <= 0.0 {
        return Err(Error::new(Status::InvalidArg, "valid non-empty file is required"));
    }
    if file_size > MAX_SPACE_FILE_BYTES as f64 {
        return Err(Error::new(
            Status::InvalidArg,
            "file exceeds the 64 MiB mobile relay limit",
        ));
    }
    let normalized_name = file_name.trim();
    if normalized_name.is_empty() {
        return Err(Error::new(Status::InvalidArg, "valid file name is required"));
    }

    let fd_path = std::path::PathBuf::from(format!("/proc/self/fd/{fd}"));
    let bytes = tokio::fs::read(fd_path).await.map_err(space_error)?;
    if bytes.is_empty() {
        return Err(Error::new(Status::InvalidArg, "file is empty"));
    }
    if bytes.len() > MAX_SPACE_FILE_BYTES {
        return Err(Error::new(
            Status::InvalidArg,
            "file exceeds the 64 MiB mobile relay limit",
        ));
    }

    let client = mobile_client()?;
    let (entry, payload) = uc_mobile_proto::publish_file(normalized_name, &bytes);
    let meta = ClipboardMeta {
        kind: ClipboardKind::File,
        text: entry.text,
        data_name: entry.data_name,
        has_data: entry.has_data,
        size: entry.size.unwrap_or(0).max(0) as u64,
        hash: entry.hash,
        content_id: None,
    };
    client
        .put_clipboard(config.into(), meta, Some(payload))
        .await
        .map_err(sync_error)
}

#[napi]
pub async fn query_text_history(
    config: NativeServerConfig,
    page: i32,
    search_text: String,
    starred_only: bool,
) -> Result<Vec<NativeHistoryItem>> {
    let client = mobile_client()?;
    let query = HistoryQuery {
        page: Some(i64::from(page.max(1))),
        before_ms: None,
        after_ms: None,
        modified_after_ms: None,
        types: Some(1),
        search_text: if search_text.trim().is_empty() {
            None
        } else {
            Some(search_text)
        },
        starred: if starred_only { Some(true) } else { None },
        sort_by_last_accessed: None,
    };
    let records = client
        .query_history(config.into(), query)
        .await
        .map_err(sync_error)?;
    Ok(records
        .into_iter()
        .filter(|record| !record.is_deleted && record.kind == ClipboardKind::Text)
        .map(native_history_item)
        .collect())
}

#[napi]
pub async fn query_clipboard_history(
    config: NativeServerConfig,
    page: i32,
    search_text: String,
    starred_only: bool,
) -> Result<Vec<NativeHistoryItem>> {
    let client = mobile_client()?;
    let query = HistoryQuery {
        page: Some(i64::from(page.max(1))),
        before_ms: None,
        after_ms: None,
        modified_after_ms: None,
        types: Some(1 | 2 | 4 | 8),
        search_text: if search_text.trim().is_empty() {
            None
        } else {
            Some(search_text)
        },
        starred: if starred_only { Some(true) } else { None },
        sort_by_last_accessed: None,
    };
    let records = client
        .query_history(config.into(), query)
        .await
        .map_err(sync_error)?;
    Ok(records
        .into_iter()
        .filter(|record| !record.is_deleted)
        .map(native_history_item)
        .collect())
}

#[napi]
pub async fn get_history_payload(
    config: NativeServerConfig,
    kind: String,
    hash: String,
) -> Result<Uint8Array> {
    let parsed_kind = parse_history_kind(kind.trim())?;
    let profile_id = format!("{}-{hash}", history_kind(parsed_kind));
    let client = mobile_client()?;
    let data = client
        .get_history_payload(config.into(), profile_id)
        .await
        .map_err(sync_error)?;
    Ok(data.into())
}

#[napi]
pub fn start_sse(config: NativeServerConfig) -> Result<()> {
    let client = mobile_client()?;
    cancel_sse_subscription();
    {
        let mut events = match sse_events().lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
        events.clear();
    }
    let generation = SSE_GENERATION.load(Ordering::Acquire);
    let listener = Arc::new(HarmonySseListener { generation });
    let handle = client.start_sse_subscription(config.into(), listener);
    let mut current = match sse_handle().lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };
    *current = Some(handle);
    Ok(())
}

#[napi]
pub fn stop_sse() {
    cancel_sse_subscription();
    let mut events = match sse_events().lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };
    events.clear();
}

#[napi]
pub fn drain_sse_events() -> Vec<NativeSseEvent> {
    let mut events = match sse_events().lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };
    let mut result = Vec::with_capacity(events.len());
    while let Some(event) = events.pop_front() {
        result.push(NativeSseEvent {
            event_type: event.event_type,
            detail: event.detail,
        });
    }
    result
}

#[napi]
pub async fn set_text_history_starred(
    config: NativeServerConfig,
    hash: String,
    starred: bool,
    version: f64,
) -> Result<NativeHistoryItem> {
    patch_text_history(
        config,
        hash,
        HistoryPatch {
            starred: Some(starred),
            pinned: None,
            is_delete: None,
            version: Some(version.max(0.0) as i64),
        },
    )
    .await
}

#[napi]
pub async fn set_text_history_pinned(
    config: NativeServerConfig,
    hash: String,
    pinned: bool,
    version: f64,
) -> Result<NativeHistoryItem> {
    patch_text_history(
        config,
        hash,
        HistoryPatch {
            starred: None,
            pinned: Some(pinned),
            is_delete: None,
            version: Some(version.max(0.0) as i64),
        },
    )
    .await
}

#[napi]
pub async fn delete_text_history(
    config: NativeServerConfig,
    hash: String,
    version: f64,
) -> Result<NativeHistoryItem> {
    patch_text_history(
        config,
        hash,
        HistoryPatch {
            starred: None,
            pinned: None,
            is_delete: Some(true),
            version: Some(version.max(0.0) as i64),
        },
    )
    .await
}

#[napi]
pub async fn set_history_starred(
    config: NativeServerConfig,
    kind: String,
    hash: String,
    starred: bool,
    version: f64,
) -> Result<NativeHistoryItem> {
    patch_history(
        config,
        kind,
        hash,
        HistoryPatch {
            starred: Some(starred),
            pinned: None,
            is_delete: None,
            version: Some(version.max(0.0) as i64),
        },
    )
    .await
}

#[napi]
pub async fn set_history_pinned(
    config: NativeServerConfig,
    kind: String,
    hash: String,
    pinned: bool,
    version: f64,
) -> Result<NativeHistoryItem> {
    patch_history(
        config,
        kind,
        hash,
        HistoryPatch {
            starred: None,
            pinned: Some(pinned),
            is_delete: None,
            version: Some(version.max(0.0) as i64),
        },
    )
    .await
}

#[napi]
pub async fn delete_history(
    config: NativeServerConfig,
    kind: String,
    hash: String,
    version: f64,
) -> Result<NativeHistoryItem> {
    patch_history(
        config,
        kind,
        hash,
        HistoryPatch {
            starred: None,
            pinned: None,
            is_delete: Some(true),
            version: Some(version.max(0.0) as i64),
        },
    )
    .await
}

async fn patch_history(
    config: NativeServerConfig,
    kind: String,
    hash: String,
    patch: HistoryPatch,
) -> Result<NativeHistoryItem> {
    let parsed_kind = parse_history_kind(kind.trim())?;
    let client = mobile_client()?;
    let record = client
        .patch_history(config.into(), parsed_kind, hash, patch)
        .await
        .map_err(sync_error)?;
    Ok(native_history_item(record))
}

async fn patch_text_history(
    config: NativeServerConfig,
    hash: String,
    patch: HistoryPatch,
) -> Result<NativeHistoryItem> {
    let client = mobile_client()?;
    let record = client
        .patch_history(config.into(), ClipboardKind::Text, hash, patch)
        .await
        .map_err(sync_error)?;
    Ok(native_history_item(record))
}
