//! Small, dependency-free LAN adapter for the SyncClipboard HTTP contract.
//! The application/core owns credentials and clipboard persistence; this file
//! only translates HTTP requests into facade calls and exposes a process-local
//! snapshot for the HarmonyOS shell.

use std::collections::{HashMap, VecDeque};
use std::io;
use std::sync::atomic::{AtomicU16, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use uc_application::facade::mobile_sync::{
    ApplyIncomingMobileClipOutcome, AuthenticateBasicAuthInput, SyncClipboardItemType,
};
use uc_application::facade::AppFacade;

const MAX_PENDING_EVENTS: usize = 64;
const MAX_UPLOAD_BYTES: usize = 64 * 1024 * 1024;
const MAX_REQUEST_HEADER_BYTES: usize = 32 * 1024;
const ONLINE_TTL_MS: u64 = 60_000;

static SERVER_STATE: OnceLock<Arc<MobileServerState>> = OnceLock::new();
static SERVER_TASK: OnceLock<Mutex<Option<tokio::task::JoinHandle<()>>>> = OnceLock::new();
static SERVER_PORT: AtomicU16 = AtomicU16::new(0);
static TRANSFER_SEQUENCE: AtomicU64 = AtomicU64::new(1);

#[derive(Clone)]
pub(crate) struct MobileServerInboundEvent {
    pub kind: String,
    pub text: String,
    pub data_name: String,
    pub mime_type: String,
    pub data: Vec<u8>,
    pub content_id: String,
    pub source_label: String,
}

#[derive(Clone, Copy)]
enum WireType {
    Text,
    Image,
    File,
    Group,
}

impl WireType {
    fn from_str(value: &str) -> Self {
        match value {
            "Image" => Self::Image,
            "File" => Self::File,
            "Group" => Self::Group,
            _ => Self::Text,
        }
    }

    fn as_str(self) -> &'static str {
        match self {
            Self::Text => "Text",
            Self::Image => "Image",
            Self::File => "File",
            Self::Group => "Group",
        }
    }

    fn application_type(self) -> SyncClipboardItemType {
        match self {
            Self::Text => SyncClipboardItemType::Text,
            Self::Image => SyncClipboardItemType::Image,
            Self::File => SyncClipboardItemType::File,
            Self::Group => SyncClipboardItemType::Group,
        }
    }
}

#[derive(Clone)]
struct Snapshot {
    available: bool,
    wire_type: WireType,
    text: String,
    data_name: String,
    mime_type: String,
    data: Vec<u8>,
    hash: String,
    content_id: String,
}

impl Default for Snapshot {
    fn default() -> Self {
        let data: Vec<u8> = Vec::new();
        Self {
            available: false,
            wire_type: WireType::Text,
            text: String::new(),
            data_name: String::new(),
            mime_type: "text/plain; charset=utf-8".to_string(),
            hash: uc_mobile_proto::sha256_hex_upper(&data),
            content_id: uc_content_hash::snapshot_hash_single_payload(&data),
            data,
        }
    }
}

struct PendingUpload {
    mime_type: String,
    data: Vec<u8>,
}

struct MobileServerState {
    snapshot: Mutex<Snapshot>,
    pending_uploads: Mutex<HashMap<String, PendingUpload>>,
    inbound_events: Mutex<VecDeque<MobileServerInboundEvent>>,
    device_activity: Mutex<HashMap<String, u64>>,
    updates: tokio::sync::broadcast::Sender<String>,
}

impl MobileServerState {
    fn new() -> Self {
        let (updates, _) = tokio::sync::broadcast::channel(64);
        Self {
            snapshot: Mutex::new(Snapshot::default()),
            pending_uploads: Mutex::new(HashMap::new()),
            inbound_events: Mutex::new(VecDeque::new()),
            device_activity: Mutex::new(HashMap::new()),
            updates,
        }
    }

    fn publish(&self, snapshot: Snapshot) {
        let content_id: String = snapshot.content_id.clone();
        let mut current = lock(&self.snapshot);
        *current = snapshot;
        drop(current);
        let _ = self.updates.send(content_id);
    }

    fn enqueue(&self, event: MobileServerInboundEvent) {
        let mut events = lock(&self.inbound_events);
        if events.len() >= MAX_PENDING_EVENTS {
            events.pop_front();
        }
        events.push_back(event);
    }

    fn mark_device_activity(&self, device_id: &str) {
        lock(&self.device_activity).insert(device_id.to_string(), now_ms());
    }

    fn device_last_activity_ms(&self, device_id: &str) -> u64 {
        lock(&self.device_activity)
            .get(device_id)
            .copied()
            .unwrap_or(0)
    }
}

fn lock<T>(value: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    match value.lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    }
}

fn shared_state() -> Arc<MobileServerState> {
    SERVER_STATE
        .get_or_init(|| Arc::new(MobileServerState::new()))
        .clone()
}

fn task_slot() -> &'static Mutex<Option<tokio::task::JoinHandle<()>>> {
    SERVER_TASK.get_or_init(|| Mutex::new(None))
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

fn json_escape(value: &str) -> String {
    let mut output: String = String::with_capacity(value.len() + 8);
    for character in value.chars() {
        match character {
            '"' => output.push_str("\\\""),
            '\\' => output.push_str("\\\\"),
            '\n' => output.push_str("\\n"),
            '\r' => output.push_str("\\r"),
            '\t' => output.push_str("\\t"),
            character if character.is_control() => output.push(' '),
            _ => output.push(character),
        }
    }
    output
}

fn json_string_field(body: &str, field: &str) -> Option<String> {
    let marker: String = format!("\"{field}\"");
    let start: usize = body.find(&marker)? + marker.len();
    let colon: usize = body[start..].find(':')? + start + 1;
    let bytes: &[u8] = body.as_bytes();
    let mut index: usize = colon;
    while index < bytes.len() && bytes[index].is_ascii_whitespace() {
        index += 1;
    }
    if index >= bytes.len() || bytes[index] != b'"' {
        return None;
    }
    index += 1;
    let mut output: String = String::new();
    let mut escaped: bool = false;
    while index < body.len() {
        let Some(character) = body[index..].chars().next() else {
            break;
        };
        index += character.len_utf8();
        if escaped {
            match character {
                'n' => output.push('\n'),
                'r' => output.push('\r'),
                't' => output.push('\t'),
                'b' => output.push('\u{0008}'),
                'f' => output.push('\u{000c}'),
                '"' => output.push('"'),
                '\\' => output.push('\\'),
                '/' => output.push('/'),
                'u' => {
                    if index + 4 <= body.len() {
                        let digits: &str = &body[index..index + 4];
                        if let Ok(code) = u16::from_str_radix(digits, 16) {
                            if let Some(decoded) = char::from_u32(u32::from(code)) {
                                output.push(decoded);
                            }
                            index += 4;
                        } else {
                            output.push('u');
                        }
                    } else {
                        output.push('u');
                    }
                }
                _ => output.push(character),
            }
            escaped = false;
        } else if character == '\\' {
            escaped = true;
        } else if character == '"' {
            return Some(output);
        } else {
            output.push(character);
        }
    }
    None
}

fn json_number_field(body: &str, field: &str) -> u64 {
    let marker: String = format!("\"{field}\"");
    let Some(start) = body.find(&marker) else {
        return 0;
    };
    let Some(colon_offset) = body[start + marker.len()..].find(':') else {
        return 0;
    };
    let colon: usize = start + marker.len() + colon_offset + 1;
    let mut end: usize = colon;
    let bytes: &[u8] = body.as_bytes();
    while end < bytes.len() && (bytes[end].is_ascii_digit() || bytes[end] == b' ') {
        end += 1;
    }
    body[colon..end].trim().parse::<u64>().unwrap_or(0)
}

fn json_bool_field(body: &str, field: &str) -> bool {
    let marker: String = format!("\"{field}\"");
    let Some(start) = body.find(&marker) else {
        return false;
    };
    let Some(colon_offset) = body[start + marker.len()..].find(':') else {
        return false;
    };
    body[start + marker.len() + colon_offset + 1..]
        .trim_start()
        .starts_with("true")
}

fn percent_decode(value: &str) -> String {
    let bytes: &[u8] = value.as_bytes();
    let mut output: Vec<u8> = Vec::with_capacity(bytes.len());
    let mut index: usize = 0;
    while index < bytes.len() {
        if bytes[index] == b'%' && index + 2 < bytes.len() {
            let hex: String = value[index + 1..index + 3].to_string();
            if let Ok(decoded) = u8::from_str_radix(&hex, 16) {
                output.push(decoded);
                index += 3;
                continue;
            }
        }
        output.push(bytes[index]);
        index += 1;
    }
    String::from_utf8(output).unwrap_or_default()
}

fn response(status: &str, content_type: &str, body: &[u8]) -> Vec<u8> {
    let header: String = format!(
        "HTTP/1.1 {status}\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
        body.len()
    );
    let mut output: Vec<u8> = header.into_bytes();
    output.extend_from_slice(body);
    output
}

fn unauthorized_response() -> Vec<u8> {
    let body: &[u8] = b"unauthorized";
    let header: String = format!(
        "HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Basic realm=\"UniClipboard\"\r\nContent-Type: text/plain\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
        body.len()
    );
    let mut output: Vec<u8> = header.into_bytes();
    output.extend_from_slice(body);
    output
}

async fn authenticate(
    app_facade: &Arc<AppFacade>,
    authorization: &str,
) -> Result<uc_application::facade::mobile_sync::AuthenticatedDevice, Vec<u8>> {
    let Some(facade) = app_facade.mobile_sync.get().cloned() else {
        return Err(response("503 Service Unavailable", "text/plain", b"mobile sync unavailable"));
    };
    facade
        .authenticate_basic(AuthenticateBasicAuthInput {
            authorization_header: authorization.to_string(),
        })
        .await
        .map_err(|_| unauthorized_response())
}

struct ParsedRequest {
    method: String,
    path: String,
    authorization: String,
    content_type: String,
    body: Vec<u8>,
}

async fn read_request(stream: &mut TcpStream) -> io::Result<ParsedRequest> {
    let mut buffer: Vec<u8> = Vec::new();
    let mut chunk: [u8; 4096] = [0; 4096];
    let header_end: usize;
    loop {
        let read: usize = stream.read(&mut chunk).await?;
        if read == 0 {
            return Err(io::Error::new(io::ErrorKind::UnexpectedEof, "request closed"));
        }
        buffer.extend_from_slice(&chunk[..read]);
        if buffer.len() > MAX_REQUEST_HEADER_BYTES {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "request headers too large"));
        }
        if let Some(position) = buffer.windows(4).position(|window| window == b"\r\n\r\n") {
            header_end = position + 4;
            break;
        }
    }
    let header_text: String = String::from_utf8_lossy(&buffer[..header_end]).to_string();
    let mut lines = header_text.split("\r\n");
    let request_line: &str = lines.next().unwrap_or_default();
    let mut request_parts = request_line.split_whitespace();
    let method: String = request_parts.next().unwrap_or_default().to_string();
    let path: String = request_parts.next().unwrap_or_default().to_string();
    let mut authorization: String = String::new();
    let mut content_type: String = "application/octet-stream".to_string();
    let mut content_length: usize = 0;
    for line in lines {
        let Some(separator) = line.find(':') else {
            continue;
        };
        let name: String = line[..separator].trim().to_ascii_lowercase();
        let value: String = line[separator + 1..].trim().to_string();
        if name == "authorization" {
            authorization = value;
        } else if name == "content-type" {
            content_type = value;
        } else if name == "content-length" {
            content_length = value.parse::<usize>().unwrap_or(0);
        }
    }
    if content_length > MAX_UPLOAD_BYTES {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "request body too large"));
    }
    let mut body: Vec<u8> = buffer[header_end..].to_vec();
    while body.len() < content_length {
        let read: usize = stream.read(&mut chunk).await?;
        if read == 0 {
            return Err(io::Error::new(io::ErrorKind::UnexpectedEof, "body closed"));
        }
        body.extend_from_slice(&chunk[..read]);
    }
    body.truncate(content_length);
    Ok(ParsedRequest {
        method,
        path,
        authorization,
        content_type,
        body,
    })
}

async fn handle_request(mut stream: TcpStream, app_facade: Arc<AppFacade>, shared: Arc<MobileServerState>) {
    let request: ParsedRequest = match read_request(&mut stream).await {
        Ok(request) => request,
        Err(_) => return,
    };
    if request.path == "/api/sse/clipboard" && request.method == "GET" {
        let authenticated = match authenticate(&app_facade, &request.authorization).await {
            Ok(device) => device,
            Err(body) => {
                let _ = stream.write_all(&body).await;
                return;
            }
        };
        let device_id: String = authenticated.device.device_id.as_str().to_string();
        shared.mark_device_activity(&device_id);
        let header: &[u8] = b"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n";
        if stream.write_all(header).await.is_err() {
            return;
        }
        let hello: String = format!("event: hello\ndata: {{\"serverTimeMs\":{}}}\n\n", now_ms());
        if stream.write_all(hello.as_bytes()).await.is_err() {
            return;
        }
        let mut receiver = shared.updates.subscribe();
        loop {
            match tokio::time::timeout(Duration::from_secs(25), receiver.recv()).await {
                Ok(Ok(content_id)) => {
                    shared.mark_device_activity(&device_id);
                    let event: String = format!(
                        "event: update\ndata: {{\"contentId\":\"{}\"}}\n\n",
                        json_escape(&content_id)
                    );
                    if stream.write_all(event.as_bytes()).await.is_err() {
                        return;
                    }
                }
                Ok(Err(_)) => {
                    shared.mark_device_activity(&device_id);
                    let _ = stream.write_all(b"event: resync\ndata: {}\n\n").await;
                }
                Err(_) => {
                    shared.mark_device_activity(&device_id);
                    if stream.write_all(b": heartbeat\n\n").await.is_err() {
                        return;
                    }
                }
            }
        }
    }
    let authenticated = match authenticate(&app_facade, &request.authorization).await {
        Ok(device) => device,
        Err(body) => {
            let _ = stream.write_all(&body).await;
            return;
        }
    };
    shared.mark_device_activity(authenticated.device.device_id.as_str());
    if request.path == "/SyncClipboard.json" && request.method == "GET" {
        let published_snapshot: Snapshot = lock(&shared.snapshot).clone();
        let body: String = if published_snapshot.available {
            format_snapshot_json(&published_snapshot)
        } else {
            match app_facade.mobile_sync.get().cloned() {
                Some(facade) => match facade.get_latest_sync_doc().await {
                    Ok(meta) => format_sync_meta_json(&meta),
                    Err(_) => format_snapshot_json(&published_snapshot),
                },
                None => format_snapshot_json(&published_snapshot),
            }
        };
        let _ = stream.write_all(&response("200 OK", "application/json; charset=utf-8", body.as_bytes())).await;
        return;
    }
    if request.path == "/SyncClipboard.json" && request.method == "PUT" {
        let body_text: String = String::from_utf8_lossy(&request.body).to_string();
        let wire_type: WireType = WireType::from_str(
            &json_string_field(&body_text, "type").unwrap_or_else(|| "Text".to_string()),
        );
        let text: String = json_string_field(&body_text, "text").unwrap_or_default();
        let data_name: String = json_string_field(&body_text, "dataName").unwrap_or_default();
        let has_data: bool = json_bool_field(&body_text, "hasData");
        let size: u64 = json_number_field(&body_text, "size");
        let Some(facade) = app_facade.mobile_sync.get().cloned() else {
            let _ = stream.write_all(&response("503 Service Unavailable", "text/plain", b"mobile sync unavailable")).await;
            return;
        };
        let meta = uc_application::facade::SyncClipboardMeta {
            item_type: wire_type.application_type(),
            text: text.clone(),
            data_name: if data_name.is_empty() { None } else { Some(data_name.clone()) },
            has_data,
            size,
            hash: json_string_field(&body_text, "hash"),
            content_id: json_string_field(&body_text, "contentId"),
        };
        let outcome = facade
            .put_sync_doc(meta, authenticated.device.device_id.clone())
            .await;
        match outcome {
            Err(_) => {
                let _ = stream.write_all(&response("500 Internal Server Error", "text/plain", b"incoming clipboard failed")).await;
                return;
            }
            Ok(ApplyIncomingMobileClipOutcome::DecodeFailed { reason }) => {
                let _ = stream.write_all(&response("400 Bad Request", "text/plain", reason.as_bytes())).await;
                return;
            }
            Ok(_) => {}
        }
        let pending = if data_name.is_empty() {
            None
        } else {
            lock(&shared.pending_uploads).remove(&data_name)
        };
        let (mime_type, data) = match pending {
            Some(upload) => (upload.mime_type, upload.data),
            None => ("text/plain; charset=utf-8".to_string(), text.as_bytes().to_vec()),
        };
        let content_id: String = uc_content_hash::snapshot_hash_single_payload(&data);
        shared.publish(Snapshot {
            available: true,
            wire_type,
            text: text.clone(),
            data_name: data_name.clone(),
            mime_type: mime_type.clone(),
            hash: uc_mobile_proto::sha256_hex_upper(&data),
            content_id: content_id.clone(),
            data: data.clone(),
        });
        shared.enqueue(MobileServerInboundEvent {
            kind: wire_type.as_str().to_string(),
            text,
            data_name,
            mime_type,
            data,
            content_id: content_id.clone(),
            source_label: authenticated.device.label,
        });
        let body: String = format!("{{\"contentId\":\"{}\"}}", json_escape(&content_id));
        let _ = stream.write_all(&response("200 OK", "application/json; charset=utf-8", body.as_bytes())).await;
        return;
    }
    if let Some(data_name_raw) = request.path.strip_prefix("/file/") {
        let data_name: String = percent_decode(data_name_raw);
        if request.method == "GET" {
            let snapshot = lock(&shared.snapshot).clone();
            if snapshot.available && snapshot.data_name == data_name && !snapshot.data.is_empty() {
                let _ = stream.write_all(&response("200 OK", &snapshot.mime_type, &snapshot.data)).await;
                return;
            }
            if let Some(facade) = app_facade.mobile_sync.get().cloned() {
                if let Ok(file) = facade.get_clipboard_file(&data_name).await {
                    let _ = stream.write_all(&response("200 OK", &file.mime, &file.bytes)).await;
                    return;
                }
            }
            let _ = stream.write_all(&response("404 Not Found", "text/plain", b"not found")).await;
            return;
        }
        if request.method == "PUT" {
            if request.body.len() > MAX_UPLOAD_BYTES {
                let _ = stream.write_all(&response("413 Payload Too Large", "text/plain", b"payload too large")).await;
                return;
            }
            let Some(facade) = app_facade.mobile_sync.get().cloned() else {
                let _ = stream.write_all(&response("503 Service Unavailable", "text/plain", b"mobile sync unavailable")).await;
                return;
            };
            let transfer_id: String = format!("mobile-lan:harmony:{}", TRANSFER_SEQUENCE.fetch_add(1, Ordering::Relaxed));
            if facade.put_clipboard_file(
                data_name.clone(), request.content_type.clone(), request.body.clone(),
                authenticated.device.device_id, transfer_id,
            ).await.is_err() {
                let _ = stream.write_all(&response("500 Internal Server Error", "text/plain", b"file upload failed")).await;
                return;
            }
            lock(&shared.pending_uploads).insert(data_name, PendingUpload {
                mime_type: request.content_type,
                data: request.body,
            });
            let _ = stream.write_all(&response("200 OK", "text/plain", b"ok")).await;
            return;
        }
    }
    let _ = stream.write_all(&response("404 Not Found", "text/plain", b"not found")).await;
}

fn format_snapshot_json(snapshot: &Snapshot) -> String {
    let data_name: String = if snapshot.data_name.is_empty() {
        "null".to_string()
    } else {
        format!("\"{}\"", json_escape(&snapshot.data_name))
    };
    format!(
        "{{\"type\":\"{}\",\"text\":\"{}\",\"dataName\":{},\"hasData\":{},\"size\":{},\"hash\":\"{}\",\"contentId\":\"{}\"}}",
        snapshot.wire_type.as_str(), json_escape(&snapshot.text), data_name,
        !snapshot.data_name.is_empty(), snapshot.data.len(), json_escape(&snapshot.hash),
        json_escape(&snapshot.content_id)
    )
}

fn format_sync_meta_json(meta: &uc_application::facade::SyncClipboardMeta) -> String {
    let item_type: &str = match meta.item_type {
        SyncClipboardItemType::Text => "Text",
        SyncClipboardItemType::Image => "Image",
        SyncClipboardItemType::File => "File",
        SyncClipboardItemType::Group => "Group",
    };
    let data_name: String = match meta.data_name.as_ref() {
        Some(value) => format!("\"{}\"", json_escape(value)),
        None => "null".to_string(),
    };
    let hash: String = match meta.hash.as_ref() {
        Some(value) => format!("\"{}\"", json_escape(value)),
        None => "null".to_string(),
    };
    let content_id: String = match meta.content_id.as_ref() {
        Some(value) => format!("\"{}\"", json_escape(value)),
        None => "null".to_string(),
    };
    format!(
        "{{\"type\":\"{}\",\"hash\":{},\"contentId\":{},\"text\":\"{}\",\"hasData\":{},\"dataName\":{},\"size\":{}}}",
        item_type,
        hash,
        content_id,
        json_escape(&meta.text),
        meta.has_data,
        data_name,
        meta.size
    )
}

pub(crate) async fn start(app_facade: Arc<AppFacade>, port: u16) -> Result<(), String> {
    if port == 0 {
        return Err("mobile sync port must be greater than zero".to_string());
    }
    if SERVER_PORT.load(Ordering::Acquire) == port && lock(task_slot()).is_some() {
        return Ok(());
    }
    stop();
    let listener: TcpListener = TcpListener::bind(("0.0.0.0", port))
        .await
        .map_err(|error| format!("failed to listen on port {port}: {error}"))?;
    let shared: Arc<MobileServerState> = shared_state();
    let task = tokio::spawn(async move {
        loop {
            let accepted = listener.accept().await;
            let Ok((stream, _)) = accepted else {
                break;
            };
            let facade: Arc<AppFacade> = app_facade.clone();
            let state: Arc<MobileServerState> = shared.clone();
            tokio::spawn(async move {
                handle_request(stream, facade, state).await;
            });
        }
        SERVER_PORT.store(0, Ordering::Release);
    });
    *lock(task_slot()) = Some(task);
    SERVER_PORT.store(port, Ordering::Release);
    Ok(())
}

pub(crate) fn stop() {
    let previous = lock(task_slot()).take();
    if let Some(task) = previous {
        task.abort();
    }
    lock(&shared_state().device_activity).clear();
    SERVER_PORT.store(0, Ordering::Release);
}

pub(crate) fn running_port() -> u16 {
    SERVER_PORT.load(Ordering::Acquire)
}

pub(crate) fn device_last_activity_ms(device_id: &str) -> u64 {
    shared_state().device_last_activity_ms(device_id)
}

pub(crate) fn is_device_online(device_id: &str) -> bool {
    if running_port() == 0 {
        return false;
    }
    let last_activity: u64 = device_last_activity_ms(device_id);
    last_activity > 0 && now_ms().saturating_sub(last_activity) <= ONLINE_TTL_MS
}

pub(crate) fn publish_text(text: String) -> String {
    let data: Vec<u8> = text.as_bytes().to_vec();
    let content_id: String = uc_content_hash::snapshot_hash_single_payload(&data);
    shared_state().publish(Snapshot {
        available: true,
        wire_type: WireType::Text,
        text,
        data_name: String::new(),
        mime_type: "text/plain; charset=utf-8".to_string(),
        hash: uc_mobile_proto::sha256_hex_upper(&data),
        content_id: content_id.clone(),
        data,
    });
    content_id
}

pub(crate) fn publish_data(
    item_type: &str,
    text: String,
    data_name: String,
    mime_type: String,
    data: Vec<u8>,
) -> String {
    let wire_type: WireType = if item_type.eq_ignore_ascii_case("image") {
        WireType::Image
    } else {
        WireType::File
    };
    let content_id: String = uc_content_hash::snapshot_hash_single_payload(&data);
    shared_state().publish(Snapshot {
        available: true,
        wire_type,
        text,
        data_name,
        mime_type,
        hash: uc_mobile_proto::sha256_hex_upper(&data),
        content_id: content_id.clone(),
        data,
    });
    content_id
}

pub(crate) fn drain_events() -> Vec<MobileServerInboundEvent> {
    lock(&shared_state().inbound_events).drain(..).collect()
}
