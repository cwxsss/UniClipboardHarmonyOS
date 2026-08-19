import { LengthMetrics, UIContext, mediaquery, SymbolGlyphModifier, window } from '@kit.ArkUI';
import {
  abilityAccessCtrl,
  bundleManager,
  common,
  ConfigurationConstant,
  PermissionRequestResult,
  Permissions
} from '@kit.AbilityKit';
import { BusinessError, deviceInfo, pasteboard } from '@kit.BasicServicesKit';
import { connection } from '@kit.NetworkKit';
import { detectBarcode, scanBarcode, scanCore } from '@kit.ScanKit';
import { textRecognition } from '@kit.CoreVisionKit';
import { image } from '@kit.ImageKit';
import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { call } from '@kit.TelephonyKit';
import { filePreview } from '@kit.PreviewKit';
import { harmonyShare, systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import {
  hdsMaterial,
  HdsNavDestination,
  HdsNavDestinationTitleMode,
  HdsNavigation,
  HdsNavigationTitleMode,
  HdsTabs,
  IconStyleMode,
  ScrollEffectType
} from '@kit.UIDesignKit';
import {
  ClipboardHistoryItem,
  LinkPreview,
  ServerConfig,
  ServerHistoryItem,
  SyncContent,
  SyncEvent,
  ClipboardFilePayload,
  ClipboardFileSelection,
  ClipboardService,
  APPEARANCE_MODE_DARK,
  APPEARANCE_MODE_LIGHT,
  APPEARANCE_MODE_SYSTEM,
  APPEARANCE_THEME_DEFAULT,
  AppearanceVisualSettings,
  AppearanceStorageService,
  ConfigStorageService,
  BackgroundSyncPreferenceService,
  HistoryStorageService,
  HistoryLibrarySettings,
  LinkPreviewService,
  Logger,
  EngineVersionService,
  engineRuntimeService,
  EngineInvitationIssued,
  EngineActiveClipboard,
  EngineSendReport,
  EngineSpaceCreated,
  EngineSpaceJoined,
  EngineRuntimeDevice,
  EngineRuntimeEvent,
  EngineRuntimeEventObserver,
  EngineRuntimeState,
  EngineSessionRecovery,
  MobileSyncClient,
  MobileSyncServerService,
  NativeProtocolService,
  ReceivedNotificationService,
  SpaceNodeService,
  NativeSpaceMemberSyncPreferences,
  NativeMobileSyncCredential,
  NativeMobileSyncDevice,
  NativeMobileSyncInboundEvent,
  NativeMobileSyncStatus
} from 'common';

import { HistoryDataSource } from './HistoryDataSource';

const logger: Logger = new Logger('ClipboardFeature');

const POLL_INTERVAL_BASE_MS: number = 1000;
const POLL_INTERVAL_RELAXED_MS: number = 2000;
const POLL_INTERVAL_SLOW_MS: number = 5000;
const POLL_IDLE_RELAXED_ROUNDS: number = 30;
const POLL_IDLE_SLOW_ROUNDS: number = 120;
const OFFICIAL_ENGINE_ENTRY_RETRY_DELAY_MS: number = 1000;
const OFFICIAL_ENGINE_ENTRY_MAX_RETRIES: number = 5;
const APPEARANCE_BACKGROUND_IMAGE_STORAGE_KEY: string = 'appearanceBackgroundImage';
const APPEARANCE_BACKGROUND_OPACITY_STORAGE_KEY: string = 'appearanceBackgroundOpacity';
const APPEARANCE_BACKGROUND_BLUR_STORAGE_KEY: string = 'appearanceBackgroundBlur';
const APPEARANCE_COMPONENT_MATERIAL_STYLE_STORAGE_KEY: string = 'appearanceComponentMaterialStyle';

export class AudioLyricLine {
  timeMs: number = 0;
  text: string = '';

  constructor(timeMs: number, text: string) {
    this.timeMs = timeMs;
    this.text = text;
  }
}

export class AppearanceThemeOption {
  id: string = '';
  primaryColor: string = '';
  secondaryColor: string = '';

  constructor(id: string, primaryColor: string, secondaryColor: string) {
    this.id = id;
    this.primaryColor = primaryColor;
    this.secondaryColor = secondaryColor;
  }
}

export class ImageSmartAction {
  kind: string = '';
  value: string = '';

  constructor(kind: string, value: string) {
    this.kind = kind;
    this.value = value;
  }
}

export const APPEARANCE_THEME_OPTIONS: AppearanceThemeOption[] = [
  new AppearanceThemeOption(APPEARANCE_THEME_DEFAULT, '#0A59F7', '#317AF7'),
  new AppearanceThemeOption('sky_cyan', '#3EB4F8', '#5DEAB5'),
  new AppearanceThemeOption('aurora_green', '#5DEAB5', '#AF64EE'),
  new AppearanceThemeOption('nebula_purple', '#AF64EE', '#FB638D'),
  new AppearanceThemeOption('sunset_orange', '#F99844', '#FFE345'),
  new AppearanceThemeOption('blossom_pink', '#FB638D', '#AF64EE')
];

export const FEEDBACK_EMAIL: string = '3514795319@qq.com';

export class AppErrorRecord {
  timeLabel: string = '';
  source: string = '';
  message: string = '';

  constructor(timeLabel: string, source: string, message: string) {
    this.timeLabel = timeLabel;
    this.source = source;
    this.message = message;
  }
}

const MAX_RECENT_ERRORS: number = 20;

class HistoryFilterCache {
  serverItems: ServerHistoryItem[] = [];
  serverSource: ServerHistoryItem[] | null = null;
  serverSignature: string = '';
  sessionItems: ClipboardHistoryItem[] = [];
  sessionSource: ClipboardHistoryItem[] | null = null;
  sessionSignature: string = '';
  compactItems: ClipboardHistoryItem[] = [];
  compactSource: ClipboardHistoryItem[] | null = null;
  compactSignature: string = '';
}

const historyFilterCache: HistoryFilterCache = new HistoryFilterCache();


@Observed
export class ClipboardFeatureController implements EngineRuntimeEventObserver {
  private static instance: ClipboardFeatureController | null = null;
  public avoidAreaRectHeight: number = 0;
  public navigationRectHeight: number = 0;
  public selectedTab: number = 0;
  public isWideScreen: boolean = false;
  public isLargeScreen: boolean = false;
  public statusCode: number = 0;
  public engineVersion: string = EngineVersionService.getVersion();
  public recentErrors: AppErrorRecord[] = [];
  private serverHistoryDataSourceInstance: HistoryDataSource<ServerHistoryItem> =
    new HistoryDataSource<ServerHistoryItem>();
  private sessionHistoryDataSourceInstance: HistoryDataSource<ClipboardHistoryItem> =
    new HistoryDataSource<ClipboardHistoryItem>();
  public busy: boolean = false;
  public serverUrl: string = '';
  public username: string = '';
  public password: string = '';
  public connectUri: string = '';
  public connectUriState: number = 0;
  public legacyConnectionExpanded: boolean = false;
  public composerText: string = '';
  public latestText: string = '';
  public latestKind: string = 'Text';
  public latestImage: image.PixelMap | null = null;
  public latestImageRevision: number = 0;
  public composerImage: image.PixelMap | null = null;
  public composerImageRevision: number = 0;
  public imageReadState: number = 0;
  public imageSendState: number = 0;
  public composerFileName: string = '';
  public latestFileName: string = '';
  public latestFileRevision: number = 0;
  public fileTransferState: number = 0;
  public latestContentId: string = '';
  public linkPreview: LinkPreview | null = null;
  public linkPreviewState: number = 0;
  public history: ClipboardHistoryItem[] = [];
  // Explicit observable revision for ArkUI list/data-source rebuilds.
  public historyRevision: number = 0;
  public serverHistory: ServerHistoryItem[] = [];
  public historyPage: number = 1;
  public historyEnd: boolean = false;
  public historyLoading: boolean = false;
  public historySearchText: string = '';
  public historyStarredOnly: boolean = false;
  public historyMutationBusy: boolean = false;
  public historyRetentionDays: number = 30;
  public historyMergeDuplicates: boolean = true;
  public historyDeviceFilter: string = '';
  public historySnippetOnly: boolean = false;
  public historySelectionMode: boolean = false;
  public historySelectedIds: string[] = [];
  public desktopRefreshBusy: boolean = false;
  public realtimeActive: boolean = false;
  public feedbackText: string = '';
  public aboutMaterialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.SMOOTH;
  public spaceNodeState: number = 0;
  public spaceJoined: boolean = false;
  public spacePeerConnected: boolean = false;
  public spaceDevices: EngineRuntimeDevice[] = [];
  public spaceDeviceName: string = '';
  public spaceInvitationCode: string = '';
  public spacePassphrase: string = '';
  public spaceJoinDeviceName: string = '';
  public spaceJoinBusy: boolean = false;
  public spaceJoinState: number = 0;
  // 0 means no migration report, 1 means records migrated, and 2 means
  // unreadable records were preserved for manual follow-up.
  public spaceMigrationState: number = 0;
  public spaceSwitchOpen: boolean = false;
  public spaceActionMode: number = 0;
  public spaceCreateDeviceName: string = '';
  public spaceCreateDeviceNameRecommended: boolean = false;
  public spaceCreatePassphrase: string = '';
  public spaceCreatePassphraseConfirm: string = '';
  public spaceCreateBusy: boolean = false;
  public spaceCreateState: number = 0;
  public spaceCreatedId: string = '';
  public spaceIssuedInvitationCode: string = '';
  public spaceInvitationExpiresAtMs: number = 0;
  public spaceInvitationScanState: number = 0;
  public spaceInvitationBusy: boolean = false;
  public mobileInvitationOpen: boolean = false;
  public spaceConnectBusy: boolean = false;
  public spaceConnectingDeviceId: string = '';
  public spaceConnectState: number = 0;
  public spaceRelayFallbackEnabled: boolean = true;
  public spaceRelayUrlsText: string = '';
  public spaceRelaySettingsBusy: boolean = false;
  public spaceRelaySettingsState: number = 0;
  public connectionDiagnosticBusy: boolean = false;
  public connectionDiagnosticExportState: number = 0;
  public connectionDiagnosticDirectCount: number = 0;
  public connectionDiagnosticRelayCount: number = 0;
  public connectionDiagnosticUnknownCount: number = 0;
  public connectionDiagnosticOfflineCount: number = 0;
  public connectionDiagnosticLatencyMs: number = -1;
  public connectionDiagnosticNetworkType: string = 'unknown';
  public connectionDiagnosticLastFailure: string = 'none';
  public connectionDiagnosticLastFailureAtMs: number = 0;
  public connectionDiagnosticInternetGranted: boolean = false;
  public connectionDiagnosticBackgroundGranted: boolean = false;
  public largeSection: number = 0;
  public largeSettingsSection: number = 0;
  public desktopSelectedId: string = '';
  public desktopSelectedText: string = '';
  public desktopSelectedMeta: string = '';
  public desktopSelectedDirection: string = '';
  public desktopSelectedImage: image.PixelMap | null = null;
  public desktopSelectedImageRevision: number = 0;
  public imageRecognitionState: number = 0;
  public imageRecognitionSourceKey: string = '';
  public imageRecognizedText: string = '';
  public imageSmartActions: ImageSmartAction[] = [];
  public desktopFilePreviewState: number = 0;
  public desktopVideoAspectRatio: number = 16 / 9;
  public desktopAudioState: number = 0;
  public desktopAudioPosition: number = 0;
  public desktopAudioDuration: number = 0;
  public desktopAudioSeeking: boolean = false;
  public desktopAudioCover: image.PixelMap | null = null;
  public desktopAudioCoverRevision: number = 0;
  public desktopAudioTitle: string = '';
  public desktopAudioArtist: string = '';
  public desktopAudioAlbum: string = '';
  public desktopAudioLyrics: AudioLyricLine[] = [];
  public desktopAudioPlainLyrics: string = '';
  public desktopAudioMetadataState: number = 0;
  public desktopGestureShareState: number = 0;
  public desktopGestureShareHintDismissed: boolean = false;
  public desktopStarredOnly: boolean = false;
  public desktopTypeFilter: number = 0;
  public desktopTagFilter: number = 0;
  public desktopSourceFilter: number = 0;
  public desktopTimeFilter: number = 0;
  public desktopExtensionFilter: string = '';
  public desktopCustomTagFilter: string = '';
  public appearanceMode: string = APPEARANCE_MODE_SYSTEM;
  public appearanceThemeId: string = APPEARANCE_THEME_DEFAULT;
  public appearanceBackgroundImage: string = '';
  public appearanceBackgroundOpacity: number = 0.4;
  public appearanceBackgroundBlur: number = 8;
  public appearanceMaterialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.ADAPTIVE;
  public appearanceComponentMaterialStyle: number = 2;
  public latestContentPulse: number = 1;
  public historyPulse: number = 1;
  public backgroundSyncEnabled: boolean = false;
  public mobileSyncEnabled: boolean = false;
  public mobileSyncRunning: boolean = false;
  public mobileSyncPort: string = '42720';
  public mobileSyncUrls: string[] = [];
  public mobileSyncDevices: NativeMobileSyncDevice[] = [];
  public mobileSyncBusy: boolean = false;
  public mobileSyncState: number = 0;
  public desktopDeviceMutationBusy: boolean = false;
  public desktopSelectedSpaceDeviceId: string = '';
  public desktopSelectedSpaceDeviceName: string = '';
  public desktopSelectedSpaceDeviceType: string = '';
  public desktopSelectedSpaceDeviceOnline: boolean = false;
  public desktopSelectedSpaceDeviceState: string = 'unknown';
  public desktopSelectedSpaceDeviceIsLocal: boolean = true;
  public desktopDeviceSyncState: number = 0;
  public desktopDeviceSyncSaving: boolean = false;
  public desktopDeviceSendEnabled: boolean = true;
  public desktopDeviceSyncText: boolean = true;
  public desktopDeviceSyncImage: boolean = true;
  public desktopDeviceSyncFile: boolean = true;
  public desktopDeviceSyncLink: boolean = true;
  public desktopDeviceSyncRichText: boolean = true;
  public mobileSyncAddOpen: boolean = false;
  public mobileSyncAdvancedOpen: boolean = false;
  public mobileSyncDeviceName: string = '';
  public mobileSyncCustomUsername: string = '';
  public mobileSyncCustomPassword: string = '';
  public mobileSyncCredential: NativeMobileSyncCredential | null = null;
  public mobileSyncPasswordVisible: boolean = false;

  public clipboardService: ClipboardService = new ClipboardService();
  public appearanceStorageService: AppearanceStorageService = new AppearanceStorageService();
  public configStorageService: ConfigStorageService = new ConfigStorageService();
  public backgroundSyncPreferenceService: BackgroundSyncPreferenceService =
    new BackgroundSyncPreferenceService();
  public historyStorageService: HistoryStorageService = new HistoryStorageService();
  public linkPreviewService: LinkPreviewService = new LinkPreviewService();
  public mobileSyncServerService: MobileSyncServerService = new MobileSyncServerService();
  public receivedNotificationService: ReceivedNotificationService =
    ReceivedNotificationService.getInstance();
  public nativeProtocolService: NativeProtocolService = new NativeProtocolService();
  public spaceNodeService: SpaceNodeService = new SpaceNodeService();
  public largeNavStack: NavPathStack = new NavPathStack();
  public sseTimerId: number = -1;
  private pollingActive: boolean = false;
  private pollIdleRounds: number = 0;
  private pagePollingVisible: boolean = true;
  public historySearchTimerId: number = -1;
  public sseEventBusy: boolean = false;
  public spaceDeviceRefreshBusy: boolean = false;
  private spaceDeviceRefreshQueued: boolean = false;
  public historyResetPending: boolean = false;
  public historyRestoreStarted: boolean = false;
  public historyRestored: boolean = false;
  public historySaveBusy: boolean = false;
  public historySavePending: boolean = false;
  public realtimeTick: number = 0;
  public realtimeAutoConnect: boolean = false;
  public mobileSyncDeviceRefreshBusy: boolean = false;
  public syncScroller: Scroller = new Scroller();
  public devicesScroller: Scroller = new Scroller();
  public settingsScroller: Scroller = new Scroller();
  public aboutScroller: Scroller = new Scroller();
  public configRestored: boolean = false;
  public composerFileData: Uint8Array | null = null;
  public composerFileUri: string = '';
  public composerFileSize: number = 0;
  public composerFileHistoryId: string = '';
  public latestFileData: Uint8Array | null = null;
  public latestFilePath: string = '';
  public latestCachedFilePath: string = '';
  public desktopSelectedFileData: Uint8Array | null = null;
  public desktopSelectedFilePath: string = '';
  public desktopVideoRatioKey: string = '';
  public desktopAudioPlayer: media.AVPlayer | null = null;
  public desktopAudioSourceFile: fileIo.File | null = null;
  public desktopAudioKey: string = '';
  public desktopAudioPlayWhenReady: boolean = false;
  public desktopGestureShareWindowId: number = -1;
  public desktopGestureShareResetTimerId: number = -1;
  public desktopGestureShareRegistering: boolean = false;
  public desktopGestureSharePageVisible: boolean = false;
  public pendingFileTransferId: string = '';
  public linkPreviewRequestId: number = 0;
  private lastOfficialActiveEntryId: string = '';
  private officialEngineInboundRefreshBusy: boolean = false;
  private officialEngineInboundRefreshQueued: boolean = false;
  private officialEngineInboundRefreshRetryCount: number = 0;
  private officialEngineInboundRefreshTimerId: number = -1;

  private uiContextRef: UIContext | null = null;

  public static getInstance(): ClipboardFeatureController {
    if (ClipboardFeatureController.instance === null) {
      ClipboardFeatureController.instance = new ClipboardFeatureController();
    }
    return ClipboardFeatureController.instance as ClipboardFeatureController;
  }

  public getUIContext(): UIContext {
    if (this.uiContextRef === null) {
      throw new Error('ClipboardFeatureController is not attached to a UIContext.');
    }
    return this.uiContextRef;
  }

  public setScreenMode(isWideScreen: boolean, isLargeScreen: boolean): void {
    this.isWideScreen = isWideScreen;
    this.isLargeScreen = isLargeScreen;
    if (!isWideScreen && this.desktopSelectedId.length > 0) {
      this.showLatestClipboardContent();
    }
  }

  public setSpaceJoined(joined: boolean): void {
    this.spaceJoined = joined;
    AppStorage.setOrCreate('spaceJoined', joined);
  }

  public prepareSharedHistory(uiContext: UIContext): void {
    this.uiContextRef = uiContext;
    this.restoreLocalHistory();
  }

  public start(uiContext: UIContext): void {
    this.uiContextRef = uiContext;
    let materialTypes: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes();
    if (materialTypes.indexOf(hdsMaterial.MaterialType.IMMERSIVE) >= 0) {
      this.aboutMaterialLevel = hdsMaterial.MaterialLevel.EXQUISITE;
    }
    this.initializeRecommendedSpaceDeviceName();
    this.selectPage(this.selectedTab);
    if (!this.pollingActive) {
      this.pollingActive = true;
      this.pollIdleRounds = 0;
      this.schedulePollTimer(POLL_INTERVAL_BASE_MS);
    }
    this.restoreConfig();
    this.restoreBackgroundSyncPreference();
    this.restoreAppearanceMode();
    this.restoreAppearanceTheme();
    this.restoreAppearanceVisualSettings();
    this.restoreLocalHistory();
    engineRuntimeService.addEventObserver(this);
    this.initializeSpaceNode();
  }

  public onPageShow(): void {
    this.desktopGestureSharePageVisible = true;
    this.registerDesktopGestureShare();
    this.pagePollingVisible = true;
    this.pollIdleRounds = 0;
    if (this.pollingActive && this.sseTimerId >= 0) {
      clearTimeout(this.sseTimerId);
      this.sseTimerId = -1;
      this.schedulePollTimer(0);
    }
  }

  public onPageHide(): void {
    this.desktopGestureSharePageVisible = false;
    this.unregisterDesktopGestureShare();
    this.pagePollingVisible = false;
  }

  public stop(): void {
    engineRuntimeService.removeEventObserver(this);
    this.pollingActive = false;
    if (this.officialEngineInboundRefreshTimerId >= 0) {
      clearTimeout(this.officialEngineInboundRefreshTimerId);
      this.officialEngineInboundRefreshTimerId = -1;
    }
    this.officialEngineInboundRefreshBusy = false;
    this.officialEngineInboundRefreshQueued = false;
    this.officialEngineInboundRefreshRetryCount = 0;
    if (this.sseTimerId >= 0) {
      clearTimeout(this.sseTimerId);
      this.sseTimerId = -1;
    }
    if (this.historySearchTimerId >= 0) {
      clearTimeout(this.historySearchTimerId);
      this.historySearchTimerId = -1;
    }
    let client: MobileSyncClient = new MobileSyncClient(this.getConfig());
    client.stopRealtime();
    this.realtimeActive = false;
    this.desktopGestureSharePageVisible = false;
    this.unregisterDesktopGestureShare();
    this.releaseDesktopAudio();
    this.removeLatestCachedFile();
    let context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context !== undefined && this.composerFileHistoryId.length > 0 && this.composerFileUri.length > 0) {
      this.historyStorageService.discardManagedFile(context, this.composerFileUri);
      this.composerFileHistoryId = '';
      this.composerFileUri = '';
    }
    this.uiContextRef = null;
  }

  private schedulePollTimer(delayMs: number): void {
    if (!this.pollingActive) {
      return;
    }
    this.sseTimerId = setTimeout(() => {
      this.pollRealtimeOnce();
    }, delayMs);
  }

  private async pollRealtimeOnce(): Promise<void> {
    this.sseTimerId = -1;
    let activityCount: number = 0;
    try {
      activityCount = await this.consumeRealtimeEvents();
    } finally {
      this.schedulePollTimer(this.nextPollDelayMs(activityCount));
    }
  }

  private nextPollDelayMs(activityCount: number): number {
    if (activityCount > 0) {
      this.pollIdleRounds = 0;
    } else {
      this.pollIdleRounds += 1;
    }
    if (!this.pagePollingVisible) {
      return this.backgroundSyncEnabled ? POLL_INTERVAL_RELAXED_MS : POLL_INTERVAL_SLOW_MS;
    }
    if (this.pollIdleRounds >= POLL_IDLE_SLOW_ROUNDS) {
      return POLL_INTERVAL_SLOW_MS;
    }
    if (this.pollIdleRounds >= POLL_IDLE_RELAXED_ROUNDS) {
      return POLL_INTERVAL_RELAXED_MS;
    }
    return POLL_INTERVAL_BASE_MS;
  }

  public showLatestClipboardContent(): void {
    this.desktopSelectedId = '';
    this.desktopSelectedText = '';
    this.desktopSelectedMeta = '';
    this.desktopSelectedDirection = '';
    this.desktopGestureShareHintDismissed = false;
    this.desktopSelectedImage = null;
    this.desktopSelectedFileData = null;
    this.desktopSelectedFilePath = '';
    this.desktopFilePreviewState = 0;
    this.resetDesktopVideoAspectRatio();
    this.releaseDesktopAudio();
    this.refreshCurrentLinkPreview();
  }

  public getConfig(): ServerConfig {
    let config: ServerConfig = {
      baseUrl: this.serverUrl,
      username: this.username,
      password: this.password
    };
    return config;
  }

  public restoreConfig(): void {
    if (this.configRestored) {
      return;
    }
    this.configRestored = true;
    try {
      let context: common.Context | undefined = this.getUIContext().getHostContext();
      if (context === undefined) {
        return;
      }
      let config: ServerConfig = this.configStorageService.load(context);
      this.serverUrl = config.baseUrl;
      this.username = config.username;
      this.password = config.password;
      this.legacyConnectionExpanded = this.hasConfig();
      if (this.hasConfig() && !this.spaceJoined) {
        this.realtimeAutoConnect = true;
        this.startRealtime();
      }
    } catch (error) {
      this.statusCode = 3;
    }
  }

  public saveConfig(): void {
    let context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    this.configStorageService.save(context, this.getConfig());
  }

  public restoreBackgroundSyncPreference(): void {
    let context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    this.backgroundSyncEnabled = this.backgroundSyncPreferenceService.load(context);
    AppStorage.setOrCreate('backgroundSyncEnabled', this.backgroundSyncEnabled);
  }

  public setBackgroundSyncEnabled(enabled: boolean): void {
    this.backgroundSyncEnabled = enabled;
    AppStorage.setOrCreate('backgroundSyncEnabled', enabled);
    let context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context !== undefined) {
      this.backgroundSyncPreferenceService.save(context, enabled);
    }
  }

  public restoreAppearanceMode(): void {
    let context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    this.appearanceMode = this.appearanceStorageService.load(context);
  }

  public restoreAppearanceTheme(): void {
    let context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    let storedThemeId: string = this.appearanceStorageService.loadTheme(context);
    this.appearanceThemeId = this.getAppearanceTheme(storedThemeId).id;
  }

  public restoreAppearanceVisualSettings(): void {
    let context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    let settings: AppearanceVisualSettings = this.appearanceStorageService.loadVisualSettings(context);
    this.appearanceBackgroundImage = settings.backgroundImage;
    this.appearanceBackgroundOpacity = settings.backgroundOpacity;
    this.appearanceBackgroundBlur = settings.backgroundBlur;
    this.appearanceMaterialLevel = this.resolveAppearanceMaterialLevel(settings.materialLevel);
    this.appearanceComponentMaterialStyle = settings.componentMaterialStyle;
    this.syncAppearanceBackgroundAppStorage();
    AppStorage.setOrCreate(APPEARANCE_COMPONENT_MATERIAL_STYLE_STORAGE_KEY,
      this.appearanceComponentMaterialStyle);
  }

  private syncAppearanceBackgroundAppStorage(): void {
    AppStorage.setOrCreate(APPEARANCE_BACKGROUND_IMAGE_STORAGE_KEY, this.appearanceBackgroundImage);
    AppStorage.setOrCreate(APPEARANCE_BACKGROUND_OPACITY_STORAGE_KEY, this.appearanceBackgroundOpacity);
    AppStorage.setOrCreate(APPEARANCE_BACKGROUND_BLUR_STORAGE_KEY, this.appearanceBackgroundBlur);
  }

  private resolveAppearanceMaterialLevel(level: number): hdsMaterial.MaterialLevel {
    if (level === hdsMaterial.MaterialLevel.EXQUISITE) {
      return hdsMaterial.MaterialLevel.EXQUISITE;
    }
    if (level === hdsMaterial.MaterialLevel.GENTLE) {
      return hdsMaterial.MaterialLevel.GENTLE;
    }
    if (level === hdsMaterial.MaterialLevel.SMOOTH) {
      return hdsMaterial.MaterialLevel.SMOOTH;
    }
    return hdsMaterial.MaterialLevel.ADAPTIVE;
  }

  public persistAppearanceVisualSettings(): void {
    let context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    let settings: AppearanceVisualSettings = new AppearanceVisualSettings(
      this.appearanceBackgroundImage,
      this.appearanceBackgroundOpacity,
      this.appearanceBackgroundBlur,
      this.appearanceMaterialLevel,
      this.appearanceComponentMaterialStyle
    );
    this.appearanceStorageService.saveVisualSettings(context, settings);
  }

  public async selectAppearanceBackgroundImage(): Promise<void> {
    try {
      let options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      let photoPicker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      let result: photoAccessHelper.PhotoSelectResult = await photoPicker.select(options);
      if (result.photoUris.length > 0) {
        this.appearanceBackgroundImage = result.photoUris[0];
        this.syncAppearanceBackgroundAppStorage();
        this.persistAppearanceVisualSettings();
        this.showFeedbackToast($r('app.string.appearance_background_applied'));
      }
    } catch (error) {
      logger.error('UniClipboard failed to select an appearance background image.');
      this.showFeedbackToast($r('app.string.appearance_background_failed'));
    }
  }

  public clearAppearanceBackgroundImage(): void {
    this.appearanceBackgroundImage = '';
    this.appearanceBackgroundOpacity = 0.4;
    this.appearanceBackgroundBlur = 8;
    this.syncAppearanceBackgroundAppStorage();
    this.persistAppearanceVisualSettings();
    this.showFeedbackToast($r('app.string.appearance_background_cleared'));
  }

  public selectAppearanceMaterialLevel(level: hdsMaterial.MaterialLevel): void {
    this.appearanceMaterialLevel = level;
    this.persistAppearanceVisualSettings();
  }

  public appearanceComponentMaterialIndex(): number {
    return this.appearanceComponentMaterialStyle + 1;
  }

  public selectAppearanceComponentMaterialByIndex(index: number): void {
    if (index <= 0) {
      this.appearanceComponentMaterialStyle = -1;
    } else if (index >= 5) {
      this.appearanceComponentMaterialStyle = 4;
    } else {
      this.appearanceComponentMaterialStyle = index - 1;
    }
    AppStorage.setOrCreate(APPEARANCE_COMPONENT_MATERIAL_STYLE_STORAGE_KEY,
      this.appearanceComponentMaterialStyle);
    this.persistAppearanceVisualSettings();
  }

  public appearanceComponentMaterialLabel(): Resource {
    if (this.appearanceComponentMaterialStyle < 0) {
      return $r('app.string.appearance_component_material_off');
    }
    if (this.appearanceComponentMaterialStyle === 0) {
      return $r('app.string.appearance_component_material_ultra_thin');
    }
    if (this.appearanceComponentMaterialStyle === 1) {
      return $r('app.string.appearance_component_material_thin');
    }
    if (this.appearanceComponentMaterialStyle === 3) {
      return $r('app.string.appearance_component_material_thick');
    }
    if (this.appearanceComponentMaterialStyle === 4) {
      return $r('app.string.appearance_component_material_ultra_thick');
    }
    return $r('app.string.appearance_component_material_regular');
  }

  public updateAppearanceBackgroundOpacity(value: number, persist: boolean): void {
    this.appearanceBackgroundOpacity = value;
    AppStorage.setOrCreate(APPEARANCE_BACKGROUND_OPACITY_STORAGE_KEY, value);
    if (persist) {
      this.persistAppearanceVisualSettings();
    }
  }

  public updateAppearanceBackgroundBlur(value: number, persist: boolean): void {
    this.appearanceBackgroundBlur = value;
    AppStorage.setOrCreate(APPEARANCE_BACKGROUND_BLUR_STORAGE_KEY, value);
    if (persist) {
      this.persistAppearanceVisualSettings();
    }
  }

  public appearanceMaterialLevelIndex(): number {
    if (this.appearanceMaterialLevel === hdsMaterial.MaterialLevel.EXQUISITE) {
      return 0;
    }
    if (this.appearanceMaterialLevel === hdsMaterial.MaterialLevel.GENTLE) {
      return 1;
    }
    if (this.appearanceMaterialLevel === hdsMaterial.MaterialLevel.SMOOTH) {
      return 2;
    }
    return 3;
  }

  public selectAppearanceMaterialLevelByIndex(index: number): void {
    if (index === 0) {
      this.selectAppearanceMaterialLevel(hdsMaterial.MaterialLevel.EXQUISITE);
    } else if (index === 1) {
      this.selectAppearanceMaterialLevel(hdsMaterial.MaterialLevel.GENTLE);
    } else if (index === 2) {
      this.selectAppearanceMaterialLevel(hdsMaterial.MaterialLevel.SMOOTH);
    } else {
      this.selectAppearanceMaterialLevel(hdsMaterial.MaterialLevel.ADAPTIVE);
    }
  }

  public pageBackgroundColor(): ResourceColor {
    if (this.appearanceBackgroundImage.length > 0) {
      return Color.Transparent;
    }
    return $r('app.color.page_background');
  }

  public selectAppearanceMode(mode: string): void {
    let context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    try {
      let colorMode: ConfigurationConstant.ColorMode = this.appearanceStorageService.getColorMode(mode);
      context.getApplicationContext().setColorMode(colorMode);
      this.appearanceMode = mode;
      this.appearanceStorageService.save(context, mode);
    } catch (error) {
      logger.error('UniClipboard failed to update the appearance mode.');
    }
  }

  public selectAppearanceTheme(themeId: string): void {
    let theme: AppearanceThemeOption = this.getAppearanceTheme(themeId);
    this.appearanceThemeId = theme.id;
    let context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context !== undefined) {
      this.appearanceStorageService.saveTheme(context, theme.id);
    }
  }

  public getAppearanceTheme(themeId: string): AppearanceThemeOption {
    for (let index: number = 0; index < APPEARANCE_THEME_OPTIONS.length; index++) {
      let option: AppearanceThemeOption = APPEARANCE_THEME_OPTIONS[index];
      if (option.id === themeId) {
        return option;
      }
    }
    return APPEARANCE_THEME_OPTIONS[0];
  }

  public appearanceThemeLabel(themeId: string): Resource {
    if (themeId === 'sky_cyan') {
      return $r('app.string.appearance_theme_sky_cyan');
    }
    if (themeId === 'aurora_green') {
      return $r('app.string.appearance_theme_aurora_green');
    }
    if (themeId === 'nebula_purple') {
      return $r('app.string.appearance_theme_nebula_purple');
    }
    if (themeId === 'sunset_orange') {
      return $r('app.string.appearance_theme_sunset_orange');
    }
    if (themeId === 'blossom_pink') {
      return $r('app.string.appearance_theme_blossom_pink');
    }
    return $r('app.string.appearance_theme_default');
  }

  public accentColor(): ResourceColor {
    if (this.appearanceThemeId === APPEARANCE_THEME_DEFAULT) {
      return $r('app.color.accent');
    }
    return this.getAppearanceTheme(this.appearanceThemeId).primaryColor;
  }

  public accentSecondaryColor(): ResourceColor {
    if (this.appearanceThemeId === APPEARANCE_THEME_DEFAULT) {
      return $r('app.color.accent_secondary');
    }
    return this.getAppearanceTheme(this.appearanceThemeId).secondaryColor;
  }

  public historyMenuSymbol(symbol: Resource): SymbolGlyphModifier {
    let modifier: SymbolGlyphModifier = new SymbolGlyphModifier(symbol);
    modifier.fontSize('20vp');
    modifier.fontColor([this.accentSecondaryColor()]);
    return modifier;
  }

  public historyDeleteMenuSymbol(): SymbolGlyphModifier {
    let modifier: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.xmark'));
    modifier.fontSize('20vp');
    modifier.fontColor([$r('app.color.danger')]);
    return modifier;
  }

  public accentSoftColor(): ResourceColor {
    if (this.appearanceThemeId === APPEARANCE_THEME_DEFAULT) {
      return $r('app.color.accent_soft');
    }
    return '#19' + this.getAppearanceTheme(this.appearanceThemeId).primaryColor.substring(1);
  }

  public accentMediumColor(): ResourceColor {
    if (this.appearanceThemeId === APPEARANCE_THEME_DEFAULT) {
      return $r('app.color.accent_medium');
    }
    return '#33' + this.getAppearanceTheme(this.appearanceThemeId).primaryColor.substring(1);
  }

  public async restoreLocalHistory(): Promise<void> {
    if (this.historyRestoreStarted) {
      return;
    }
    this.historyRestoreStarted = true;
    try {
      let context: common.Context | undefined = this.getUIContext().getHostContext();
      if (context === undefined) {
        return;
      }
      let settings: HistoryLibrarySettings = this.historyStorageService.loadSettings(context);
      this.historyRetentionDays = settings.retentionDays;
      this.historyMergeDuplicates = settings.mergeDuplicates;
      let storedItems: ClipboardHistoryItem[] = await this.historyStorageService.load(context,
        this.historyRetentionDays);
      let mergedItems: ClipboardHistoryItem[] = [];
      let knownIds: Set<string> = new Set<string>();
      for (let index: number = 0; index < this.history.length; index++) {
        let item: ClipboardHistoryItem = this.history[index];
        mergedItems.push(item);
        knownIds.add(item.id);
      }
      for (let index: number = 0; index < storedItems.length; index++) {
        let item: ClipboardHistoryItem = storedItems[index];
        if (!knownIds.has(item.id)) {
          mergedItems.push(item);
          knownIds.add(item.id);
        }
      }
      this.history = this.historyMergeDuplicates ? this.mergeHistoryDuplicates(mergedItems) : mergedItems;
      this.pruneHistoryByRetention();
    } catch (error) {
      this.reportError('history', 'failed to restore local clipboard history: ' + this.errorDetail(error),
        $r('app.string.error_toast_history_restore'));
    } finally {
      this.historyRestored = true;
      if (this.historySavePending) {
        this.historySavePending = false;
        this.scheduleHistorySave();
      } else {
        this.scheduleHistorySave();
      }
    }
  }

  public scheduleHistorySave(): void {
    if (!this.historyRestored || this.historySaveBusy) {
      this.historySavePending = true;
      return;
    }
    this.persistLocalHistory();
  }

  public async persistLocalHistory(): Promise<void> {
    let context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      this.historySavePending = true;
      return;
    }
    let items: ClipboardHistoryItem[] = [];
    for (let index: number = 0; index < this.history.length; index++) {
      items.push(this.history[index]);
    }
    this.historySaveBusy = true;
    try {
      await this.historyStorageService.save(context, items);
    } catch (error) {
      this.reportError('history', 'failed to persist local clipboard history: ' + this.errorDetail(error),
        $r('app.string.error_toast_history_persist'));
    } finally {
      this.historySaveBusy = false;
      if (this.historySavePending) {
        this.historySavePending = false;
        this.scheduleHistorySave();
      }
    }
  }

  public async initializeSpaceNode(): Promise<void> {
    if (this.spaceNodeState === 1 || this.spaceNodeState === 2) {
      return;
    }
    this.spaceNodeState = 1;
    this.spacePeerConnected = false;
    try {
      let context: common.Context | undefined = this.getUIContext().getHostContext();
      if (context === undefined) {
        this.spaceNodeState = 3;
        this.recordConnectionDiagnosticFailure('node_unavailable');
        return;
      }
      await engineRuntimeService.prepare(context as common.UIAbilityContext);
      await engineRuntimeService.start();
      let recovery = await engineRuntimeService.recoverSession(true);
      this.spaceNodeState = 2;
      this.setSpaceJoined(recovery.resumed);
      await this.refreshSpaceNetworkSettings();
      if (this.spaceJoined) {
        await this.refreshSpaceDevices();
      }
      await this.initializeMobileSyncServer();
    } catch (error) {
      this.spaceNodeState = 3;
      this.recordConnectionDiagnosticFailure('node_unavailable');
    }
  }

  public async refreshSpaceNetworkSettings(): Promise<void> {
    this.spaceRelayFallbackEnabled = false;
    this.spaceRelayUrlsText = '';
    this.spaceRelaySettingsState = 0;
  }

  public spaceRelaySettingsChanged(): void {
    this.spaceRelaySettingsState = 0;
  }

  private spaceRelayUrls(): string[] {
    let lines: string[] = this.spaceRelayUrlsText.split('\n');
    let urls: string[] = [];
    for (let index: number = 0; index < lines.length; index++) {
      let url: string = lines[index].trim();
      if (url.length > 0) {
        urls.push(url);
      }
    }
    return urls;
  }

  public async saveSpaceNetworkSettings(): Promise<void> {
    if (this.spaceRelaySettingsBusy) {
      return;
    }
    this.spaceRelaySettingsBusy = true;
    this.spaceRelaySettingsState = 0;
    this.spaceRelayFallbackEnabled = false;
    this.spaceRelayUrlsText = '';
    this.spaceRelaySettingsState = 2;
    this.spaceRelaySettingsBusy = false;
  }

  public async initializeMobileSyncServer(): Promise<void> {
    try {
      let status: NativeMobileSyncStatus = await this.mobileSyncServerService.status();
      this.mobileSyncEnabled = status.enabled;
      this.mobileSyncRunning = status.running;
      this.mobileSyncPort = status.port.toString();
      this.mobileSyncUrls = status.urls;
      await this.refreshMobileSyncDevices();
      if (status.enabled && !status.running) {
        let restarted: NativeMobileSyncStatus = await this.mobileSyncServerService.setEnabled(
          true, this.mobileSyncPortNumber());
        this.mobileSyncRunning = restarted.running;
        this.mobileSyncUrls = restarted.urls;
      }
    } catch (error) {
      this.mobileSyncState = 3;
      this.mobileSyncRunning = false;
    }
  }

  public mobileSyncPortNumber(): number {
    let port: number = parseInt(this.mobileSyncPort.trim(), 10);
    if (isNaN(port) || port < 1 || port > 65535) {
      return 42720;
    }
    return port;
  }

  public async refreshMobileSyncDevices(): Promise<void> {
    if (this.mobileSyncDeviceRefreshBusy) {
      return;
    }
    this.mobileSyncDeviceRefreshBusy = true;
    try {
      this.mobileSyncDevices = await this.mobileSyncServerService.listDevices();
    } catch (error) {
      this.mobileSyncDevices = [];
    } finally {
      this.mobileSyncDeviceRefreshBusy = false;
    }
  }

  public async toggleMobileSyncServer(enabled: boolean): Promise<void> {
    if (this.mobileSyncBusy) {
      return;
    }
    this.mobileSyncBusy = true;
    this.mobileSyncState = 0;
    try {
      let status: NativeMobileSyncStatus = await this.mobileSyncServerService.setEnabled(
        enabled, this.mobileSyncPortNumber());
      this.mobileSyncEnabled = status.enabled;
      this.mobileSyncRunning = status.running;
      this.mobileSyncPort = status.port.toString();
      this.mobileSyncUrls = status.urls;
      if (enabled && !status.running) {
        this.mobileSyncState = 3;
      }
      await this.refreshMobileSyncDevices();
    } catch (error) {
      this.mobileSyncEnabled = false;
      this.mobileSyncRunning = false;
      this.mobileSyncState = 3;
      this.reportError('mobile-sync', 'failed to toggle the mobile sync server: ' + this.errorDetail(error),
        $r('app.string.error_toast_sync'));
    } finally {
      this.mobileSyncBusy = false;
    }
  }

  public async createMobileSyncDevice(): Promise<void> {
    if (this.mobileSyncBusy || this.mobileSyncDeviceName.trim().length === 0) {
      return;
    }
    this.mobileSyncBusy = true;
    this.mobileSyncState = 0;
    this.mobileSyncCredential = null;
    try {
      let credential: NativeMobileSyncCredential = await this.mobileSyncServerService.registerDevice(
        this.mobileSyncDeviceName.trim(), this.mobileSyncCustomUsername.trim(),
        this.mobileSyncCustomPassword, this.mobileSyncPortNumber());
      this.mobileSyncCredential = credential;
      this.mobileSyncEnabled = true;
      this.mobileSyncRunning = true;
      this.mobileSyncUrls = credential.urls;
      await this.refreshMobileSyncDevices();
      this.mobileSyncState = 2;
      this.mobileSyncCustomPassword = '';
    } catch (error) {
      this.mobileSyncState = 3;
      this.reportError('mobile-sync', 'failed to issue mobile sync credentials: ' + this.errorDetail(error));
    } finally {
      this.mobileSyncBusy = false;
    }
  }

  public async revokeMobileSyncDevice(device: NativeMobileSyncDevice): Promise<void> {
    if (this.desktopDeviceMutationBusy || this.mobileSyncBusy) {
      return;
    }
    try {
      let result = await this.getUIContext().getPromptAction().showDialog({
        title: $r('app.string.mobile_sync_revoke_title'),
        message: $r('app.string.mobile_sync_revoke_message'),
        buttons: [
          { text: $r('app.string.cancel_action'), color: $r('app.color.text_secondary') },
          { text: $r('app.string.mobile_sync_revoke_confirm'), color: $r('app.color.danger') }
        ]
      });
      if (result.index !== 1) {
        return;
      }
      this.desktopDeviceMutationBusy = true;
      await this.mobileSyncServerService.revokeDevice(device.deviceId);
      await this.refreshMobileSyncDevices();
      this.statusCode = 2;
    } catch (error) {
      this.mobileSyncState = 3;
      this.statusCode = 3;
    } finally {
      this.desktopDeviceMutationBusy = false;
    }
  }

  public async revokeSpaceDevice(device: EngineRuntimeDevice): Promise<void> {
    if (device.isLocal || this.desktopDeviceMutationBusy || this.spaceConnectBusy ||
      !this.spaceJoined || this.spaceNodeState !== 2) {
      return;
    }
    try {
      let result = await this.getUIContext().getPromptAction().showDialog({
        title: $r('app.string.space_revoke_device_title'),
        message: $r('app.string.space_revoke_device_message'),
        buttons: [
          { text: $r('app.string.cancel_action'), color: $r('app.color.text_secondary') },
          { text: $r('app.string.space_revoke_device_confirm'), color: $r('app.color.danger') }
        ]
      });
      if (result.index !== 1) {
        return;
      }
      this.desktopDeviceMutationBusy = true;
      await engineRuntimeService.removeMember(device.deviceId);
      await this.refreshSpaceDevices();
      this.statusCode = 2;
    } catch (error) {
      this.statusCode = 3;
    } finally {
      this.desktopDeviceMutationBusy = false;
    }
  }

  public async consumeMobileSyncEvents(): Promise<number> {
    let events: NativeMobileSyncInboundEvent[] = this.mobileSyncServerService.drainInboundEvents();
    for (let index: number = 0; index < events.length; index++) {
      let event: NativeMobileSyncInboundEvent = events[index];
      this.latestContentId = event.contentId;
      if (event.kind === 'Text') {
        this.latestText = event.text;
        this.latestKind = 'Text';
        this.latestImage = null;
        if (this.desktopSelectedId.length === 0) {
          this.refreshCurrentLinkPreview();
        }
        this.addHistory(event.text, 'received', 'Text', null, null, '', event.contentId, event.sourceLabel);
        try {
          await this.clipboardService.writeText(event.text);
          this.notifyReceivedContent('Text', event.text, null, 0, event.sourceLabel);
        } catch (error) {
          this.statusCode = 3;
        }
      } else if (event.kind === 'Image') {
        try {
          let pixelMap: image.PixelMap = await this.clipboardService.decodeImage(event.data);
          this.latestImage = pixelMap;
          this.latestImageRevision += 1;
          this.latestKind = 'Image';
          this.latestText = event.dataName.length > 0 ? event.dataName : 'image.png';
          if (this.desktopSelectedId.length === 0) {
            this.clearLinkPreview();
          }
          this.addHistory(this.latestText, 'received', 'Image', pixelMap, null, '', event.contentId,
            event.sourceLabel);
          await this.clipboardService.writeImage(pixelMap);
          this.notifyReceivedContent('Image', this.latestText, pixelMap, event.data.length,
            event.sourceLabel);
        } catch (error) {
          this.statusCode = 3;
        }
      } else if (event.kind === 'File') {
        let fileName: string = event.dataName.length > 0 ? event.dataName : event.text;
        let filePreview: image.PixelMap | null = null;
        if (this.isImageFileName(fileName) && event.data.length > 0) {
          try {
            filePreview = await this.clipboardService.decodeImage(event.data);
          } catch (error) {
            filePreview = null;
          }
        }
        this.latestKind = 'File';
        this.latestText = fileName;
        if (this.desktopSelectedId.length === 0) {
          this.clearLinkPreview();
        }
        this.latestFileName = fileName;
        this.latestFileData = event.data;
        this.latestFilePath = '';
        this.latestFileRevision += 1;
        this.addHistory(fileName, 'received', 'File', null, event.data, '', event.contentId,
          event.sourceLabel);
        this.notifyReceivedContent('File', fileName, filePreview, event.data.length,
          event.sourceLabel);
      }
      this.statusCode = 2;
      this.animateLatestContent();
    }
    if (events.length > 0) {
      await this.refreshMobileSyncDevices();
    }
    return events.length;
  }

  public async initializeRecommendedSpaceDeviceName(): Promise<void> {
    if (this.spaceCreateDeviceName.trim().length > 0) {
      return;
    }
    let recommendedName: string = deviceInfo.marketName.trim();
    if (recommendedName.length === 0) {
      let context: common.Context | undefined = this.getUIContext().getHostContext();
      if (context !== undefined) {
        try {
          if (deviceInfo.deviceType === 'phone') {
            recommendedName = await context.resourceManager.getStringByName('space_device_recommended_phone');
          } else if (deviceInfo.deviceType === 'tablet') {
            recommendedName = await context.resourceManager.getStringByName('space_device_recommended_tablet');
          } else if (deviceInfo.deviceType === '2in1') {
            recommendedName = await context.resourceManager.getStringByName('space_device_recommended_computer');
          } else {
            recommendedName = await context.resourceManager.getStringByName('space_device_recommended_default');
          }
        } catch (error) {
          logger.error('UniClipboard failed to load the recommended device name.');
        }
      }
    }
    if (recommendedName.length > 0) {
      this.spaceCreateDeviceName = recommendedName;
      this.spaceCreateDeviceNameRecommended = true;
    }
  }

  public canJoinSpace(): boolean {
    if (this.spaceNodeState !== 2 || this.spaceJoinBusy ||
      this.spaceInvitationCode.trim().length === 0 || this.spacePassphrase.length === 0) {
      return false;
    }
    if (this.spaceJoined) {
      return this.spaceSwitchOpen;
    }
    return this.spaceJoinDeviceName.trim().length > 0;
  }

  public async joinCurrentSpace(): Promise<void> {
    if (!this.canJoinSpace()) {
      return;
    }
    this.spaceJoinBusy = true;
    this.spaceJoinState = 0;
    try {
      let switching: boolean = this.spaceJoined;
      let deviceName: string = this.spaceJoinDeviceName.trim();
      let requestedDeviceName: string | null = switching ? null : deviceName;
      let result: EngineSpaceJoined = await engineRuntimeService.joinSpace(
        this.spaceInvitationCode.trim(), requestedDeviceName, this.spacePassphrase, true);
      let hasMigratedRecords: boolean = this.hasMigrationRecords(result.migratedRecords);
      let hasPreservedUnreadableRecords: boolean = this.hasMigrationRecords(result.preservedUnreadableRecords);
      this.spaceMigrationState = hasPreservedUnreadableRecords ? 2 : (hasMigratedRecords ? 1 : 0);
      this.setSpaceJoined(result.spaceId.length > 0);
      this.spacePeerConnected = false;
      if (!switching) {
        this.spaceDeviceName = deviceName;
      }
      this.spaceCreatedId = result.spaceId;
      this.spaceCreatePassphrase = this.spacePassphrase;
      this.spaceInvitationCode = '';
      this.spacePassphrase = '';
      this.spaceJoinDeviceName = '';
      this.spaceJoinState = 1;
      if (hasPreservedUnreadableRecords) {
        this.reportError('space', 'Engine preserved unreadable records during space migration.',
          $r('app.string.space_migration_preserved_warning'));
      } else if (hasMigratedRecords) {
        this.showFeedbackToast($r('app.string.space_migration_success'));
      }
      await this.refreshSpaceDevices();
      if (switching) {
        this.spaceSwitchOpen = false;
      }
    } catch (error) {
      let errorMessage: string = 'unavailable';
      if (error instanceof Error) {
        let joinError: Error = error as Error;
        errorMessage = joinError.message;
      }
      this.reportError('space', 'join space failed: ' + errorMessage);
      this.spaceJoinState = 2;
    } finally {
      this.spaceJoinBusy = false;
    }
  }

  public canCreateSpace(): boolean {
    return this.spaceNodeState === 2 && (!this.spaceJoined || this.spaceSwitchOpen) && !this.spaceCreateBusy &&
      this.spaceCreateDeviceName.trim().length > 0 && this.spaceCreatePassphrase.length >= 8 &&
      this.spaceCreatePassphrase === this.spaceCreatePassphraseConfirm;
  }

  public async confirmReplaceCurrentSpace(): Promise<boolean> {
    try {
      let result = await this.getUIContext().getPromptAction().showDialog({
        title: $r('app.string.space_replace_confirm_title'),
        message: $r('app.string.space_replace_confirm_message'),
        buttons: [
          { text: $r('app.string.cancel_action'), color: $r('app.color.text_secondary') },
          { text: $r('app.string.space_replace_confirm_action'), color: $r('app.color.danger') }
        ]
      });
      return result.index === 1;
    } catch (error) {
      return false;
    }
  }

  public async createCurrentSpace(): Promise<void> {
    if (!this.canCreateSpace()) {
      return;
    }
    let replacing: boolean = this.spaceJoined;
    if (replacing) {
      let confirmed: boolean = await this.confirmReplaceCurrentSpace();
      if (!confirmed) {
        return;
      }
    }
    this.spaceCreateBusy = true;
    this.spaceCreateState = 0;
    try {
      let deviceName: string = this.spaceCreateDeviceName.trim();
      let result: EngineSpaceCreated = await engineRuntimeService.createSpace(
        deviceName, this.spaceCreatePassphrase);
      this.setSpaceJoined(result.spaceId.length > 0);
      this.spacePeerConnected = false;
      this.spaceCreatedId = result.spaceId;
      this.spaceDeviceName = deviceName;
      this.spaceDevices = [];
      this.spaceCreatePassphraseConfirm = '';
      this.spaceCreateState = 1;
      await this.refreshSpaceDevices();
      if (replacing) {
        this.spaceSwitchOpen = false;
      }
    } catch (error) {
      this.spaceCreateState = 2;
    } finally {
      this.spaceCreateBusy = false;
    }
  }

  public async issueCurrentSpaceInvitation(): Promise<void> {
    if (!this.canIssueSpaceInvitation()) {
      return;
    }
    this.spaceInvitationBusy = true;
    try {
      let invitation: EngineInvitationIssued = await engineRuntimeService.issueInvitation();
      this.spaceIssuedInvitationCode = invitation.invitationCode;
      this.spaceInvitationExpiresAtMs = invitation.expiresAtMs;
      this.spaceCreateState = 1;
    } catch (error) {
      this.spaceCreateState = 3;
    } finally {
      this.spaceInvitationBusy = false;
    }
  }

  public canIssueSpaceInvitation(): boolean {
    return this.spaceNodeState === 2 && this.spaceJoined && !this.spaceInvitationBusy &&
      this.spaceCreatePassphrase.length >= 8;
  }

  public buildSpaceInvitationUri(): string {
    if (this.spaceIssuedInvitationCode.length === 0 || this.spaceCreatePassphrase.length === 0) {
      return '';
    }
    return 'uniclipboard://join-space?v=1&code=' + encodeURIComponent(this.spaceIssuedInvitationCode) +
      '&pwd=' + encodeURIComponent(this.spaceCreatePassphrase);
  }

  public async shareCurrentSpaceInvitation(): Promise<void> {
    let invitationUri: string = this.buildSpaceInvitationUri();
    if (invitationUri.length === 0) {
      return;
    }
    let context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      this.showFeedbackToast($r('app.string.space_share_invitation_failed'));
      return;
    }
    try {
      let title: string = await context.resourceManager.getStringByName('space_invitation_title');
      let codeLabel: string = await context.resourceManager.getStringByName('space_share_code_label');
      let passphraseLabel: string =
        await context.resourceManager.getStringByName('space_share_passphrase_label');
      let linkLabel: string = await context.resourceManager.getStringByName('space_share_link_label');
      let sharedContent: string = title + '\n' +
        codeLabel + ': ' + this.spaceIssuedInvitationCode + '\n' +
        passphraseLabel + ': ' + this.spaceCreatePassphrase + '\n' +
        linkLabel + ': ' + invitationUri;
      let record: systemShare.SharedRecord = {
        utd: uniformTypeDescriptor.UniformDataType.PLAIN_TEXT,
        content: sharedContent,
        title: title
      };
      let sharedData: systemShare.SharedData = new systemShare.SharedData(record);
      let shareController: systemShare.ShareController = new systemShare.ShareController(sharedData);
      let options: systemShare.ShareControllerOptions = {
        selectionMode: systemShare.SelectionMode.SINGLE
      };
      let abilityContext: common.UIAbilityContext = context as common.UIAbilityContext;
      await shareController.show(abilityContext, options);
    } catch (error) {
      logger.error('UniClipboard failed to share the space invitation.');
      this.showFeedbackToast($r('app.string.space_share_invitation_failed'));
    }
  }

  public isSpaceInvitationCode(value: string): boolean {
    let code: string = value.trim().toUpperCase();
    return code.length === 9 && code.charAt(4) === '-';
  }

  public importSpaceInvitation(value: string): boolean {
    let payload: string = value.trim();
    if (this.isSpaceInvitationCode(payload)) {
      this.spaceInvitationCode = payload.toUpperCase();
      this.spaceInvitationScanState = 1;
      this.spaceJoinState = 0;
      return true;
    }
    let prefix: string = 'uniclipboard://join-space?';
    if (!payload.startsWith(prefix)) {
      this.spaceInvitationScanState = 2;
      return false;
    }
    let code: string = '';
    let passphrase: string = '';
    try {
      let query: string = payload.substring(prefix.length);
      let pairs: string[] = query.split('&');
      for (let index: number = 0; index < pairs.length; index++) {
        let pair: string = pairs[index];
        let separator: number = pair.indexOf('=');
        if (separator <= 0) {
          continue;
        }
        let key: string = pair.substring(0, separator);
        let decodedValue: string = decodeURIComponent(pair.substring(separator + 1));
        if (key === 'code') {
          code = decodedValue.toUpperCase();
        } else if (key === 'pwd') {
          passphrase = decodedValue;
        }
      }
    } catch (error) {
      this.spaceInvitationScanState = 2;
      return false;
    }
    if (!this.isSpaceInvitationCode(code) || passphrase.length === 0) {
      this.spaceInvitationScanState = 2;
      return false;
    }
    this.spaceInvitationCode = code;
    this.spacePassphrase = passphrase;
    this.spaceInvitationScanState = 1;
    this.spaceJoinState = 0;
    return true;
  }

  public scanSpaceInvitation(): void {
    let options: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.QR_CODE],
      enableMultiMode: false,
      enableAlbum: true
    };
    this.spaceInvitationScanState = 0;
    if (canIUse('SystemCapability.Multimedia.Scan.ScanBarcode')) {
      try {
        scanBarcode.startScanForResult(this.getUIContext().getHostContext(), options,
          (error: BusinessError, result: scanBarcode.ScanResult): void => {
            if (error) {
              this.spaceInvitationScanState = 2;
              return;
            }
            this.importSpaceInvitation(result.originalValue);
          });
      } catch (error) {
        this.spaceInvitationScanState = 2;
      }
    } else {
      this.spaceInvitationScanState = 2;
    }
  }

  public invitationExpiryText(): string {
    if (this.spaceInvitationExpiresAtMs <= 0) {
      return '';
    }
    let expiry: Date = new Date(this.spaceInvitationExpiresAtMs);
    let hours: string = expiry.getHours().toString().padStart(2, '0');
    let minutes: string = expiry.getMinutes().toString().padStart(2, '0');
    let seconds: string = expiry.getSeconds().toString().padStart(2, '0');
    return hours + ':' + minutes + ':' + seconds;
  }

  public selectPage(index: number): void {
    this.selectedTab = index;
    this.largeSection = index === 0 ? 0 : (index === 1 ? 1 : 2);
    let destinationName: string = index === 0 ? 'sync' : (index === 1 ? 'devices' : 'settings');
    this.largeNavStack.clear(false);
    this.largeNavStack.pushPath({ name: destinationName }, false);
    if (index === 1) {
      this.refreshMobileSyncDevices();
      if (this.spaceJoined) {
        this.refreshSpaceDevices();
      }
    }
  }

  public openConnectionSettings(): void {
    this.selectPage(1);
  }

  public showFeedbackToast(message: Resource): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (error) {
      logger.error('UniClipboard failed to show feedback status.');
    }
  }

  public reportError(source: string, message: string, toast?: Resource): void {
    logger.error('[' + source + '] ' + message);
    let now: Date = new Date();
    let timeLabel: string = this.padTimeUnit(now.getHours()) + ':' +
      this.padTimeUnit(now.getMinutes()) + ':' + this.padTimeUnit(now.getSeconds());
    let next: AppErrorRecord[] = [new AppErrorRecord(timeLabel, source, message)];
    for (let index: number = 0; index < this.recentErrors.length && next.length < MAX_RECENT_ERRORS; index++) {
      next.push(this.recentErrors[index]);
    }
    this.recentErrors = next;
    if (toast !== undefined) {
      this.showFeedbackToast(toast);
    }
  }

  public errorDetail(error: Object): string {
    let businessError: BusinessError = error as BusinessError;
    if (businessError.message !== undefined && businessError.message.length > 0) {
      return businessError.message;
    }
    return JSON.stringify(error);
  }

  private hasMigrationRecords(value: string | undefined): boolean {
    if (value === undefined) {
      return false;
    }
    let normalized: string = value.trim();
    return normalized.length > 0 && normalized !== '0' && normalized !== '[]' && normalized !== '{}';
  }

  private padTimeUnit(value: number): string {
    return value < 10 ? '0' + value.toString() : value.toString();
  }

  public async submitFeedback(): Promise<boolean> {
    let feedback: string = this.feedbackText.trim();
    if (feedback.length === 0) {
      this.showFeedbackToast($r('app.string.feedback_empty_hint'));
      return false;
    }

    try {
      await this.clipboardService.writeText(feedback);
      this.showFeedbackToast($r('app.string.feedback_copied'));
    } catch (error) {
      this.showFeedbackToast($r('app.string.feedback_copy_failed'));
    }

    let context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      this.showFeedbackToast($r('app.string.feedback_email_open_failed'));
      return false;
    }

    let subject: string = 'UniClipboard Feedback';
    try {
      subject = await context.resourceManager.getStringByName('feedback_email_subject');
    } catch (error) {
      logger.error('UniClipboard failed to load the feedback email subject.');
    }
    let abilityContext: common.UIAbilityContext = context as common.UIAbilityContext;
    let emailUri: string = 'mailto:' + FEEDBACK_EMAIL + '?subject=' + encodeURIComponent(subject) +
      '&body=' + encodeURIComponent(feedback);
    try {
      await abilityContext.startAbility({
        action: 'ohos.want.action.sendToData',
        uri: emailUri
      });
      return true;
    } catch (error) {
      logger.error('UniClipboard failed to open the email app.');
      this.showFeedbackToast($r('app.string.feedback_email_open_failed'));
      return false;
    }
  }

  public selectLargeSection(index: number): void {
    this.largeSection = index;
    this.selectedTab = index;
    let destinationName: string = index === 0 ? 'desktopClipboard' :
      index === 1 ? 'desktopDevices' : 'desktopSettings';
    this.largeNavStack.clear(false);
    this.largeNavStack.pushPath({ name: destinationName }, false);
    if (index === 1) {
      this.refreshMobileSyncDevices();
      if (this.spaceJoined) {
        this.refreshSpaceDevices();
      }
    }
  }

  public animateLatestContent(): void {
    this.getUIContext().animateTo({
      duration: 300,
      curve: Curve.EaseOut,
      iterations: 2,
      playMode: PlayMode.Alternate,
      onFinish: (): void => {
        this.latestContentPulse = 1;
      }
    }, (): void => {
      this.latestContentPulse = 1.025;
    });
  }

  public animateHistoryUpdate(): void {
    this.getUIContext().animateTo({
      duration: 320,
      curve: Curve.EaseOut,
      iterations: 2,
      playMode: PlayMode.Alternate,
      onFinish: (): void => {
        this.historyPulse = 1;
      }
    }, (): void => {
      this.historyPulse = 1.018;
    });
  }

  private recordConnectionDiagnosticFailure(reason: string): void {
    this.connectionDiagnosticLastFailure = reason;
    this.connectionDiagnosticLastFailureAtMs = Date.now();
  }

  private refreshConnectionDiagnosticNetworkType(): void {
    this.connectionDiagnosticNetworkType = 'unavailable';
    try {
      let netHandle: connection.NetHandle = connection.getDefaultNetSync();
      let capabilities: connection.NetCapabilities = connection.getNetCapabilitiesSync(netHandle);
      let bearerTypes: connection.NetBearType[] = capabilities.bearerTypes;
      if (bearerTypes.indexOf(connection.NetBearType.BEARER_VPN) >= 0) {
        this.connectionDiagnosticNetworkType = 'vpn';
      } else if (bearerTypes.indexOf(connection.NetBearType.BEARER_WIFI) >= 0) {
        this.connectionDiagnosticNetworkType = 'wifi';
      } else if (bearerTypes.indexOf(connection.NetBearType.BEARER_ETHERNET) >= 0) {
        this.connectionDiagnosticNetworkType = 'ethernet';
      } else if (bearerTypes.indexOf(connection.NetBearType.BEARER_CELLULAR) >= 0) {
        this.connectionDiagnosticNetworkType = 'cellular';
      } else if (bearerTypes.indexOf(connection.NetBearType.BEARER_BLUETOOTH) >= 0) {
        this.connectionDiagnosticNetworkType = 'bluetooth';
      } else {
        this.connectionDiagnosticNetworkType = 'other';
      }
    } catch (error) {
      this.connectionDiagnosticNetworkType = 'unavailable';
    }
  }

  private refreshConnectionDiagnosticPermissions(): void {
    this.connectionDiagnosticInternetGranted = false;
    this.connectionDiagnosticBackgroundGranted = false;
    try {
      let bundleInfo: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      let tokenId: number = bundleInfo.appInfo.accessTokenId;
      let accessManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      let internetPermission: Permissions = 'ohos.permission.INTERNET';
      let backgroundPermission: Permissions = 'ohos.permission.KEEP_BACKGROUND_RUNNING';
      this.connectionDiagnosticInternetGranted = accessManager.checkAccessTokenSync(
        tokenId, internetPermission) === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
      this.connectionDiagnosticBackgroundGranted = accessManager.checkAccessTokenSync(
        tokenId, backgroundPermission) === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (error) {
      this.connectionDiagnosticInternetGranted = false;
      this.connectionDiagnosticBackgroundGranted = false;
    }
  }

  private applyConnectionDiagnosticDevices(devices: EngineRuntimeDevice[]): EngineRuntimeDevice | null {
    this.spaceDevices = devices;
    this.connectionDiagnosticDirectCount = 0;
    this.connectionDiagnosticRelayCount = 0;
    this.connectionDiagnosticUnknownCount = 0;
    this.connectionDiagnosticOfflineCount = 0;
    let target: EngineRuntimeDevice | null = null;
    let peerConnected: boolean = false;
    for (let index: number = 0; index < devices.length; index++) {
      let device: EngineRuntimeDevice = devices[index];
      if (device.isLocal) {
        continue;
      }
      if (target === null || (!target.online && device.online)) {
        target = device;
      }
      if (!device.online || device.channel === 'offline') {
        this.connectionDiagnosticOfflineCount += 1;
        continue;
      }
      peerConnected = true;
      if (device.channel === 'direct') {
        this.connectionDiagnosticDirectCount += 1;
      } else if (device.channel === 'relay') {
        this.connectionDiagnosticRelayCount += 1;
      } else {
        this.connectionDiagnosticUnknownCount += 1;
      }
    }
    this.spacePeerConnected = peerConnected;
    return target;
  }

  public async refreshConnectionDiagnostics(): Promise<void> {
    if (this.connectionDiagnosticBusy) {
      return;
    }
    this.connectionDiagnosticBusy = true;
    this.connectionDiagnosticExportState = 0;
    this.connectionDiagnosticLatencyMs = -1;
    this.connectionDiagnosticDirectCount = 0;
    this.connectionDiagnosticRelayCount = 0;
    this.connectionDiagnosticUnknownCount = 0;
    this.connectionDiagnosticOfflineCount = 0;
    this.refreshConnectionDiagnosticNetworkType();
    this.refreshConnectionDiagnosticPermissions();
    let probeSucceeded: boolean = false;
    let failureReason: string = 'none';
    if (this.connectionDiagnosticNetworkType === 'unavailable') {
      failureReason = 'network_unavailable';
    }
    if (this.spaceNodeState === 2 && this.spaceJoined) {
      try {
        await engineRuntimeService.recoverNetwork();
        let devices: EngineRuntimeDevice[] = await engineRuntimeService.queryDevices();
        let target: EngineRuntimeDevice | null = this.applyConnectionDiagnosticDevices(devices);
        if (target === null) {
          failureReason = 'no_peer';
        } else {
          if (target.online) {
            probeSucceeded = true;
          } else {
            failureReason = 'peer_offline';
          }
        }
      } catch (error) {
        failureReason = 'space_probe_failed';
      }
    } else if (this.spaceNodeState !== 2) {
      failureReason = 'node_unavailable';
    } else if (!this.spaceJoined) {
      failureReason = 'space_not_joined';
    }
    if (!probeSucceeded && this.hasConfig()) {
      try {
        let startedAt: number = Date.now();
        let client: MobileSyncClient = new MobileSyncClient(this.getConfig());
        await client.probe();
        this.connectionDiagnosticLatencyMs = Math.max(0, Date.now() - startedAt);
        this.connectionDiagnosticRelayCount += 1;
        probeSucceeded = true;
      } catch (error) {
        failureReason = 'relay_probe_failed';
      }
    }
    if (probeSucceeded) {
      this.statusCode = 2;
    } else {
      this.statusCode = 3;
      if (!this.connectionDiagnosticInternetGranted) {
        failureReason = 'permission_unavailable';
      }
      if (failureReason === 'none') {
        failureReason = 'not_configured';
      }
      this.recordConnectionDiagnosticFailure(failureReason);
    }
    this.connectionDiagnosticBusy = false;
  }

  private connectionDiagnosticTransportCode(): string {
    if (this.connectionDiagnosticDirectCount > 0 && this.connectionDiagnosticRelayCount > 0) {
      return 'mixed';
    }
    if (this.connectionDiagnosticDirectCount > 0) {
      return 'direct';
    }
    if (this.connectionDiagnosticRelayCount > 0) {
      return 'relay';
    }
    if (this.connectionDiagnosticUnknownCount > 0) {
      return 'unknown';
    }
    return 'offline';
  }

  private connectionDiagnosticPermissionCode(granted: boolean): string {
    return granted ? 'granted' : 'denied';
  }

  private buildRedactedConnectionDiagnosticLog(): string {
    let generatedAt: string = new Date().toISOString();
    let recentErrorLog: string = 'recent_errors_begin\n';
    if (this.recentErrors.length === 0) {
      recentErrorLog += 'none\n';
    } else {
      for (let index: number = 0; index < this.recentErrors.length; index++) {
        let record: AppErrorRecord = this.recentErrors[index];
        recentErrorLog += record.timeLabel + '|' + this.redactDiagnosticText(record.source) + '|' +
          this.redactDiagnosticText(record.message) + '\n';
      }
    }
    recentErrorLog += 'recent_errors_end\n';
    return 'UniClipboard connection diagnostics\n' +
      'redaction=enabled\n' +
      'generated_at=' + generatedAt + '\n' +
      'device_type=' + deviceInfo.deviceType + '\n' +
      'network_type=' + this.connectionDiagnosticNetworkType + '\n' +
      'transport=' + this.connectionDiagnosticTransportCode() + '\n' +
      'latency_ms=' + this.connectionDiagnosticLatencyMs.toString() + '\n' +
      'direct_paths=' + this.connectionDiagnosticDirectCount.toString() + '\n' +
      'relay_paths=' + this.connectionDiagnosticRelayCount.toString() + '\n' +
      'unknown_paths=' + this.connectionDiagnosticUnknownCount.toString() + '\n' +
      'offline_peers=' + this.connectionDiagnosticOfflineCount.toString() + '\n' +
      'internet_permission=' + this.connectionDiagnosticPermissionCode(
        this.connectionDiagnosticInternetGranted) + '\n' +
      'background_permission=' + this.connectionDiagnosticPermissionCode(
        this.connectionDiagnosticBackgroundGranted) + '\n' +
      'background_sync=' + (this.backgroundSyncEnabled ? 'enabled' : 'disabled') + '\n' +
      'last_failure=' + this.connectionDiagnosticLastFailure + '\n' +
      'last_failure_at_ms=' + this.connectionDiagnosticLastFailureAtMs.toString() + '\n' +
      recentErrorLog +
      'redacted_fields=device_ids,device_names,addresses,urls,credentials,clipboard_content\n';
  }

  private redactDiagnosticText(value: string): string {
    let redacted: string = value.replace(/https?:\/\/[^\s]+/gi, '[redacted-url]');
    redacted = redacted.replace(/(password|token|secret|authorization)=?[^\s]*/gi, '$1=[redacted]');
    if (redacted.length > 512) {
      return redacted.substring(0, 512) + '...';
    }
    return redacted;
  }

  public async exportRedactedConnectionDiagnostics(): Promise<void> {
    if (this.connectionDiagnosticExportState === 1) {
      return;
    }
    let context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      this.connectionDiagnosticExportState = 3;
      return;
    }
    this.connectionDiagnosticExportState = 1;
    let targetFile: fileIo.File | null = null;
    try {
      let targetPath: string = context.cacheDir + '/uniclipboard-connection-diagnostics.txt';
      targetFile = fileIo.openSync(targetPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      let encoder: util.TextEncoder = new util.TextEncoder();
      let data: Uint8Array = encoder.encodeInto(this.buildRedactedConnectionDiagnosticLog());
      fileIo.writeSync(targetFile.fd, data.buffer);
      fileIo.closeSync(targetFile.fd);
      targetFile = null;
      let title: string = await context.resourceManager.getStringByName('connection_diagnostics_log_title');
      let targetUri: string = fileUri.getUriFromPath(targetPath);
      let record: systemShare.SharedRecord = {
        utd: uniformTypeDescriptor.UniformDataType.PLAIN_TEXT,
        uri: targetUri,
        title: title,
        description: title
      };
      let sharedData: systemShare.SharedData = new systemShare.SharedData(record);
      let shareController: systemShare.ShareController = new systemShare.ShareController(sharedData);
      let options: systemShare.ShareControllerOptions = {
        selectionMode: systemShare.SelectionMode.SINGLE
      };
      await shareController.show(context as common.UIAbilityContext, options);
      this.connectionDiagnosticExportState = 2;
    } catch (error) {
      this.connectionDiagnosticExportState = 3;
    } finally {
      if (targetFile !== null) {
        try {
          fileIo.closeSync(targetFile.fd);
        } catch (error) {
        }
      }
    }
  }

  private applyDesktopDeviceSyncPreferences(preferences: NativeSpaceMemberSyncPreferences): void {
    this.desktopDeviceSendEnabled = preferences.sendEnabled;
    this.desktopDeviceSyncText = preferences.text;
    this.desktopDeviceSyncImage = preferences.image;
    this.desktopDeviceSyncFile = preferences.file;
    this.desktopDeviceSyncLink = preferences.link;
    this.desktopDeviceSyncRichText = preferences.richText;
  }

  private assignDesktopSelectedSpaceDevice(device: EngineRuntimeDevice): void {
    this.desktopSelectedSpaceDeviceId = device.deviceId;
    this.desktopSelectedSpaceDeviceName = device.deviceName;
    this.desktopSelectedSpaceDeviceType = device.deviceType;
    this.desktopSelectedSpaceDeviceOnline = device.online;
    this.desktopSelectedSpaceDeviceState = device.state;
    this.desktopSelectedSpaceDeviceIsLocal = device.isLocal;
  }

  public selectDesktopSpaceDevice(device: EngineRuntimeDevice): void {
    this.assignDesktopSelectedSpaceDevice(device);
    if (device.isLocal) {
      this.desktopDeviceSyncState = 0;
      return;
    }
    this.loadDesktopDeviceSyncPreferences(device.deviceId);
  }

  private synchronizeDesktopSpaceDeviceSelection(devices: EngineRuntimeDevice[]): void {
    let selected: EngineRuntimeDevice | null = null;
    let local: EngineRuntimeDevice | null = null;
    for (let index: number = 0; index < devices.length; index++) {
      let device: EngineRuntimeDevice = devices[index];
      if (device.isLocal) {
        local = device;
      }
      if (device.deviceId === this.desktopSelectedSpaceDeviceId) {
        selected = device;
      }
    }
    if (selected !== null) {
      this.assignDesktopSelectedSpaceDevice(selected);
      return;
    }
    if (local !== null) {
      this.assignDesktopSelectedSpaceDevice(local);
    } else if (devices.length > 0) {
      this.assignDesktopSelectedSpaceDevice(devices[0]);
    } else {
      this.desktopSelectedSpaceDeviceId = '';
      this.desktopSelectedSpaceDeviceName = '';
      this.desktopSelectedSpaceDeviceType = '';
      this.desktopSelectedSpaceDeviceOnline = false;
      this.desktopSelectedSpaceDeviceState = 'unknown';
      this.desktopSelectedSpaceDeviceIsLocal = true;
      this.desktopDeviceSyncState = 0;
    }
  }

  public async loadDesktopDeviceSyncPreferences(deviceId: string): Promise<void> {
    if (deviceId.length === 0) {
      return;
    }
    this.desktopDeviceSyncState = 1;
    try {
      let preferences: NativeSpaceMemberSyncPreferences =
        await this.spaceNodeService.memberSyncPreferences(deviceId);
      if (this.desktopSelectedSpaceDeviceId !== deviceId || this.desktopSelectedSpaceDeviceIsLocal) {
        return;
      }
      this.applyDesktopDeviceSyncPreferences(preferences);
      this.desktopDeviceSyncState = 2;
    } catch (error) {
      if (this.desktopSelectedSpaceDeviceId === deviceId) {
        this.desktopDeviceSyncState = 3;
      }
    }
  }

  public async updateDesktopDeviceSyncPreference(contentType: string, enabled: boolean): Promise<void> {
    if (this.desktopSelectedSpaceDeviceIsLocal || this.desktopSelectedSpaceDeviceId.length === 0 ||
      this.desktopDeviceSyncSaving || this.desktopDeviceSyncState !== 2) {
      return;
    }
    let previousSendEnabled: boolean = this.desktopDeviceSendEnabled;
    let previousText: boolean = this.desktopDeviceSyncText;
    let previousImage: boolean = this.desktopDeviceSyncImage;
    let previousFile: boolean = this.desktopDeviceSyncFile;
    let previousLink: boolean = this.desktopDeviceSyncLink;
    let previousRichText: boolean = this.desktopDeviceSyncRichText;
    if (contentType === 'send') {
      this.desktopDeviceSendEnabled = enabled;
    } else if (contentType === 'text') {
      this.desktopDeviceSyncText = enabled;
    } else if (contentType === 'image') {
      this.desktopDeviceSyncImage = enabled;
    } else if (contentType === 'file') {
      this.desktopDeviceSyncFile = enabled;
    } else if (contentType === 'link') {
      this.desktopDeviceSyncLink = enabled;
    } else if (contentType === 'rich_text') {
      this.desktopDeviceSyncRichText = enabled;
    } else {
      return;
    }
    this.desktopDeviceSyncSaving = true;
    let deviceId: string = this.desktopSelectedSpaceDeviceId;
    try {
      let preferences: NativeSpaceMemberSyncPreferences =
        await this.spaceNodeService.updateMemberSendPreferences(
          deviceId,
          this.desktopDeviceSendEnabled,
          this.desktopDeviceSyncText,
          this.desktopDeviceSyncImage,
          this.desktopDeviceSyncFile,
          this.desktopDeviceSyncLink,
          this.desktopDeviceSyncRichText);
      if (this.desktopSelectedSpaceDeviceId === deviceId) {
        this.applyDesktopDeviceSyncPreferences(preferences);
        this.desktopDeviceSyncState = 2;
      }
      this.statusCode = 2;
    } catch (error) {
      if (this.desktopSelectedSpaceDeviceId === deviceId) {
        this.desktopDeviceSendEnabled = previousSendEnabled;
        this.desktopDeviceSyncText = previousText;
        this.desktopDeviceSyncImage = previousImage;
        this.desktopDeviceSyncFile = previousFile;
        this.desktopDeviceSyncLink = previousLink;
        this.desktopDeviceSyncRichText = previousRichText;
        this.desktopDeviceSyncState = 3;
      }
      this.statusCode = 3;
    } finally {
      this.desktopDeviceSyncSaving = false;
    }
  }

  public async resetDesktopDeviceSyncPreferences(): Promise<void> {
    if (this.desktopSelectedSpaceDeviceIsLocal || this.desktopSelectedSpaceDeviceId.length === 0 ||
      this.desktopDeviceSyncSaving) {
      return;
    }
    this.desktopDeviceSyncSaving = true;
    let deviceId: string = this.desktopSelectedSpaceDeviceId;
    try {
      let preferences: NativeSpaceMemberSyncPreferences =
        await this.spaceNodeService.resetMemberSyncPreferences(deviceId);
      if (this.desktopSelectedSpaceDeviceId === deviceId) {
        this.applyDesktopDeviceSyncPreferences(preferences);
        this.desktopDeviceSyncState = 2;
      }
      this.statusCode = 2;
    } catch (error) {
      if (this.desktopSelectedSpaceDeviceId === deviceId) {
        this.desktopDeviceSyncState = 3;
      }
      this.statusCode = 3;
    } finally {
      this.desktopDeviceSyncSaving = false;
    }
  }

  public async refreshSpaceDevices(): Promise<void> {
    if (!this.spaceJoined || this.spaceNodeState !== 2) {
      return;
    }
    if (this.spaceDeviceRefreshBusy) {
      this.spaceDeviceRefreshQueued = true;
      return;
    }
    this.spaceDeviceRefreshBusy = true;
    try {
      await this.ensureOfficialEngineRunning();
      let devices: EngineRuntimeDevice[] = await engineRuntimeService.queryDevices();
      this.spaceDevices = devices;
      this.synchronizeDesktopSpaceDeviceSelection(devices);
      this.spacePeerConnected = devices.some((device: EngineRuntimeDevice): boolean => {
        return !device.isLocal && device.online;
      });
    } catch (error) {
      logger.error('UniClipboard refresh space devices failed: ' + this.errorDetail(error));
      this.recordConnectionDiagnosticFailure('space_probe_failed');
    } finally {
      this.spaceDeviceRefreshBusy = false;
      if (this.spaceDeviceRefreshQueued && this.spaceJoined && this.spaceNodeState === 2) {
        this.spaceDeviceRefreshQueued = false;
        setTimeout((): void => {
          this.refreshSpaceDevices().catch((): void => {
          });
        }, 0);
      } else {
        this.spaceDeviceRefreshQueued = false;
      }
    }
  }

  public async connectSpaceDevice(device: EngineRuntimeDevice): Promise<void> {
    if (device.isLocal || this.spaceConnectBusy || this.desktopDeviceMutationBusy ||
      this.spaceNodeState !== 2 || !this.spaceJoined) {
      return;
    }
    this.spaceConnectBusy = true;
    this.spaceConnectingDeviceId = device.deviceId;
    this.spaceConnectState = 1;
    try {
      await engineRuntimeService.recoverNetwork();
      await this.refreshSpaceDevices();
      this.spaceConnectState = device.online ? 2 : 3;
      if (device.online) {
        this.spacePeerConnected = true;
        this.statusCode = 2;
      } else {
        this.recordConnectionDiagnosticFailure('peer_offline');
      }
    } catch (error) {
      this.spaceConnectState = 3;
      this.statusCode = 3;
      this.recordConnectionDiagnosticFailure('space_probe_failed');
    } finally {
      this.spaceConnectingDeviceId = '';
      this.spaceConnectBusy = false;
    }
  }

  public async connectAllSpaceDevices(): Promise<void> {
    if (this.spaceConnectBusy || this.desktopDeviceMutationBusy ||
      this.spaceNodeState !== 2 || !this.spaceJoined) {
      return;
    }
    this.spaceConnectBusy = true;
    this.spaceConnectingDeviceId = '*';
    this.spaceConnectState = 1;
    let anyOnline: boolean = false;
    try {
      await engineRuntimeService.recoverNetwork();
      await this.refreshSpaceDevices();
      for (let index: number = 0; index < this.spaceDevices.length; index++) {
        let device: EngineRuntimeDevice = this.spaceDevices[index];
        if (!device.isLocal && device.online) {
          anyOnline = true;
        }
      }
      await this.refreshSpaceDevices();
      this.spacePeerConnected = anyOnline || this.spacePeerConnected;
      this.spaceConnectState = this.spacePeerConnected ? 2 : 3;
      this.statusCode = this.spacePeerConnected ? 2 : 3;
      if (!this.spacePeerConnected) {
        this.recordConnectionDiagnosticFailure('peer_offline');
      }
    } catch (error) {
      this.spaceConnectState = 3;
      this.statusCode = 3;
      this.recordConnectionDiagnosticFailure('space_probe_failed');
    } finally {
      this.spaceConnectingDeviceId = '';
      this.spaceConnectBusy = false;
    }
  }

  public async refreshDesktopMessages(): Promise<void> {
    if (this.desktopRefreshBusy) {
      return;
    }
    this.desktopRefreshBusy = true;
    try {
      if (this.spaceJoined) {
        await engineRuntimeService.recoverNetwork();
        await this.connectAllSpaceDevices();
        await this.pollOfficialEngineInbound();
      }
      if (this.hasConfig()) {
        await this.loadServerHistory(true);
      } else if (!this.spaceJoined) {
        this.statusCode = 3;
      }
    } finally {
      this.desktopRefreshBusy = false;
    }
  }

  public desktopAllFiltersClear(): boolean {
    return !this.desktopStarredOnly && this.desktopTypeFilter === 0 && this.desktopTagFilter === 0 &&
      this.desktopSourceFilter === 0 && this.desktopTimeFilter === 0 && this.desktopExtensionFilter.length === 0 &&
      this.desktopCustomTagFilter.length === 0 && this.historyDeviceFilter.length === 0 && !this.historySnippetOnly;
  }

  public desktopSearchMatches(text: string): boolean {
    let query: string = this.historySearchText.trim().toLowerCase();
    return query.length === 0 || text.toLowerCase().indexOf(query) >= 0;
  }

  public scheduleDesktopHistorySearch(value: string): void {
    this.historySearchText = value;
    if (this.historySearchTimerId >= 0) {
      clearTimeout(this.historySearchTimerId);
      this.historySearchTimerId = -1;
    }
    if (!this.hasConfig()) {
      return;
    }
    this.historySearchTimerId = setTimeout((): void => {
      this.historySearchTimerId = -1;
      this.loadServerHistory(true);
    }, 300);
  }

  public submitDesktopHistorySearch(): void {
    if (this.historySearchTimerId >= 0) {
      clearTimeout(this.historySearchTimerId);
      this.historySearchTimerId = -1;
    }
    if (this.hasConfig()) {
      this.loadServerHistory(true);
    }
  }

  public desktopFilterSelected(group: number, value: number): boolean {
    if (group === 0) {
      return value === 0 ? this.desktopAllFiltersClear() : this.desktopStarredOnly;
    }
    if (group === 1) {
      return this.desktopTypeFilter === value;
    }
    if (group === 2) {
      return this.desktopTagFilter === value;
    }
    if (group === 3) {
      return this.desktopSourceFilter === value;
    }
    if (group === 5) {
      return this.historySnippetOnly;
    }
    return this.desktopTimeFilter === value;
  }

  public applyDesktopFilter(group: number, value: number): void {
    let previousStarredOnly: boolean = this.desktopStarredOnly;
    if (group === 0 && value === 0) {
      this.desktopStarredOnly = false;
      this.desktopTypeFilter = 0;
      this.desktopTagFilter = 0;
      this.desktopSourceFilter = 0;
      this.desktopTimeFilter = 0;
      this.desktopExtensionFilter = '';
      this.desktopCustomTagFilter = '';
      this.historyDeviceFilter = '';
      this.historySnippetOnly = false;
    } else if (group === 0) {
      this.desktopStarredOnly = !this.desktopStarredOnly;
    } else if (group === 1) {
      this.desktopTypeFilter = this.desktopTypeFilter === value ? 0 : value;
    } else if (group === 2) {
      this.desktopTagFilter = this.desktopTagFilter === value ? 0 : value;
    } else if (group === 3) {
      this.desktopSourceFilter = value;
    } else if (group === 5) {
      this.historySnippetOnly = !this.historySnippetOnly;
    } else {
      this.desktopTimeFilter = value;
    }
    let shouldReload: boolean = previousStarredOnly !== this.desktopStarredOnly;
    this.historyStarredOnly = this.desktopStarredOnly;
    if (shouldReload && this.hasConfig()) {
      this.loadServerHistory(true);
    }
  }

  public applyDesktopExtensionFilter(extension: string): void {
    this.desktopExtensionFilter = this.desktopExtensionFilter === extension ? '' : extension;
  }

  public applyHistoryDeviceFilter(deviceName: string): void {
    this.historyDeviceFilter = this.historyDeviceFilter === deviceName ? '' : deviceName;
  }

  public applyHistoryTagFilter(tag: string): void {
    this.desktopCustomTagFilter = this.desktopCustomTagFilter === tag ? '' : tag;
  }

  public toggleHistorySnippetFilter(): void {
    this.historySnippetOnly = !this.historySnippetOnly;
  }

  public clearHistoryLibraryFilters(): void {
    this.historySnippetOnly = false;
    this.historyDeviceFilter = '';
    this.desktopCustomTagFilter = '';
  }

  public desktopTextLooksRich(text: string): boolean {
    let lowerText: string = text.toLowerCase();
    return lowerText.indexOf('<p') >= 0 || lowerText.indexOf('<div') >= 0 ||
      lowerText.indexOf('<span') >= 0 || lowerText.indexOf('<strong') >= 0 ||
      lowerText.indexOf('<html') >= 0;
  }

  public desktopLinkHostIsValid(host: string): boolean {
    if (host.length === 0 || host.endsWith('.')) {
      return false;
    }
    if (host === 'localhost') {
      return true;
    }
    let portIndex: number = host.lastIndexOf(':');
    let hostWithoutPort: string = portIndex > 0 ? host.substring(0, portIndex) : host;
    let dotIndex: number = hostWithoutPort.indexOf('.');
    return dotIndex > 0 && dotIndex < hostWithoutPort.length - 1;
  }

  public desktopTextLooksLikeLink(text: string): boolean {
    let candidate: string = text.trim().toLowerCase();
    if (candidate.length === 0 || candidate.indexOf(' ') >= 0 || candidate.indexOf('\n') >= 0 ||
      candidate.indexOf('\r') >= 0 || candidate.indexOf('\t') >= 0) {
      return false;
    }
    if (candidate.indexOf('mailto:') === 0) {
      let email: string = candidate.substring(7);
      let atIndex: number = email.indexOf('@');
      let dotIndex: number = email.lastIndexOf('.');
      return atIndex > 0 && dotIndex > atIndex + 1 && dotIndex < email.length - 1;
    }
    let hostStart: number = -1;
    if (candidate.indexOf('https://') === 0) {
      hostStart = 8;
    } else if (candidate.indexOf('http://') === 0) {
      hostStart = 7;
    } else if (candidate.indexOf('ftp://') === 0) {
      hostStart = 6;
    } else if (candidate.indexOf('www.') === 0) {
      hostStart = 0;
    }
    if (hostStart < 0 || hostStart >= candidate.length) {
      return false;
    }
    let hostEnd: number = candidate.length;
    let pathIndex: number = candidate.indexOf('/', hostStart);
    if (pathIndex >= 0 && pathIndex < hostEnd) {
      hostEnd = pathIndex;
    }
    let queryIndex: number = candidate.indexOf('?', hostStart);
    if (queryIndex >= 0 && queryIndex < hostEnd) {
      hostEnd = queryIndex;
    }
    let fragmentIndex: number = candidate.indexOf('#', hostStart);
    if (fragmentIndex >= 0 && fragmentIndex < hostEnd) {
      hostEnd = fragmentIndex;
    }
    return this.desktopLinkHostIsValid(candidate.substring(hostStart, hostEnd));
  }

  public currentTextLooksLikeLink(): boolean {
    return !this.desktopShowsLatestImage() && !this.desktopShowsFile() &&
      this.desktopTextLooksLikeLink(this.desktopDetailText());
  }

  public currentLinkUrl(): string {
    let candidate: string = this.desktopDetailText().trim();
    if (candidate.toLowerCase().indexOf('www.') === 0) {
      return 'https://' + candidate;
    }
    return candidate;
  }

  public clearLinkPreview(): void {
    this.linkPreviewRequestId += 1;
    this.linkPreview = null;
    this.linkPreviewState = 0;
  }

  public async refreshCurrentLinkPreview(): Promise<void> {
    this.clearLinkPreview();
    if (!this.currentTextLooksLikeLink()) {
      return;
    }
    let url: string = this.currentLinkUrl();
    let lowerUrl: string = url.toLowerCase();
    if (lowerUrl.indexOf('http://') !== 0 && lowerUrl.indexOf('https://') !== 0) {
      this.linkPreview = this.linkPreviewService.createFallback(url);
      this.linkPreviewState = 3;
      return;
    }
    let requestId: number = this.linkPreviewRequestId;
    this.linkPreviewState = 1;
    try {
      let preview: LinkPreview = await this.linkPreviewService.load(url);
      if (requestId !== this.linkPreviewRequestId || this.currentLinkUrl() !== url) {
        return;
      }
      this.linkPreview = preview;
      this.linkPreviewState = 2;
    } catch (error) {
      if (requestId === this.linkPreviewRequestId) {
        this.linkPreview = this.linkPreviewService.createFallback(url);
        this.linkPreviewState = 3;
      }
    }
  }

  public markLinkPreviewImageFailed(): void {
    if (this.linkPreviewState === 2) {
      this.linkPreviewState = 3;
    }
  }

  public async openCurrentLink(): Promise<void> {
    let url: string = this.currentLinkUrl();
    let context: common.Context | undefined = this.getUIContext().getHostContext();
    if (url.length === 0 || context === undefined) {
      return;
    }
    try {
      await (context as common.UIAbilityContext).startAbility({
        action: 'ohos.want.action.viewData',
        uri: url
      });
    } catch (error) {
      this.statusCode = 3;
    }
  }

  public desktopTextLooksLikeCode(text: string): boolean {
    let sourceText: string = text.trim();
    if (sourceText.length === 0 || this.desktopTextLooksLikeLink(sourceText)) {
      return false;
    }
    let normalizedText: string = sourceText.toLowerCase();
    let score: number = 0;
    if (normalizedText.indexOf('import ') === 0 || normalizedText.indexOf('export ') === 0 ||
      normalizedText.indexOf('package ') === 0 || normalizedText.indexOf('#include') === 0 ||
      normalizedText.indexOf('using ') === 0 || normalizedText.indexOf('namespace ') === 0 ||
      normalizedText.indexOf('fn ') === 0 || normalizedText.indexOf('func ') === 0) {
      score += 2;
    }
    if (normalizedText.indexOf('function ') >= 0 || normalizedText.indexOf('class ') >= 0 ||
      normalizedText.indexOf('interface ') >= 0 || normalizedText.indexOf('struct ') >= 0 ||
      normalizedText.indexOf('enum ') >= 0 || normalizedText.indexOf('const ') >= 0 ||
      normalizedText.indexOf('let ') >= 0 || normalizedText.indexOf('public ') >= 0 ||
      normalizedText.indexOf('private ') >= 0) {
      score += 2;
    }
    if (sourceText.indexOf('=>') >= 0 || sourceText.indexOf('===') >= 0 ||
      sourceText.indexOf('!==') >= 0 || sourceText.indexOf('::') >= 0 ||
      sourceText.indexOf('->') >= 0 || sourceText.indexOf(':=') >= 0) {
      score += 2;
    }
    if (sourceText.indexOf('\n') >= 0 || sourceText.indexOf('\r') >= 0) {
      score += 1;
    }
    if (sourceText.indexOf('{') >= 0 && sourceText.indexOf('}') >= 0) {
      score += 1;
    }
    if (sourceText.indexOf('(') >= 0 && sourceText.indexOf(')') >= 0) {
      score += 1;
    }
    if (sourceText.indexOf(';') >= 0) {
      score += 1;
    }
    if (sourceText.indexOf('```') >= 0 || normalizedText.indexOf('#!/') === 0) {
      score += 3;
    }
    if ((sourceText.indexOf('{') === 0 || sourceText.indexOf('[') === 0) &&
      sourceText.indexOf('\":') >= 0) {
      score += 3;
    }
    if ((normalizedText.indexOf('select ') === 0 && normalizedText.indexOf(' from ') > 0) ||
      normalizedText.indexOf('insert into ') === 0 || normalizedText.indexOf('create table ') === 0) {
      score += 3;
    }
    return score >= 3;
  }

  public desktopContentExtension(text: string): string {
    let normalizedText: string = text.trim().toLowerCase();
    let queryIndex: number = normalizedText.indexOf('?');
    if (queryIndex >= 0) {
      normalizedText = normalizedText.substring(0, queryIndex);
    }
    let fragmentIndex: number = normalizedText.indexOf('#');
    if (fragmentIndex >= 0) {
      normalizedText = normalizedText.substring(0, fragmentIndex);
    }
    let slashIndex: number = normalizedText.lastIndexOf('/');
    let backslashIndex: number = normalizedText.lastIndexOf('\\');
    let separatorIndex: number = slashIndex > backslashIndex ? slashIndex : backslashIndex;
    let fileName: string = normalizedText.substring(separatorIndex + 1);
    let dotIndex: number = fileName.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex >= fileName.length - 1) {
      return '';
    }
    let extension: string = fileName.substring(dotIndex + 1);
    return extension.length <= 10 ? extension : '';
  }

  public desktopExtensionIsImage(extension: string): boolean {
    return extension === 'jpg' || extension === 'jpeg' || extension === 'png' || extension === 'gif' ||
      extension === 'webp' || extension === 'bmp' || extension === 'svg' || extension === 'heic';
  }

  public desktopExtensionIsCode(extension: string): boolean {
    return extension === 'ts' || extension === 'ets' || extension === 'js' || extension === 'json' ||
      extension === 'rs' || extension === 'go' || extension === 'py' || extension === 'java' ||
      extension === 'c' || extension === 'h' || extension === 'cpp' || extension === 'css' ||
      extension === 'html' || extension === 'xml';
  }

  public desktopTypeMatchesFilter(kind: string, text: string): boolean {
    if (this.desktopTypeFilter === 1) {
      return kind === 'Text' && !this.desktopTextLooksRich(text);
    }
    if (this.desktopTypeFilter === 2) {
      return kind === 'RichText' || kind === 'Html' ||
        (kind === 'Text' && this.desktopTextLooksRich(text));
    }
    if (this.desktopTypeFilter === 3) {
      return kind === 'Image';
    }
    if (this.desktopTypeFilter === 4) {
      return kind === 'File' || kind === 'Folder';
    }
    return true;
  }

  public desktopTagMatchesFilter(kind: string, text: string): boolean {
    if (this.desktopTagFilter === 0) {
      return true;
    }
    let normalizedText: string = text.trim().toLowerCase();
    let extension: string = this.desktopContentExtension(text);
    if (this.desktopTagFilter === 1) {
      return this.desktopTextLooksLikeLink(text);
    }
    if (this.desktopTagFilter === 2) {
      return this.desktopExtensionIsCode(extension) || this.desktopTextLooksLikeCode(text);
    }
    if (this.desktopTagFilter === 3) {
      return kind === 'Image' || this.desktopExtensionIsImage(extension);
    }
    return kind === 'Folder' || normalizedText.endsWith('/') || normalizedText.endsWith('\\');
  }

  public desktopSourceMatchesFilter(serverItem: boolean): boolean {
    if (this.desktopSourceFilter === 1) {
      return serverItem;
    }
    if (this.desktopSourceFilter === 2) {
      return !serverItem;
    }
    return true;
  }

  public desktopExtensionMatchesFilter(text: string): boolean {
    if (this.desktopExtensionFilter.length === 0) {
      return true;
    }
    return this.desktopContentExtension(text) === this.desktopExtensionFilter;
  }

  public desktopTimeMatchesFilter(timestampMs: number): boolean {
    if (this.desktopTimeFilter === 0) {
      return true;
    }
    if (timestampMs <= 0) {
      return false;
    }
    let nowMs: number = Date.now();
    let nowDate: Date = new Date(nowMs);
    let todayStartMs: number = new Date(nowDate.getFullYear(), nowDate.getMonth(), nowDate.getDate()).getTime();
    let oneDayMs: number = 24 * 60 * 60 * 1000;
    if (this.desktopTimeFilter === 1) {
      return timestampMs >= todayStartMs && timestampMs <= nowMs;
    }
    if (this.desktopTimeFilter === 2) {
      return timestampMs >= todayStartMs - oneDayMs && timestampMs < todayStartMs;
    }
    if (this.desktopTimeFilter === 3) {
      return timestampMs >= nowMs - 7 * oneDayMs && timestampMs <= nowMs;
    }
    if (this.desktopTimeFilter === 4) {
      return timestampMs >= nowMs - 30 * oneDayMs && timestampMs <= nowMs;
    }
    if (this.desktopTimeFilter === 5) {
      let weekDay: number = nowDate.getDay();
      let daysFromMonday: number = weekDay === 0 ? 6 : weekDay - 1;
      return timestampMs >= todayStartMs - daysFromMonday * oneDayMs && timestampMs <= nowMs;
    }
    let monthStartMs: number = new Date(nowDate.getFullYear(), nowDate.getMonth(), 1).getTime();
    return timestampMs >= monthStartMs && timestampMs <= nowMs;
  }

  private historyFilterSignature(): string {
    let signature: string = this.historyRevision.toString() + '|' +
      this.historySearchText.trim().toLowerCase() + '|' +
      (this.desktopStarredOnly ? '1' : '0') + '|' + this.desktopTypeFilter.toString() + '|' +
      this.desktopTagFilter.toString() + '|' + this.desktopSourceFilter.toString() + '|' +
      this.desktopTimeFilter.toString() + '|' + this.desktopExtensionFilter + '|' +
      this.desktopCustomTagFilter + '|' + this.historyDeviceFilter + '|' +
      (this.historySnippetOnly ? '1' : '0');
    if (this.desktopTimeFilter > 0) {
      // Time filters compare against "now"; refresh the cache at minute resolution.
      signature += '|' + Math.floor(Date.now() / 60000).toString();
    }
    return signature;
  }

  public desktopFilteredServerHistory(): ServerHistoryItem[] {
    let signature: string = this.historyFilterSignature();
    if (historyFilterCache.serverSource === this.serverHistory &&
      historyFilterCache.serverSignature === signature) {
      return historyFilterCache.serverItems;
    }
    let items: ServerHistoryItem[] = [];
    if (this.historyDeviceFilter.length === 0 && this.desktopCustomTagFilter.length === 0 &&
      !this.historySnippetOnly) {
      for (let index: number = 0; index < this.serverHistory.length; index++) {
        let item: ServerHistoryItem = this.serverHistory[index];
        let starredMatches: boolean = !this.desktopStarredOnly || item.starred;
        if (starredMatches && this.desktopSearchMatches(item.text) && this.desktopSourceMatchesFilter(true) &&
          this.desktopTypeMatchesFilter(item.kind, item.text) && this.desktopTagMatchesFilter(item.kind, item.text) &&
          this.desktopTimeMatchesFilter(item.timestampMs) && this.desktopExtensionMatchesFilter(item.text)) {
          items.push(item);
        }
      }
    }
    historyFilterCache.serverItems = items;
    historyFilterCache.serverSource = this.serverHistory;
    historyFilterCache.serverSignature = signature;
    return items;
  }

  public desktopFilteredSessionHistory(): ClipboardHistoryItem[] {
    let signature: string = this.historyFilterSignature();
    if (historyFilterCache.sessionSource === this.history &&
      historyFilterCache.sessionSignature === signature) {
      return historyFilterCache.sessionItems;
    }
    let items: ClipboardHistoryItem[] = [];
    for (let index: number = 0; index < this.history.length; index++) {
      let item: ClipboardHistoryItem = this.history[index];
      let starredMatches: boolean = !this.desktopStarredOnly || item.starred;
      if (starredMatches && this.desktopSearchMatches(item.text) && this.desktopSourceMatchesFilter(false) &&
        this.desktopTypeMatchesFilter(item.kind, item.text) && this.desktopTagMatchesFilter(item.kind, item.text) &&
        this.desktopTimeMatchesFilter(item.timestampMs) && this.desktopExtensionMatchesFilter(item.text) &&
        this.historyItemMatchesLibraryFilters(item)) {
        items.push(item);
      }
    }
    historyFilterCache.sessionItems = items;
    historyFilterCache.sessionSource = this.history;
    historyFilterCache.sessionSignature = signature;
    return items;
  }

  public historyItemMatchesLibraryFilters(item: ClipboardHistoryItem): boolean {
    if (this.historySnippetOnly && !item.isSnippet) {
      return false;
    }
    if (this.historyDeviceFilter.length > 0 && item.sourceDevice !== this.historyDeviceFilter) {
      return false;
    }
    if (this.desktopCustomTagFilter.length > 0 && !this.historyItemHasTag(item, this.desktopCustomTagFilter)) {
      return false;
    }
    return true;
  }

  public compactFilteredHistory(): ClipboardHistoryItem[] {
    let signature: string = this.historyFilterSignature();
    if (historyFilterCache.compactSource === this.history &&
      historyFilterCache.compactSignature === signature) {
      return historyFilterCache.compactItems;
    }
    let items: ClipboardHistoryItem[] = [];
    for (let index: number = 0; index < this.history.length; index++) {
      let item: ClipboardHistoryItem = this.history[index];
      if (this.desktopSearchMatches(item.text) && this.historyItemMatchesLibraryFilters(item)) {
        items.push(item);
      }
    }
    historyFilterCache.compactItems = items;
    historyFilterCache.compactSource = this.history;
    historyFilterCache.compactSignature = signature;
    return items;
  }

  public desktopServerHistoryDataSource(): HistoryDataSource<ServerHistoryItem> {
    this.serverHistoryDataSourceInstance.reload(this.desktopFilteredServerHistory());
    return this.serverHistoryDataSourceInstance;
  }

  public desktopSessionHistoryDataSource(): HistoryDataSource<ClipboardHistoryItem> {
    this.sessionHistoryDataSourceInstance.reload(this.desktopFilteredSessionHistory());
    return this.sessionHistoryDataSourceInstance;
  }

  public historyDeviceOptions(): string[] {
    let devices: string[] = [];
    for (let index: number = 0; index < this.history.length; index++) {
      let name: string = this.history[index].sourceDevice.trim();
      if (name.length > 0 && devices.indexOf(name) < 0) {
        devices.push(name);
      }
    }
    return devices;
  }

  public historyTagOptions(): string[] {
    let tags: string[] = [];
    for (let itemIndex: number = 0; itemIndex < this.history.length; itemIndex++) {
      let item: ClipboardHistoryItem = this.history[itemIndex];
      for (let tagIndex: number = 0; tagIndex < item.tags.length; tagIndex++) {
        let tag: string = item.tags[tagIndex];
        if (tag.length > 0 && tags.indexOf(tag) < 0) {
          tags.push(tag);
        }
      }
    }
    return tags;
  }

  public historyItemHasTag(item: ClipboardHistoryItem, tag: string): boolean {
    for (let index: number = 0; index < item.tags.length; index++) {
      if (item.tags[index] === tag) {
        return true;
      }
    }
    return false;
  }

  public async selectDesktopServerItem(item: ServerHistoryItem): Promise<void> {
    this.desktopSelectedId = item.id;
    this.desktopSelectedText = item.text;
    this.desktopSelectedMeta = item.kind + ' · ' + item.time;
    this.desktopSelectedDirection = '';
    this.desktopGestureShareHintDismissed = false;
    this.desktopSelectedImage = null;
    this.desktopSelectedImageRevision += 1;
    this.desktopSelectedFileData = null;
    this.desktopSelectedFilePath = '';
    this.desktopFilePreviewState = 0;
    this.resetDesktopVideoAspectRatio();
    this.releaseDesktopAudio();
    this.refreshCurrentLinkPreview();
    if (!item.hasData || (item.kind !== 'File' && item.kind !== 'Image')) {
      return;
    }
    let context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      this.desktopFilePreviewState = 2;
      return;
    }
    if (item.kind === 'File') {
      let cachedPath: string = this.historyStorageService.findServerFile(context, item.id, item.text);
      if (cachedPath.length > 0) {
        this.desktopSelectedFilePath = cachedPath;
        return;
      }
    }
    this.desktopFilePreviewState = 1;
    try {
      let client: MobileSyncClient = new MobileSyncClient(this.getConfig());
      let data: Uint8Array = await client.getHistoryPayload(item);
      if (this.desktopSelectedId !== item.id || data.length === 0) {
        return;
      }
      if (item.kind === 'Image') {
        this.desktopSelectedImage = await this.clipboardService.decodeImage(data);
        this.desktopSelectedImageRevision += 1;
      } else {
        let filePath: string = this.historyStorageService.storeServerFile(context, item.id, item.text, data);
        if (filePath.length === 0) {
          throw new Error('failed to persist server history file');
        }
        this.desktopSelectedFilePath = filePath;
      }
      this.desktopFilePreviewState = 0;
    } catch (error) {
      if (this.desktopSelectedId === item.id) {
        this.desktopFilePreviewState = 2;
      }
    }
  }

  public selectDesktopSessionItem(item: ClipboardHistoryItem): void {
    this.desktopSelectedId = item.id;
    this.desktopSelectedText = item.text;
    this.desktopSelectedMeta = item.time;
    this.desktopSelectedDirection = item.direction;
    this.desktopGestureShareHintDismissed = false;
    this.desktopSelectedImage = item.imagePreview;
    this.desktopSelectedImageRevision += 1;
    this.desktopSelectedFileData = item.fileData;
    this.desktopSelectedFilePath = item.filePath;
    this.desktopFilePreviewState = 0;
    this.resetDesktopVideoAspectRatio();
    this.releaseDesktopAudio();
    this.refreshCurrentLinkPreview();
  }

  public desktopDetailText(): string {
    if (this.desktopSelectedText.length > 0) {
      return this.desktopSelectedText;
    }
    return this.latestText;
  }

  public desktopShowsLatestImage(): boolean {
    return this.desktopDisplayImage() !== null;
  }

  public desktopDisplayImage(): image.PixelMap | null {
    if (this.desktopSelectedId.length > 0) {
      return this.desktopSelectedImage;
    }
    return this.latestKind === 'Image' ? this.latestImage : null;
  }

  public desktopShowsFile(): boolean {
    if (this.desktopSelectedId.length > 0) {
      return this.desktopSelectedFileData !== null || this.desktopSelectedFilePath.length > 0;
    }
    return this.latestKind === 'File' &&
      (this.latestFileData !== null || this.latestFilePath.length > 0);
  }

  public desktopFileName(): string {
    if (this.desktopSelectedId.length > 0) {
      return this.desktopSelectedText;
    }
    return this.latestFileName.length > 0 ? this.latestFileName : this.latestText;
  }

  public desktopFileSourcePath(): string {
    if (this.desktopSelectedId.length > 0) {
      return this.desktopSelectedFilePath;
    }
    return this.latestFilePath;
  }

  public desktopFilePreviewUri(): string {
    let sourcePath: string = this.desktopFileSourcePath();
    if (sourcePath.length === 0) {
      return '';
    }
    if (!sourcePath.startsWith('/')) {
      return sourcePath;
    }
    try {
      return fileUri.getUriFromPath(sourcePath);
    } catch (error) {
      return '';
    }
  }

  public async registerDesktopGestureShare(): Promise<void> {
    if (this.desktopGestureShareWindowId >= 0 || this.desktopGestureShareRegistering ||
      !this.desktopGestureSharePageVisible) {
      return;
    }
    if (!canIUse('SystemCapability.Collaboration.HarmonyShare')) {
      this.desktopGestureShareState = 5;
      return;
    }
    let context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      this.desktopGestureShareState = 4;
      return;
    }
    this.desktopGestureShareRegistering = true;
    try {
      let mainWindow: window.Window = await window.getLastWindow(context);
      if (!this.desktopGestureSharePageVisible) {
        return;
      }
      let windowId: number = mainWindow.getWindowProperties().id;
      let capability: harmonyShare.SendCapabilityRegistry = {
        windowId: windowId,
        sendOnly: true
      };
      harmonyShare.on('gesturesShare', capability, (target: harmonyShare.SharableTarget): void => {
        this.shareDesktopContentByGesture(target);
      });
      this.desktopGestureShareWindowId = windowId;
      this.desktopGestureShareState = 1;
    } catch (error) {
      logger.error('UniClipboard failed to register gesturesShare.');
      this.desktopGestureShareState = 4;
    } finally {
      this.desktopGestureShareRegistering = false;
    }
  }

  public unregisterDesktopGestureShare(): void {
    let windowId: number = this.desktopGestureShareWindowId;
    this.desktopGestureShareWindowId = -1;
    if (this.desktopGestureShareResetTimerId >= 0) {
      clearTimeout(this.desktopGestureShareResetTimerId);
      this.desktopGestureShareResetTimerId = -1;
    }
    if (windowId < 0 || !canIUse('SystemCapability.Collaboration.HarmonyShare')) {
      return;
    }
    let capability: harmonyShare.SendCapabilityRegistry = {
      windowId: windowId,
      sendOnly: true
    };
    try {
      harmonyShare.off('gesturesShare', capability);
    } catch (error) {
      logger.error('UniClipboard failed to unregister gesturesShare.');
    }
  }

  public resetDesktopGestureShareStateLater(): void {
    if (this.desktopGestureShareResetTimerId >= 0) {
      clearTimeout(this.desktopGestureShareResetTimerId);
    }
    this.desktopGestureShareResetTimerId = setTimeout((): void => {
      this.desktopGestureShareResetTimerId = -1;
      if (this.desktopGestureShareWindowId >= 0) {
        this.desktopGestureShareState = 1;
      }
    }, 2200);
  }

  public desktopHasGestureShareContent(): boolean {
    return this.desktopShowsFile() || this.desktopShowsLatestImage() || this.desktopDetailText().trim().length > 0;
  }

  public desktopGestureShareContentKind(): number {
    if (this.desktopShowsFile()) {
      return this.desktopGestureShareFileContentKind();
    }
    if (this.desktopShowsLatestImage()) {
      return 2;
    }
    if (this.desktopDetailText().trim().length > 0) {
      return 3;
    }
    return 0;
  }

  public desktopGestureShareFileUtd(): string {
    let extension: string = this.desktopFileExtension();
    if (extension.length === 0) {
      return uniformTypeDescriptor.UniformDataType.FILE;
    }
    try {
      let utdType: string = uniformTypeDescriptor.getUniformDataTypeByFilenameExtension('.' + extension);
      if (utdType.length === 0 || utdType.startsWith('flex.')) {
        return uniformTypeDescriptor.UniformDataType.FILE;
      }
      return utdType;
    } catch (error) {
      return uniformTypeDescriptor.UniformDataType.FILE;
    }
  }

  public desktopGestureShareFileContentKind(): number {
    let utdType: string = this.desktopGestureShareFileUtd();
    if (utdType === 'com.adobe.pdf') {
      return 7;
    }
    if (utdType === 'com.microsoft.word.doc' ||
      utdType === 'org.openxmlformats.wordprocessingml.document') {
      return 9;
    }
    if (utdType === 'com.microsoft.excel.xls' ||
      utdType === 'org.openxmlformats.spreadsheetml.sheet') {
      return 10;
    }
    if (utdType === 'com.microsoft.powerpoint.ppt' ||
      utdType === 'org.openxmlformats.presentationml.presentation') {
      return 11;
    }
    if (utdType === uniformTypeDescriptor.UniformDataType.FILE) {
      return 1;
    }
    try {
      let typeDescriptor: uniformTypeDescriptor.TypeDescriptor =
        uniformTypeDescriptor.getTypeDescriptor(utdType);
      if (typeDescriptor.belongsTo(uniformTypeDescriptor.UniformDataType.IMAGE)) {
        return 4;
      }
      if (typeDescriptor.belongsTo(uniformTypeDescriptor.UniformDataType.VIDEO)) {
        return 5;
      }
      if (typeDescriptor.belongsTo(uniformTypeDescriptor.UniformDataType.AUDIO)) {
        return 6;
      }
      if (typeDescriptor.belongsTo('general.archive')) {
        return 8;
      }
      if (typeDescriptor.belongsTo('general.text') || typeDescriptor.belongsTo('general.composite-object')) {
        return 12;
      }
    } catch (error) {
      return 1;
    }
    return 1;
  }

  public async createDesktopGestureImageUri(): Promise<string> {
    let pixelMap: image.PixelMap | null = this.desktopDisplayImage();
    let context: common.Context | undefined = this.getUIContext().getHostContext();
    if (pixelMap === null || context === undefined) {
      return '';
    }
    let targetPath: string = context.cacheDir + '/uniclipboard-gesture-share.png';
    let targetFile: fileIo.File | null = null;
    let packer: image.ImagePacker | null = null;
    try {
      targetFile = fileIo.openSync(targetPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      packer = image.createImagePacker();
      let options: image.PackingOption = {
        format: 'image/png',
        quality: 100
      };
      await packer.packToFile(pixelMap, targetFile.fd, options);
      return fileUri.getUriFromPath(targetPath);
    } catch (error) {
      logger.error('UniClipboard failed to prepare the gesture share image.');
      return '';
    } finally {
      if (packer !== null) {
        try {
          await packer.release();
        } catch (error) {
        }
      }
      if (targetFile !== null) {
        try {
          fileIo.closeSync(targetFile.fd);
        } catch (error) {
        }
      }
    }
  }

  public async createDesktopGestureShareRecord(): Promise<systemShare.SharedRecord | null> {
    if (this.desktopShowsFile()) {
      let fileUriValue: string = this.desktopFilePreviewUri();
      let fileName: string = this.desktopFileName();
      if (fileUriValue.length === 0 || fileName.length === 0) {
        return null;
      }
      let utdType: string = this.desktopGestureShareFileUtd();
      let fileRecord: systemShare.SharedRecord = {
        utd: utdType,
        uri: fileUriValue,
        title: fileName,
        description: fileName
      };
      return fileRecord;
    }
    if (this.desktopShowsLatestImage()) {
      let imageUri: string = await this.createDesktopGestureImageUri();
      if (imageUri.length === 0) {
        return null;
      }
      let imageRecord: systemShare.SharedRecord = {
        utd: uniformTypeDescriptor.UniformDataType.PNG,
        uri: imageUri,
        thumbnailUri: imageUri
      };
      return imageRecord;
    }
    let textContent: string = this.desktopDetailText();
    if (textContent.trim().length > 0) {
      let textRecord: systemShare.SharedRecord = {
        utd: uniformTypeDescriptor.UniformDataType.PLAIN_TEXT,
        content: textContent,
        title: textContent.length > 40 ? textContent.substring(0, 40) : textContent
      };
      return textRecord;
    }
    return null;
  }

  public async shareDesktopContentByGesture(target: harmonyShare.SharableTarget): Promise<void> {
    if (!this.desktopHasGestureShareContent() || this.desktopGestureShareState === 2) {
      try {
        await target.reject(harmonyShare.SharableErrorCode.NO_CONTENT_ERROR);
      } catch (error) {
      }
      return;
    }
    this.desktopGestureShareState = 2;
    try {
      let record: systemShare.SharedRecord | null = await this.createDesktopGestureShareRecord();
      if (record === null) {
        this.desktopGestureShareState = 4;
        await target.reject(harmonyShare.SharableErrorCode.NO_CONTENT_ERROR);
        this.resetDesktopGestureShareStateLater();
        return;
      }
      let shareData: systemShare.SharedData = new systemShare.SharedData(record);
      await target.share(shareData);
      this.desktopGestureShareState = 3;
    } catch (error) {
      logger.error('UniClipboard gesturesShare failed.');
      this.desktopGestureShareState = 4;
    }
    this.resetDesktopGestureShareStateLater();
  }

  public desktopFileExtension(): string {
    let fileName: string = this.desktopFileName();
    let dotIndex: number = fileName.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex >= fileName.length - 1) {
      return '';
    }
    return fileName.substring(dotIndex + 1).toLowerCase();
  }

  public desktopFileMimeType(): string {
    let extension: string = this.desktopFileExtension();
    switch (extension) {
      case 'txt':
        return 'text/plain';
      case 'cpp':
        return 'text/x-c++src';
      case 'c':
        return 'text/x-csrc';
      case 'h':
        return 'text/x-chdr';
      case 'java':
        return 'text/x-java';
      case 'xhtml':
        return 'application/xhtml+xml';
      case 'xml':
        return 'text/xml';
      case 'html':
      case 'htm':
        return 'text/html';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      case 'svg':
        return 'image/svg+xml';
      case 'm4a':
        return 'audio/mp4a-latm';
      case 'aac':
        return 'audio/aac';
      case 'mp3':
        return 'audio/mpeg';
      case 'ogg':
        return 'audio/ogg';
      case 'wav':
        return 'audio/x-wav';
      case 'mp4':
        return 'video/mp4';
      case 'mkv':
        return 'video/x-matroska';
      case 'ts':
        return 'video/mp2ts';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'csv':
        return 'text/csv';
      case 'ofd':
        return 'general.ofd';
      default:
        return '';
    }
  }

  public desktopFileIsVideo(): boolean {
    let extension: string = this.desktopFileExtension();
    return extension === 'mp4' || extension === 'mkv' || extension === 'ts' ||
      extension === 'avi' || extension === 'mov' || extension === 'webm' ||
      extension === 'm4v' || extension === '3gp' || extension === 'mpeg' ||
      extension === 'mpg' || extension === 'ogv' || extension === 'flv';
  }

  public desktopFileIsAudio(): boolean {
    let extension: string = this.desktopFileExtension();
    return extension === 'm4a' || extension === 'aac' || extension === 'mp3' ||
      extension === 'ogg' || extension === 'wav' || extension === 'flac' ||
      extension === 'opus' || extension === 'ape' || extension === 'amr' ||
      extension === 'midi' || extension === 'mid';
  }

  public async releaseDesktopAudio(): Promise<void> {
    let player: media.AVPlayer | null = this.desktopAudioPlayer;
    let sourceFile: fileIo.File | null = this.desktopAudioSourceFile;
    this.desktopAudioPlayer = null;
    this.desktopAudioSourceFile = null;
    this.desktopAudioKey = '';
    this.desktopAudioPlayWhenReady = false;
    this.desktopAudioState = 0;
    this.desktopAudioPosition = 0;
    this.desktopAudioDuration = 0;
    this.desktopAudioSeeking = false;
    this.resetDesktopAudioMetadata();
    if (player !== null) {
      try {
        await player.release();
      } catch (error) {
        logger.error('UniClipboard failed to release the audio player.');
      }
    }
    if (sourceFile !== null) {
      try {
        fileIo.closeSync(sourceFile.fd);
      } catch (error) {
        logger.error('UniClipboard failed to close the audio preview file.');
      }
    }
  }

  public async prepareDesktopAudioPlayer(player: media.AVPlayer, previewKey: string): Promise<void> {
    if (this.desktopAudioPlayer !== player || this.desktopAudioKey !== previewKey ||
      player.state !== 'initialized') {
      return;
    }
    try {
      await player.prepare();
    } catch (error) {
      if (this.desktopAudioPlayer === player && this.desktopAudioKey === previewKey) {
        this.desktopAudioState = 5;
      }
    }
  }

  public async prepareDesktopAudio(): Promise<void> {
    if (!this.desktopFileIsAudio()) {
      return;
    }
    let sourcePath: string = this.desktopFileSourcePath();
    let previewKey: string = this.desktopFilePreviewKey();
    if (sourcePath.length === 0 || (this.desktopAudioKey === previewKey && this.desktopAudioPlayer !== null)) {
      return;
    }
    await this.releaseDesktopAudio();
    if (!this.desktopFileIsAudio() || this.desktopFilePreviewKey() !== previewKey) {
      return;
    }
    this.desktopAudioKey = previewKey;
    this.desktopAudioState = 1;
    this.loadDesktopAudioMetadata(sourcePath, previewKey);
    try {
      let sourceFile: fileIo.File = fileIo.openSync(sourcePath, fileIo.OpenMode.READ_ONLY);
      this.desktopAudioSourceFile = sourceFile;
      let sourceStat: fileIo.Stat = fileIo.statSync(sourceFile.fd);
      let sourceDescriptor: media.AVFileDescriptor = {
        fd: sourceFile.fd,
        offset: 0,
        length: sourceStat.size
      };
      let player: media.AVPlayer | null = null;
      if (canIUse('SystemCapability.Multimedia.Media.Core')) {
        if (canIUse('SystemCapability.Multimedia.Media.AVPlayer')) {
          player = await media.createAVPlayer();
        }
      }
      if (player === null) {
        this.desktopAudioState = 5;
        return;
      }
      let activePlayer: media.AVPlayer = player;
      if (this.desktopAudioKey !== previewKey) {
        await activePlayer.release();
        return;
      }
      this.desktopAudioPlayer = activePlayer;
      activePlayer.on('stateChange', (state: media.AVPlayerState, _reason: media.StateChangeReason): void => {
        if (this.desktopAudioPlayer !== activePlayer || this.desktopAudioKey !== previewKey) {
          return;
        }
        if (state === 'initialized') {
          this.prepareDesktopAudioPlayer(activePlayer, previewKey);
        } else if (state === 'prepared') {
          this.desktopAudioDuration = activePlayer.duration > 0 ? activePlayer.duration : 0;
          this.desktopAudioState = 2;
          if (this.desktopAudioPlayWhenReady) {
            this.playDesktopAudio();
          }
        } else if (state === 'playing') {
          this.desktopAudioState = 3;
        } else if (state === 'paused') {
          this.desktopAudioState = 2;
        } else if (state === 'completed') {
          this.desktopAudioPosition = this.desktopAudioDuration;
          this.desktopAudioState = 4;
        } else if (state === 'stopped') {
          this.desktopAudioPosition = 0;
          this.desktopAudioState = 2;
        } else if (state === 'error') {
          this.desktopAudioState = 5;
        }
      });
      activePlayer.on('timeUpdate', (position: number): void => {
        if (this.desktopAudioPlayer === activePlayer && this.desktopAudioKey === previewKey &&
          !this.desktopAudioSeeking) {
          this.desktopAudioPosition = position;
        }
      });
      activePlayer.on('durationUpdate', (duration: number): void => {
        if (this.desktopAudioPlayer === activePlayer && this.desktopAudioKey === previewKey) {
          this.desktopAudioDuration = duration > 0 ? duration : 0;
        }
      });
      activePlayer.on('error', (_error: BusinessError): void => {
        if (this.desktopAudioPlayer === activePlayer && this.desktopAudioKey === previewKey) {
          this.desktopAudioState = 5;
        }
      });
      activePlayer.fdSrc = sourceDescriptor;
    } catch (error) {
      await this.releaseDesktopAudio();
      this.desktopAudioState = 5;
    }
  }

  public async playDesktopAudio(): Promise<void> {
    let player: media.AVPlayer | null = this.desktopAudioPlayer;
    if (player === null) {
      this.desktopAudioPlayWhenReady = true;
      await this.prepareDesktopAudio();
      return;
    }
    if (player.state !== 'prepared' && player.state !== 'paused' && player.state !== 'completed') {
      this.desktopAudioPlayWhenReady = true;
      return;
    }
    try {
      this.desktopAudioPlayWhenReady = false;
      if (player.state === 'completed') {
        this.desktopAudioPosition = 0;
      }
      await player.play();
    } catch (error) {
      this.desktopAudioState = 5;
    }
  }

  public async toggleDesktopAudioPlayback(): Promise<void> {
    let player: media.AVPlayer | null = this.desktopAudioPlayer;
    if (player !== null && player.state === 'playing') {
      try {
        await player.pause();
      } catch (error) {
        this.desktopAudioState = 5;
      }
      return;
    }
    await this.playDesktopAudio();
  }

  public seekDesktopAudio(position: number): void {
    let player: media.AVPlayer | null = this.desktopAudioPlayer;
    if (player === null || this.desktopAudioDuration <= 0) {
      return;
    }
    if (player.state === 'prepared' || player.state === 'playing' || player.state === 'paused' ||
      player.state === 'completed') {
      player.seek(Math.floor(position));
    }
  }

  public formatAudioTime(timeMs: number): string {
    let safeTime: number = Math.max(0, timeMs);
    let totalSeconds: number = Math.floor(safeTime / 1000);
    let minutes: number = Math.floor(totalSeconds / 60);
    let seconds: number = totalSeconds % 60;
    return minutes.toString() + ':' + (seconds < 10 ? '0' : '') + seconds.toString();
  }

  public resetDesktopAudioMetadata(): void {
    this.desktopAudioCover = null;
    this.desktopAudioCoverRevision++;
    this.desktopAudioTitle = '';
    this.desktopAudioArtist = '';
    this.desktopAudioAlbum = '';
    this.desktopAudioLyrics = [];
    this.desktopAudioPlainLyrics = '';
    this.desktopAudioMetadataState = 0;
  }

  public desktopAudioDisplayTitle(): string {
    return this.desktopAudioTitle.length > 0 ? this.desktopAudioTitle : this.desktopFileName();
  }

  public desktopAudioDisplayArtist(): string {
    if (this.desktopAudioArtist.length > 0 && this.desktopAudioAlbum.length > 0) {
      return this.desktopAudioArtist + ' · ' + this.desktopAudioAlbum;
    }
    return this.desktopAudioArtist.length > 0 ? this.desktopAudioArtist : this.desktopAudioAlbum;
  }

  public embeddedLyricsFromMetadata(metadata: media.AVMetadata): string {
    let customInfo: Record<string, string> | undefined = metadata.customInfo;
    if (customInfo === undefined) {
      return '';
    }
    let keys: string[] = Object.keys(customInfo);
    for (let index: number = 0; index < keys.length; index++) {
      let key: string = keys[index];
      let normalizedKey: string = key.toLowerCase();
      if (normalizedKey === 'lyrics' || normalizedKey === 'lyric' ||
        normalizedKey === 'unsyncedlyrics' || normalizedKey === 'syncedlyrics' ||
        normalizedKey === 'lrc' || normalizedKey === '©lyr') {
        let value: string | undefined = customInfo[key];
        if (value !== undefined && value.trim().length > 0) {
          return value;
        }
      }
    }
    return '';
  }

  public loadDesktopSidecarLyrics(sourcePath: string): string {
    let dotIndex: number = sourcePath.lastIndexOf('.');
    if (dotIndex <= 0) {
      return '';
    }
    let basePath: string = sourcePath.substring(0, dotIndex);
    let candidates: string[] = [basePath + '.lrc', basePath + '.LRC'];
    for (let index: number = 0; index < candidates.length; index++) {
      let lyricPath: string = candidates[index];
      try {
        if (fileIo.accessSync(lyricPath)) {
          return fileIo.readTextSync(lyricPath);
        }
      } catch (error) {
        logger.error('UniClipboard failed to read the sidecar lyric file.');
      }
    }
    return '';
  }

  public parseDesktopLyricTime(tag: string): number {
    let colonIndex: number = tag.indexOf(':');
    if (colonIndex <= 0 || colonIndex >= tag.length - 1) {
      return -1;
    }
    let minuteText: string = tag.substring(0, colonIndex);
    let secondText: string = tag.substring(colonIndex + 1);
    let minutes: number = Number.parseInt(minuteText);
    let seconds: number = Number.parseFloat(secondText);
    if (!Number.isFinite(minutes) || !Number.isFinite(seconds) || minutes < 0 || seconds < 0) {
      return -1;
    }
    return Math.floor((minutes * 60 + seconds) * 1000);
  }

  public parseDesktopLyrics(lyricText: string): void {
    let normalizedText: string = lyricText.replace(/\r/g, '');
    let rawLines: string[] = normalizedText.split('\n');
    let parsedLines: AudioLyricLine[] = [];
    let hasTimedLine: boolean = false;
    for (let lineIndex: number = 0; lineIndex < rawLines.length; lineIndex++) {
      let rawLine: string = rawLines[lineIndex].trim();
      let cursor: number = 0;
      let lineTimes: number[] = [];
      while (cursor < rawLine.length && rawLine.substring(cursor, cursor + 1) === '[') {
        let closeIndex: number = rawLine.indexOf(']', cursor + 1);
        if (closeIndex < 0) {
          break;
        }
        let tag: string = rawLine.substring(cursor + 1, closeIndex);
        let timeMs: number = this.parseDesktopLyricTime(tag);
        if (timeMs >= 0) {
          lineTimes.push(timeMs);
        }
        cursor = closeIndex + 1;
      }
      let lineText: string = rawLine.substring(cursor).trim();
      if (lineTimes.length > 0 && lineText.length > 0) {
        hasTimedLine = true;
        for (let timeIndex: number = 0; timeIndex < lineTimes.length; timeIndex++) {
          parsedLines.push(new AudioLyricLine(lineTimes[timeIndex], lineText));
        }
      }
    }
    if (hasTimedLine) {
      parsedLines.sort((left: AudioLyricLine, right: AudioLyricLine): number => left.timeMs - right.timeMs);
      this.desktopAudioLyrics = parsedLines;
      this.desktopAudioPlainLyrics = '';
    } else {
      this.desktopAudioLyrics = [];
      this.desktopAudioPlainLyrics = normalizedText.trim();
    }
  }

  public desktopCurrentLyricIndex(): number {
    if (this.desktopAudioLyrics.length === 0) {
      return -1;
    }
    let currentIndex: number = 0;
    for (let index: number = 0; index < this.desktopAudioLyrics.length; index++) {
      if (this.desktopAudioLyrics[index].timeMs <= this.desktopAudioPosition) {
        currentIndex = index;
      } else {
        break;
      }
    }
    return currentIndex;
  }

  public desktopLyricTextAtOffset(offset: number): string {
    let index: number = this.desktopCurrentLyricIndex() + offset;
    if (index < 0 || index >= this.desktopAudioLyrics.length) {
      return '';
    }
    return this.desktopAudioLyrics[index].text;
  }

  public async loadDesktopAudioMetadata(sourcePath: string, previewKey: string): Promise<void> {
    if (this.desktopAudioKey !== previewKey) {
      return;
    }
    this.desktopAudioMetadataState = 1;
    let sidecarLyrics: string = this.loadDesktopSidecarLyrics(sourcePath);
    if (sidecarLyrics.trim().length > 0 && this.desktopAudioKey === previewKey) {
      this.parseDesktopLyrics(sidecarLyrics);
    }
    let extractor: media.AVMetadataExtractor | null = null;
    let sourceFile: fileIo.File | null = null;
    try {
      sourceFile = fileIo.openSync(sourcePath, fileIo.OpenMode.READ_ONLY);
      let sourceStat: fileIo.Stat = fileIo.statSync(sourceFile.fd);
      let sourceDescriptor: media.AVFileDescriptor = {
        fd: sourceFile.fd,
        offset: 0,
        length: sourceStat.size
      };
      if (canIUse('SystemCapability.Multimedia.Media.Core')) {
        if (canIUse('SystemCapability.Multimedia.Media.AVMetadataExtractor')) {
          extractor = await media.createAVMetadataExtractor();
        }
      }
      if (extractor === null) {
        this.desktopAudioMetadataState = 2;
        return;
      }
      extractor.fdSrc = sourceDescriptor;
      try {
        let metadata: media.AVMetadata = await extractor.fetchMetadata();
        if (this.desktopAudioKey === previewKey) {
          this.desktopAudioTitle = metadata.title === undefined ? '' : metadata.title;
          if (metadata.artist !== undefined) {
            this.desktopAudioArtist = metadata.artist;
          } else if (metadata.albumArtist !== undefined) {
            this.desktopAudioArtist = metadata.albumArtist;
          }
          this.desktopAudioAlbum = metadata.album === undefined ? '' : metadata.album;
          if (sidecarLyrics.trim().length === 0) {
            let embeddedLyrics: string = this.embeddedLyricsFromMetadata(metadata);
            if (embeddedLyrics.trim().length > 0) {
              this.parseDesktopLyrics(embeddedLyrics);
            }
          }
        }
      } catch (error) {
        logger.error('UniClipboard failed to read the audio metadata.');
      }
      try {
        let cover: image.PixelMap = await extractor.fetchAlbumCover();
        if (this.desktopAudioKey === previewKey) {
          this.desktopAudioCover = cover;
          this.desktopAudioCoverRevision++;
        }
      } catch (error) {
        logger.info('UniClipboard audio file has no embedded cover.');
      }
    } catch (error) {
      logger.error('UniClipboard failed to open the audio metadata source.');
    } finally {
      if (extractor !== null) {
        try {
          await extractor.release();
        } catch (error) {
        }
      }
      if (sourceFile !== null) {
        try {
          fileIo.closeSync(sourceFile.fd);
        } catch (error) {
        }
      }
      if (this.desktopAudioKey === previewKey) {
        this.desktopAudioMetadataState = 2;
      }
    }
  }

  public desktopFileIsDocument(): boolean {
    let extension: string = this.desktopFileExtension();
    return extension === 'csv' || extension === 'ofd' ||
      extension === 'txt' || extension === 'rtf' || extension === 'md' ||
      extension === 'html' || extension === 'htm' || extension === 'xml';
  }

  public desktopFilePreviewKey(): string {
    if (this.desktopSelectedId.length > 0) {
      return this.desktopSelectedId;
    }
    return this.latestFileRevision.toString();
  }

  public currentImageRecognitionKey(): string {
    if (this.desktopSelectedId.length > 0 && this.desktopSelectedImage !== null) {
      return 'selected:' + this.desktopSelectedId + ':' + this.desktopSelectedImageRevision.toString();
    }
    if (this.latestKind === 'Image' && this.latestImage !== null) {
      return 'latest:' + this.latestImageRevision.toString();
    }
    return '';
  }

  public currentImageRecognitionState(): number {
    return this.imageRecognitionSourceKey === this.currentImageRecognitionKey() ? this.imageRecognitionState : 0;
  }

  public currentImageRecognizedText(): string {
    return this.imageRecognitionSourceKey === this.currentImageRecognitionKey() ? this.imageRecognizedText : '';
  }

  public currentImageSmartActions(): ImageSmartAction[] {
    if (this.imageRecognitionSourceKey === this.currentImageRecognitionKey()) {
      return this.imageSmartActions;
    }
    return [];
  }

  private async packImageForRecognition(pixelMap: image.PixelMap): Promise<ArrayBuffer> {
    let packer: image.ImagePacker = image.createImagePacker();
    let options: image.PackingOption = {
      format: 'image/png',
      quality: 100
    };
    try {
      return await packer.packToData(pixelMap, options);
    } finally {
      await packer.release();
    }
  }

  private async createOcrPixelMap(packedImage: ArrayBuffer): Promise<image.PixelMap> {
    let source: image.ImageSource = image.createImageSource(packedImage);
    let options: image.DecodingOptions = {
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888
    };
    try {
      return await source.createPixelMap(options);
    } finally {
      await source.release();
    }
  }

  private imageSmartActionExists(actions: ImageSmartAction[], kind: string, value: string): boolean {
    for (let index: number = 0; index < actions.length; index++) {
      let action: ImageSmartAction = actions[index];
      if (action.kind === kind && action.value === value) {
        return true;
      }
    }
    return false;
  }

  private appendImageSmartAction(actions: ImageSmartAction[], kind: string, value: string): void {
    let normalizedValue: string = value.trim();
    if (normalizedValue.length === 0 || this.imageSmartActionExists(actions, kind, normalizedValue)) {
      return;
    }
    actions.push(new ImageSmartAction(kind, normalizedValue));
  }

  private trimDetectedLink(value: string): string {
    let result: string = value.trim();
    let trailingMarks: string = '.,;:!?)]}，。；：！？）】》';
    while (result.length > 0 && trailingMarks.indexOf(result.charAt(result.length - 1)) >= 0) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  private extractImageTextActions(text: string, actions: ImageSmartAction[]): void {
    let linkPattern: RegExp = /(https?:\/\/[^\s<>"']+|www\.[^\s<>"']+)/gi;
    let linkMatch: RegExpExecArray | null = linkPattern.exec(text);
    while (linkMatch !== null) {
      let link: string = this.trimDetectedLink(linkMatch[0]);
      if (link.length > 0) {
        this.appendImageSmartAction(actions, 'link', link);
      }
      linkMatch = linkPattern.exec(text);
    }

    let phonePattern: RegExp = /(?:\+?\d[\d\s\-()]{5,}\d)/g;
    let phoneMatch: RegExpExecArray | null = phonePattern.exec(text);
    while (phoneMatch !== null) {
      let candidate: string = phoneMatch[0].trim();
      let digits: string = candidate.replace(/\D/g, '');
      if (digits.length >= 7 && digits.length <= 15) {
        let normalizedPhone: string = candidate.charAt(0) === '+' ? '+' + digits : digits;
        this.appendImageSmartAction(actions, 'phone', normalizedPhone);
      }
      phoneMatch = phonePattern.exec(text);
    }
  }

  private async detectImageQrCodes(packedImage: ArrayBuffer, actions: ImageSmartAction[]): Promise<boolean> {
    let context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      return false;
    }
    let imagePath: string = context.cacheDir + '/uniclipboard-image-recognition.png';
    let targetFile: fileIo.File | null = null;
    try {
      targetFile = fileIo.openSync(imagePath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(targetFile.fd, packedImage);
      fileIo.closeSync(targetFile.fd);
      targetFile = null;
      let inputImage: detectBarcode.InputImage = {
        uri: fileUri.getUriFromPath(imagePath)
      };
      let options: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.QR_CODE],
        enableMultiMode: true
      };
      if (canIUse('SystemCapability.Multimedia.Scan.ScanBarcode')) {
        let results: scanBarcode.ScanResult[] = await detectBarcode.decode(inputImage, options);
        for (let index: number = 0; index < results.length; index++) {
          this.appendImageSmartAction(actions, 'qr', results[index].originalValue);
        }
        return true;
      }
      return false;
    } catch (error) {
      logger.error('UniClipboard failed to detect QR codes in the current image.');
      return false;
    } finally {
      if (targetFile !== null) {
        try {
          fileIo.closeSync(targetFile.fd);
        } catch (error) {
        }
      }
    }
  }

  public async recognizeCurrentImage(): Promise<void> {
    let pixelMap: image.PixelMap | null = this.desktopDisplayImage();
    let sourceKey: string = this.currentImageRecognitionKey();
    if (pixelMap === null || sourceKey.length === 0 || this.currentImageRecognitionState() === 1) {
      return;
    }
    this.imageRecognitionSourceKey = sourceKey;
    this.imageRecognitionState = 1;
    this.imageRecognizedText = '';
    this.imageSmartActions = [];

    let packedImage: ArrayBuffer;
    try {
      packedImage = await this.packImageForRecognition(pixelMap);
    } catch (error) {
      if (this.currentImageRecognitionKey() === sourceKey) {
        this.imageRecognitionState = 4;
      }
      return;
    }

    let recognizedText: string = '';
    let actions: ImageSmartAction[] = [];
    let ocrCompleted: boolean = false;
    let ocrInitialized: boolean = false;
    let ocrPixelMap: image.PixelMap | null = null;
    try {
      ocrInitialized = await textRecognition.init();
      if (ocrInitialized) {
        ocrPixelMap = await this.createOcrPixelMap(packedImage);
        let visionInfo: textRecognition.VisionInfo = {
          pixelMap: ocrPixelMap
        };
        let result: textRecognition.TextRecognitionResult = await textRecognition.recognizeText(visionInfo);
        recognizedText = result.value.trim();
        this.extractImageTextActions(recognizedText, actions);
        ocrCompleted = true;
      }
    } catch (error) {
      logger.error('UniClipboard failed to recognize text in the current image.');
    } finally {
      if (ocrPixelMap !== null) {
        try {
          await ocrPixelMap.release();
        } catch (error) {
        }
      }
      if (ocrInitialized) {
        try {
          await textRecognition.release();
        } catch (error) {
        }
      }
    }

    let qrCompleted: boolean = await this.detectImageQrCodes(packedImage, actions);
    if (this.currentImageRecognitionKey() !== sourceKey) {
      return;
    }
    this.imageRecognizedText = recognizedText;
    this.imageSmartActions = actions;
    if (recognizedText.length > 0 || actions.length > 0) {
      this.imageRecognitionState = 2;
    } else if (ocrCompleted || qrCompleted) {
      this.imageRecognitionState = 3;
    } else {
      this.imageRecognitionState = 4;
    }
  }

  public async copyImageRecognizedText(): Promise<void> {
    let text: string = this.currentImageRecognizedText();
    if (text.length === 0) {
      return;
    }
    try {
      await this.clipboardService.writeText(text);
      this.statusCode = 2;
    } catch (error) {
      this.statusCode = 3;
    }
  }

  public async copyImageSmartAction(action: ImageSmartAction): Promise<void> {
    try {
      await this.clipboardService.writeText(action.value);
      this.statusCode = 2;
    } catch (error) {
      this.statusCode = 3;
    }
  }

  public imageSmartActionCanOpen(action: ImageSmartAction): boolean {
    let lowerValue: string = action.value.toLowerCase();
    return action.kind === 'phone' || action.kind === 'link' ||
      (action.kind === 'qr' && (lowerValue.startsWith('http://') || lowerValue.startsWith('https://') ||
        lowerValue.startsWith('www.')));
  }

  public async openImageSmartAction(action: ImageSmartAction): Promise<void> {
    try {
      if (action.kind === 'phone') {
        let context: common.Context | undefined = this.getUIContext().getHostContext();
        if (context === undefined) {
          throw new Error('UIAbility context is unavailable.');
        }
        await call.makeCall(context, action.value);
        return;
      }
      let targetUrl: string = action.value;
      if (targetUrl.toLowerCase().startsWith('www.')) {
        targetUrl = 'https://' + targetUrl;
      }
      if (!targetUrl.toLowerCase().startsWith('http://') && !targetUrl.toLowerCase().startsWith('https://')) {
        return;
      }
      let context: common.Context | undefined = this.getUIContext().getHostContext();
      if (context === undefined) {
        throw new Error('UIAbility context is unavailable.');
      }
      let abilityContext: common.UIAbilityContext = context as common.UIAbilityContext;
      await abilityContext.startAbility({
        action: 'ohos.want.action.viewData',
        uri: targetUrl
      });
    } catch (error) {
      this.statusCode = 3;
    }
  }

  public desktopImageAspectRatio(): number {
    let pixelMap: image.PixelMap | null = this.desktopDisplayImage();
    if (pixelMap === null) {
      return 1;
    }
    try {
      let imageInfo: image.ImageInfo = pixelMap.getImageInfoSync();
      if (imageInfo.size.width > 0 && imageInfo.size.height > 0) {
        return imageInfo.size.width / imageInfo.size.height;
      }
    } catch (error) {
      logger.error('UniClipboard failed to read the image preview size.');
    }
    return 1;
  }

  public latestImageAspectRatio(): number {
    let pixelMap: image.PixelMap | null = this.latestImage;
    if (pixelMap === null) {
      return 1;
    }
    try {
      let imageInfo: image.ImageInfo = pixelMap.getImageInfoSync();
      if (imageInfo.size.width > 0 && imageInfo.size.height > 0) {
        return imageInfo.size.width / imageInfo.size.height;
      }
    } catch (error) {
      logger.error('UniClipboard failed to read the latest image preview size.');
    }
    return 1;
  }

  public resetDesktopVideoAspectRatio(): void {
    this.desktopVideoAspectRatio = 16 / 9;
    this.desktopVideoRatioKey = '';
  }

  public async loadDesktopVideoAspectRatio(): Promise<void> {
    let sourcePath: string = this.desktopFileSourcePath();
    let previewKey: string = this.desktopFilePreviewKey();
    if (!this.desktopFileIsVideo() || sourcePath.length === 0 || this.desktopVideoRatioKey === previewKey) {
      return;
    }
    this.desktopVideoRatioKey = previewKey;
    let extractor: media.AVMetadataExtractor | null = null;
    let sourceFile: fileIo.File | null = null;
    try {
      sourceFile = fileIo.openSync(sourcePath, fileIo.OpenMode.READ_ONLY);
      let sourceStat: fileIo.Stat = fileIo.statSync(sourceFile.fd);
      let sourceDescriptor: media.AVFileDescriptor = {
        fd: sourceFile.fd,
        offset: 0,
        length: sourceStat.size
      };
      if (canIUse('SystemCapability.Multimedia.Media.Core')) {
        if (canIUse('SystemCapability.Multimedia.Media.AVMetadataExtractor')) {
          extractor = await media.createAVMetadataExtractor();
        }
      }
      if (extractor === null) {
        return;
      }
      extractor.fdSrc = sourceDescriptor;
      let metadata: media.AVMetadata = await extractor.fetchMetadata();
      let widthText: string | undefined = metadata.videoWidth;
      let heightText: string | undefined = metadata.videoHeight;
      if (widthText === undefined || heightText === undefined) {
        return;
      }
      let width: number = Number.parseInt(widthText);
      let height: number = Number.parseInt(heightText);
      let orientation: number = 0;
      if (metadata.videoOrientation !== undefined) {
        orientation = Number.parseInt(metadata.videoOrientation);
      }
      if (orientation === 90 || orientation === 270) {
        let originalWidth: number = width;
        width = height;
        height = originalWidth;
      }
      if (width > 0 && height > 0 && this.desktopFilePreviewKey() === previewKey) {
        this.desktopVideoAspectRatio = width / height;
      }
    } catch (error) {
      logger.error('UniClipboard failed to read the video preview size.');
    } finally {
      if (extractor !== null) {
        try {
          await extractor.release();
        } catch (error) {
        }
      }
      if (sourceFile !== null) {
        try {
          fileIo.closeSync(sourceFile.fd);
        } catch (error) {
        }
      }
    }
  }

  public async openDesktopFilePreview(): Promise<void> {
    let uri: string = this.desktopFilePreviewUri();
    let fileName: string = this.desktopFileName();
    let context: common.Context | undefined = this.getUIContext().getHostContext();
    if (uri.length === 0 || fileName.length === 0 || context === undefined) {
      this.desktopFilePreviewState = 2;
      return;
    }
    this.desktopFilePreviewState = 1;
    let previewInfo: filePreview.PreviewInfo = {
      title: fileName,
      uri: uri,
      mimeType: this.desktopFileMimeType()
    };
    try {
      await filePreview.openPreview(context as common.UIAbilityContext, previewInfo);
      this.desktopFilePreviewState = 0;
    } catch (error) {
      logger.error('UniClipboard failed to open the file preview.');
      this.desktopFilePreviewState = 2;
    }
  }

  public async copyDesktopSelection(): Promise<void> {
    try {
      if (this.desktopShowsLatestImage()) {
        let pixelMap: image.PixelMap | null = this.desktopDisplayImage();
        if (pixelMap !== null) {
          await this.clipboardService.writeImage(pixelMap);
        }
      } else {
        let text: string = this.desktopDetailText();
        if (text.length === 0) {
          return;
        }
        await this.clipboardService.writeText(text);
      }
      this.statusCode = 2;
    } catch (error) {
      this.statusCode = 3;
    }
  }

  public async copyServerHistoryItem(item: ServerHistoryItem): Promise<void> {
    await this.selectDesktopServerItem(item);
    await this.copyDesktopSelection();
  }

  public async copyLocalHistoryItem(item: ClipboardHistoryItem): Promise<void> {
    try {
      if (item.kind === 'Image' && item.imagePreview !== null) {
        await this.clipboardService.writeImage(item.imagePreview);
      } else if (item.text.length > 0) {
        await this.clipboardService.writeText(item.text);
      }
      this.statusCode = 2;
    } catch (error) {
      this.statusCode = 3;
    }
  }

  public toggleLocalHistoryStarred(item: ClipboardHistoryItem): void {
    let items: ClipboardHistoryItem[] = [];
    for (let index: number = 0; index < this.history.length; index++) {
      let current: ClipboardHistoryItem = this.history[index];
      if (current.id === item.id) {
        current.starred = !current.starred;
      }
      items.push(current);
    }
    this.history = items;
    this.historyRevision += 1;
    this.animateHistoryUpdate();
    this.scheduleHistorySave();
  }

  public toggleHistorySnippet(item: ClipboardHistoryItem): void {
    let items: ClipboardHistoryItem[] = [];
    for (let index: number = 0; index < this.history.length; index++) {
      let current: ClipboardHistoryItem = this.history[index];
      if (current.id === item.id) {
        current.isSnippet = !current.isSnippet;
      }
      items.push(current);
    }
    this.history = items;
    this.animateHistoryUpdate();
    this.scheduleHistorySave();
  }

  public historyTagsText(item: ClipboardHistoryItem): string {
    return item.tags.join(', ');
  }

  public setHistoryTags(itemId: string, tagText: string): void {
    let normalizedText: string = tagText.replace(/，/g, ',');
    let parts: string[] = normalizedText.split(',');
    let tags: string[] = [];
    for (let index: number = 0; index < parts.length && tags.length < 8; index++) {
      let tag: string = parts[index].trim();
      if (tag.length > 20) {
        tag = tag.substring(0, 20);
      }
      if (tag.length > 0 && tags.indexOf(tag) < 0) {
        tags.push(tag);
      }
    }
    let items: ClipboardHistoryItem[] = [];
    for (let index: number = 0; index < this.history.length; index++) {
      let item: ClipboardHistoryItem = this.history[index];
      if (item.id === itemId) {
        item.tags = tags;
      }
      items.push(item);
    }
    this.history = items;
    this.animateHistoryUpdate();
    this.scheduleHistorySave();
  }

  public historyItemSelected(itemId: string): boolean {
    return this.historySelectedIds.indexOf(itemId) >= 0;
  }

  public toggleHistorySelectionMode(): void {
    this.historySelectionMode = !this.historySelectionMode;
    if (!this.historySelectionMode) {
      this.historySelectedIds = [];
    }
  }

  public toggleHistorySelection(itemId: string): void {
    let selectedIds: string[] = [];
    let alreadySelected: boolean = false;
    for (let index: number = 0; index < this.historySelectedIds.length; index++) {
      let selectedId: string = this.historySelectedIds[index];
      if (selectedId === itemId) {
        alreadySelected = true;
      } else {
        selectedIds.push(selectedId);
      }
    }
    if (!alreadySelected) {
      selectedIds.push(itemId);
    }
    this.historySelectedIds = selectedIds;
  }

  public selectAllFilteredHistory(): void {
    let selectedIds: string[] = [];
    let items: ClipboardHistoryItem[] = this.compactFilteredHistory();
    for (let index: number = 0; index < items.length; index++) {
      selectedIds.push(items[index].id);
    }
    this.historySelectedIds = selectedIds;
  }

  public batchToggleSelectedStarred(): void {
    if (this.historySelectedIds.length === 0) {
      return;
    }
    let allStarred: boolean = true;
    for (let index: number = 0; index < this.history.length; index++) {
      let item: ClipboardHistoryItem = this.history[index];
      if (this.historyItemSelected(item.id) && !item.starred) {
        allStarred = false;
      }
    }
    let items: ClipboardHistoryItem[] = [];
    for (let index: number = 0; index < this.history.length; index++) {
      let item: ClipboardHistoryItem = this.history[index];
      if (this.historyItemSelected(item.id)) {
        item.starred = !allStarred;
      }
      items.push(item);
    }
    this.history = items;
    this.animateHistoryUpdate();
    this.scheduleHistorySave();
  }

  public async batchDeleteSelectedHistory(): Promise<void> {
    if (this.historySelectedIds.length === 0 || this.historyMutationBusy) {
      return;
    }
    try {
      let result = await this.getUIContext().getPromptAction().showDialog({
        title: $r('app.string.history_batch_delete_title'),
        message: $r('app.string.history_batch_delete_message'),
        buttons: [
          { text: $r('app.string.cancel_action'), color: $r('app.color.text_secondary') },
          { text: $r('app.string.history_delete_action'), color: $r('app.color.danger') }
        ]
      });
      if (result.index !== 1) {
        return;
      }
    } catch (error) {
      return;
    }
    this.historyMutationBusy = true;
    try {
      let retainedItems: ClipboardHistoryItem[] = [];
      let context: common.Context | undefined = this.getUIContext().getHostContext();
      for (let index: number = 0; index < this.history.length; index++) {
        let item: ClipboardHistoryItem = this.history[index];
        if (this.historyItemSelected(item.id)) {
          if (context !== undefined) {
            this.historyStorageService.removePayload(context, item);
          }
        } else {
          retainedItems.push(item);
        }
      }
      this.history = retainedItems;
      this.historySelectedIds = [];
      this.historySelectionMode = false;
      this.scheduleHistorySave();
    } finally {
      this.historyMutationBusy = false;
    }
  }

  public setHistoryRetentionDays(retentionDays: number): void {
    if (retentionDays < 0) {
      return;
    }
    this.historyRetentionDays = retentionDays;
    this.saveHistoryLibrarySettings();
    this.pruneHistoryByRetention();
    this.scheduleHistorySave();
  }

  public setHistoryMergeDuplicates(enabled: boolean): void {
    this.historyMergeDuplicates = enabled;
    if (enabled) {
      this.history = this.mergeHistoryDuplicates(this.history);
    }
    this.saveHistoryLibrarySettings();
    this.scheduleHistorySave();
  }

  public saveHistoryLibrarySettings(): void {
    let context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    this.historyStorageService.saveSettings(context,
      new HistoryLibrarySettings(this.historyRetentionDays, this.historyMergeDuplicates));
  }

  public pruneHistoryByRetention(): void {
    if (this.historyRetentionDays === 0) {
      return;
    }
    let cutoffMs: number = Date.now() - this.historyRetentionDays * 24 * 60 * 60 * 1000;
    let retainedItems: ClipboardHistoryItem[] = [];
    let context: common.Context | undefined = this.getUIContext().getHostContext();
    for (let index: number = 0; index < this.history.length; index++) {
      let item: ClipboardHistoryItem = this.history[index];
      if (item.timestampMs >= cutoffMs || item.starred || item.isSnippet) {
        retainedItems.push(item);
      } else if (context !== undefined) {
        this.historyStorageService.removePayload(context, item);
      }
    }
    this.history = retainedItems;
  }

  public mergeHistoryDuplicates(items: ClipboardHistoryItem[]): ClipboardHistoryItem[] {
    let mergedItems: ClipboardHistoryItem[] = [];
    for (let sourceIndex: number = 0; sourceIndex < items.length; sourceIndex++) {
      let source: ClipboardHistoryItem = items[sourceIndex];
      let duplicateIndex: number = -1;
      for (let targetIndex: number = 0; targetIndex < mergedItems.length; targetIndex++) {
        let target: ClipboardHistoryItem = mergedItems[targetIndex];
        let sameTextContent: boolean = source.kind === 'Text' && target.kind === 'Text' &&
          source.text.trim() === target.text.trim();
        let sameContentId: boolean = source.id.length > 0 && source.id === target.id;
        if (sameTextContent || sameContentId) {
          duplicateIndex = targetIndex;
          break;
        }
      }
      if (duplicateIndex < 0) {
        mergedItems.push(source);
        continue;
      }
      let duplicate: ClipboardHistoryItem = mergedItems[duplicateIndex];
      duplicate.starred = duplicate.starred || source.starred;
      duplicate.isSnippet = duplicate.isSnippet || source.isSnippet;
      duplicate.occurrenceCount += Math.max(1, source.occurrenceCount);
      if (duplicate.sourceDevice.length === 0) {
        duplicate.sourceDevice = source.sourceDevice;
      }
      for (let tagIndex: number = 0; tagIndex < source.tags.length; tagIndex++) {
        let tag: string = source.tags[tagIndex];
        if (duplicate.tags.indexOf(tag) < 0) {
          duplicate.tags.push(tag);
        }
      }
    }
    return mergedItems;
  }

  public async sendLocalHistoryItem(item: ClipboardHistoryItem): Promise<void> {
    if (item.kind === 'Image' && item.imagePreview !== null) {
      this.composerImage = item.imagePreview;
      await this.sendImage();
      return;
    }
    if (item.kind === 'File' && item.filePath.length > 0) {
      try {
        let sourceFile: fileIo.File = fileIo.openSync(item.filePath, fileIo.OpenMode.READ_ONLY);
        let sourceStat: fileIo.Stat = fileIo.statSync(sourceFile.fd);
        fileIo.closeSync(sourceFile.fd);
        this.composerFileUri = item.filePath;
        this.composerFileSize = sourceStat.size;
        this.composerFileName = item.text;
        await this.sendFile();
      } catch (error) {
        this.statusCode = 3;
      }
      return;
    }
    this.composerText = item.text;
    await this.sendText();
  }

  public async sendServerHistoryItem(item: ServerHistoryItem): Promise<void> {
    await this.selectDesktopServerItem(item);
    if (item.kind === 'Image' && this.desktopSelectedImage !== null) {
      this.composerImage = this.desktopSelectedImage;
      await this.sendImage();
      return;
    }
    if (item.kind === 'File' && this.desktopSelectedFilePath.length > 0) {
      try {
        let sourceFile: fileIo.File = fileIo.openSync(this.desktopSelectedFilePath, fileIo.OpenMode.READ_ONLY);
        let sourceStat: fileIo.Stat = fileIo.statSync(sourceFile.fd);
        fileIo.closeSync(sourceFile.fd);
        this.composerFileUri = this.desktopSelectedFilePath;
        this.composerFileSize = sourceStat.size;
        this.composerFileName = item.text;
        await this.sendFile();
      } catch (error) {
        this.statusCode = 3;
      }
      return;
    }
    this.composerText = item.text;
    await this.sendText();
  }

  public async sendServerHistoryItemToTarget(item: ServerHistoryItem, target: string): Promise<void> {
    logger.info('UniClipboard history send target: ' + target);
    await this.sendServerHistoryItem(item);
  }

  public async sendLocalHistoryItemToTarget(item: ClipboardHistoryItem, target: string): Promise<void> {
    logger.info('UniClipboard history send target: ' + target);
    await this.sendLocalHistoryItem(item);
  }

  public toggleDesktopSelectedStar(): void {
    for (let index: number = 0; index < this.serverHistory.length; index++) {
      let item: ServerHistoryItem = this.serverHistory[index];
      if (item.id === this.desktopSelectedId) {
        this.toggleHistoryStarred(item);
        return;
      }
    }
    let items: ClipboardHistoryItem[] = [];
    for (let index: number = 0; index < this.history.length; index++) {
      let item: ClipboardHistoryItem = this.history[index];
      if (item.id === this.desktopSelectedId) {
        item.starred = !item.starred;
      }
      items.push(item);
    }
    this.history = items;
    this.animateHistoryUpdate();
    this.scheduleHistorySave();
  }

  public desktopSelectionStarred(): boolean {
    for (let index: number = 0; index < this.serverHistory.length; index++) {
      let item: ServerHistoryItem = this.serverHistory[index];
      if (item.id === this.desktopSelectedId) {
        return item.starred;
      }
    }
    for (let index: number = 0; index < this.history.length; index++) {
      let item: ClipboardHistoryItem = this.history[index];
      if (item.id === this.desktopSelectedId) {
        return item.starred;
      }
    }
    return false;
  }

  public deleteDesktopSelection(): void {
    for (let index: number = 0; index < this.serverHistory.length; index++) {
      let item: ServerHistoryItem = this.serverHistory[index];
      if (item.id === this.desktopSelectedId) {
        this.confirmDeleteHistory(item);
        return;
      }
    }
    for (let index: number = 0; index < this.history.length; index++) {
      let item: ClipboardHistoryItem = this.history[index];
      if (item.id === this.desktopSelectedId) {
        this.confirmDeleteLocalHistory(item);
        return;
      }
    }
  }

  public async confirmDeleteLocalHistory(item: ClipboardHistoryItem): Promise<void> {
    let confirmed: boolean = false;
    try {
      let result = await this.getUIContext().getPromptAction().showDialog({
        title: $r('app.string.history_delete_title'),
        message: $r('app.string.history_delete_message'),
        buttons: [
          { text: $r('app.string.cancel_action'), color: $r('app.color.text_secondary') },
          { text: $r('app.string.history_delete_action'), color: $r('app.color.danger') }
        ]
      });
      confirmed = result.index === 1;
    } catch (error) {
      return;
    }
    if (!confirmed || this.historyMutationBusy) {
      return;
    }
    this.historyMutationBusy = true;
    try {
      let items: ClipboardHistoryItem[] = [];
      for (let index: number = 0; index < this.history.length; index++) {
        let current: ClipboardHistoryItem = this.history[index];
        if (current.id !== item.id) {
          items.push(current);
        }
      }
      this.history = items;
      this.desktopSelectedId = '';
      this.desktopSelectedText = '';
      this.desktopSelectedMeta = '';
      this.desktopSelectedDirection = '';
      this.desktopSelectedImage = null;
      this.desktopSelectedFileData = null;
      this.desktopSelectedFilePath = '';
      this.releaseDesktopAudio();
      this.refreshCurrentLinkPreview();
      let context: common.Context | undefined = this.getUIContext().getHostContext();
      if (context !== undefined) {
        this.historyStorageService.removePayload(context, item);
      }
      this.scheduleHistorySave();
    } finally {
      this.historyMutationBusy = false;
    }
  }

  public hasConfig(): boolean {
    return this.serverUrl.trim().length > 0 &&
      this.username.trim().length > 0 &&
      this.password.length > 0;
  }

  public currentTime(): string {
    let now: Date = new Date();
    let hours: string = now.getHours().toString().padStart(2, '0');
    let minutes: string = now.getMinutes().toString().padStart(2, '0');
    return hours + ':' + minutes;
  }

  public addHistory(text: string, direction: string, kind: string = 'Text',
    imagePreview: image.PixelMap | null = null, fileData: Uint8Array | null = null,
    filePath: string = '', historyId: string = '', sourceDevice: string = ''): void {
    let timestampMs: number = Date.now();
    let itemId: string = historyId.length > 0 ? historyId : timestampMs.toString();
    let resolvedSource: string = sourceDevice;
    if (resolvedSource.length === 0 && direction === 'sent') {
      resolvedSource = this.spaceDeviceName.length > 0 ? this.spaceDeviceName : deviceInfo.marketName;
      if (resolvedSource.length === 0) {
        resolvedSource = deviceInfo.deviceType;
      }
    }
    let item: ClipboardHistoryItem = new ClipboardHistoryItem(
      itemId, text, direction, this.currentTime(), kind, imagePreview, fileData, filePath, timestampMs,
      false, [], false, resolvedSource, 1);
    let items: ClipboardHistoryItem[] = [item];
    let merged: boolean = false;
    for (let index: number = 0; index < this.history.length; index++) {
      let current: ClipboardHistoryItem = this.history[index];
      let sameTextContent: boolean = kind === 'Text' && current.kind === 'Text' &&
        current.text.trim() === text.trim();
      let sameContentId: boolean = historyId.length > 0 && current.id === historyId;
      if (this.historyMergeDuplicates && !merged && (sameTextContent || sameContentId)) {
        current.direction = direction;
        current.time = item.time;
        current.timestampMs = timestampMs;
        current.sourceDevice = resolvedSource;
        current.occurrenceCount += 1;
        if (imagePreview !== null) {
          current.imagePreview = imagePreview;
        }
        if (fileData !== null) {
          current.fileData = fileData;
        }
        if (filePath.length > 0) {
          current.filePath = filePath;
        }
        items[0] = current;
        merged = true;
      } else {
        items.push(current);
      }
    }
    this.history = items;
    this.historyRevision += 1;
    AppStorage.setOrCreate('historyRevision', this.historyRevision);
    this.pruneHistoryByRetention();
    // LazyForEach must be notified from the data mutation, not during build().
    this.sessionHistoryDataSourceInstance.reload(this.desktopFilteredSessionHistory());
    this.animateHistoryUpdate();
    this.scheduleHistorySave();
  }

  public connectionChanged(): void {
    this.realtimeAutoConnect = false;
    if (this.realtimeActive) {
      this.stopRealtime();
    }
    this.statusCode = 0;
  }

  public isConnectionAvailable(): boolean {
    if (this.spaceJoined && !this.hasConfig()) {
      return this.spacePeerConnected;
    }
    return this.spacePeerConnected || this.statusCode === 2 || this.realtimeActive;
  }

  public async testConnection(): Promise<void> {
    if (!this.hasConfig()) {
      this.statusCode = 3;
      this.recordConnectionDiagnosticFailure('not_configured');
      return;
    }
    this.busy = true;
    this.statusCode = 1;
    try {
      let client: MobileSyncClient = new MobileSyncClient(this.getConfig());
      await client.probe();
      this.saveConfig();
      this.startRealtime();
      this.statusCode = 2;
    } catch (error) {
      this.statusCode = 3;
      this.recordConnectionDiagnosticFailure('relay_probe_failed');
    } finally {
      this.busy = false;
    }
  }

  public importConnectUri(): void {
    if (this.connectUri.trim().length === 0) {
      this.connectUriState = 2;
      return;
    }
    try {
      let config: ServerConfig = this.nativeProtocolService.parseServerConfig(this.connectUri);
      this.connectionChanged();
      this.serverUrl = config.baseUrl;
      this.username = config.username;
      this.password = config.password;
      this.connectUri = '';
      this.connectUriState = 1;
      this.statusCode = 0;
      this.saveConfig();
      this.startRealtime();
      this.pullLatest();
    } catch (error) {
      this.connectUriState = 2;
    }
  }

  public scanConnectUri(): void {
    let options: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.QR_CODE],
      enableMultiMode: false,
      enableAlbum: true
    };
    this.connectUriState = 0;
    if (canIUse('SystemCapability.Multimedia.Scan.ScanBarcode')) {
      try {
        scanBarcode.startScanForResult(this.getUIContext().getHostContext(), options,
          (error: BusinessError, result: scanBarcode.ScanResult): void => {
            if (error) {
              this.connectUriState = 3;
              return;
            }
            this.connectUri = result.originalValue;
            this.importConnectUri();
          });
      } catch (error) {
        this.connectUriState = 3;
      }
    } else {
      this.connectUriState = 3;
    }
  }

  public async pullLatest(): Promise<void> {
    if (!this.hasConfig()) {
      if (this.spaceJoined) {
        await this.connectAllSpaceDevices();
        return;
      }
      this.statusCode = 3;
      this.openConnectionSettings();
      return;
    }
    this.busy = true;
    this.statusCode = 1;
    try {
      let client: MobileSyncClient = new MobileSyncClient(this.getConfig());
      let result: SyncContent = await client.getLatestContent();
      await this.applyLatestContent(result, true);
      this.desktopSelectedId = '';
      this.desktopSelectedText = '';
      this.desktopSelectedMeta = '';
      this.desktopSelectedDirection = '';
      this.desktopSelectedImage = null;
      this.desktopSelectedFileData = null;
      this.desktopSelectedFilePath = '';
      this.desktopFilePreviewState = 0;
      this.resetDesktopVideoAspectRatio();
      this.releaseDesktopAudio();
      this.refreshCurrentLinkPreview();
      this.statusCode = 2;
    } catch (error) {
      this.statusCode = 3;
    } finally {
      this.busy = false;
    }
  }

  public async applyLatestContent(result: SyncContent, recordHistory: boolean): Promise<void> {
    if (this.latestContentId !== result.contentId) {
      this.desktopGestureShareHintDismissed = false;
    }
    let pixelMap: image.PixelMap | null = null;
    let displayText: string = this.contentDisplayText(result);
    if (this.desktopSelectedId.length === 0) {
      await this.releaseDesktopAudio();
      this.resetDesktopVideoAspectRatio();
    }
    if (result.kind === 'Image') {
      if (result.data.length === 0) {
        throw new Error('image payload is empty');
      }
      pixelMap = await this.clipboardService.decodeImage(result.data);
    }
    let fileData: Uint8Array | null = null;
    let filePath: string = '';
    let fileName: string = '';
    if (result.kind === 'File') {
      fileName = result.dataName.length > 0 ? result.dataName : displayText;
      if (result.data.length > 0) {
        fileData = result.data;
        filePath = this.cacheLatestFile(result.data);
      }
    } else {
      this.removeLatestCachedFile();
    }
    this.latestKind = result.kind;
    this.latestText = displayText;
    if (this.desktopSelectedId.length === 0) {
      this.refreshCurrentLinkPreview();
    }
    this.latestImage = pixelMap;
    if (pixelMap !== null) {
      this.latestImageRevision += 1;
    }
    this.latestFileName = fileName;
    this.latestFileData = fileData;
    this.latestFilePath = filePath;
    if (result.kind === 'File') {
      this.latestFileRevision += 1;
      this.desktopFilePreviewState = 0;
    }
    this.latestContentId = result.contentId;
    this.animateLatestContent();
    if (recordHistory) {
      this.addHistory(displayText, 'received', result.kind, pixelMap, fileData, filePath, result.contentId);
    }
  }

  public cacheLatestFile(data: Uint8Array): string {
    this.removeLatestCachedFile();
    let context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined || data.length === 0) {
      return '';
    }
    let targetPath: string = context.cacheDir + '/uniclipboard_latest_file_' + Date.now().toString();
    try {
      let targetFile: fileIo.File = fileIo.openSync(targetPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(targetFile.fd, data.buffer);
      } finally {
        fileIo.closeSync(targetFile.fd);
      }
      this.latestCachedFilePath = targetPath;
      return targetPath;
    } catch (error) {
      try {
        fileIo.unlinkSync(targetPath);
      } catch (unlinkError) {
      }
      return '';
    }
  }

  public removeLatestCachedFile(): void {
    let cachedPath: string = this.latestCachedFilePath;
    this.latestCachedFilePath = '';
    if (cachedPath.length === 0) {
      return;
    }
    try {
      fileIo.unlinkSync(cachedPath);
    } catch (error) {
    }
  }

  public contentDisplayText(result: SyncContent): string {
    if (result.dataName.length > 0 && (result.kind === 'Image' || result.text.length === 0)) {
      return result.dataName;
    }
    if (result.kind === 'Image' && result.text.length === 0) {
      return 'image.png';
    }
    return result.text;
  }

  public latestCopyable(): boolean {
    return (this.latestKind === 'Text' && this.latestText.length > 0) ||
      (this.latestKind === 'Image' && this.latestImage !== null) ||
      (this.latestKind === 'File' &&
        (this.latestFileData !== null || this.latestFilePath.length > 0));
  }

  public async copyLatest(): Promise<void> {
    try {
      if (this.latestKind === 'Image' && this.latestImage !== null) {
        await this.clipboardService.writeImage(this.latestImage);
      } else if (this.latestKind === 'File' &&
        (this.latestFileData !== null || this.latestFilePath.length > 0)) {
        await this.saveSelectedFile();
      } else if (this.latestKind === 'Text' && this.latestText.length > 0) {
        await this.clipboardService.writeText(this.latestText);
      }
    } catch (error) {
      this.statusCode = 3;
    }
  }

  public async readLocalClipboard(): Promise<void> {
    try {
      if (!this.clipboardService.hasText()) {
        this.composerText = '';
        return;
      }
      this.composerText = await this.clipboardService.readText();
    } catch (error) {
      this.statusCode = 3;
    }
  }

  public async readLocalImage(): Promise<void> {
    if (this.imageReadState === 1) {
      return;
    }
    this.imageReadState = 1;
    this.imageSendState = 0;
    try {
      let pixelMap: image.PixelMap | null = await this.clipboardService.readImage();
      this.composerImage = pixelMap;
      if (pixelMap !== null) {
        this.composerImageRevision += 1;
        this.imageReadState = 2;
      } else {
        this.imageReadState = 3;
      }
      this.statusCode = this.composerImage === null ? 3 : 2;
    } catch (error) {
      this.composerImage = null;
      this.imageReadState = 5;
      this.statusCode = 3;
    }
  }

  public async readLocalImageFromPasteData(data: pasteboard.PasteData): Promise<void> {
    if (this.imageReadState === 1) {
      return;
    }
    this.imageReadState = 1;
    this.imageSendState = 0;
    try {
      let pixelMap: image.PixelMap | null = await this.clipboardService.readImageFromPasteData(data);
      this.composerImage = pixelMap;
      if (pixelMap !== null) {
        this.composerImageRevision += 1;
        this.imageReadState = 2;
      } else {
        this.imageReadState = 3;
      }
      this.statusCode = this.composerImage === null ? 3 : 2;
    } catch (error) {
      this.composerImage = null;
      this.imageReadState = 5;
      this.statusCode = 3;
    }
  }

  public async sendText(): Promise<void> {
    let text: string = this.composerText.trim();
    if (text.length === 0) {
      return;
    }
    if (!this.spaceJoined && !this.hasConfig() && !this.mobileSyncRunning) {
      this.statusCode = 3;
      this.openConnectionSettings();
      return;
    }
    this.busy = true;
    this.statusCode = 1;
    try {
      let delivered: boolean = false;
      let mobilePublished: boolean = false;
      if (this.mobileSyncRunning) {
        try {
          this.latestContentId = this.mobileSyncServerService.publishText(text);
          mobilePublished = true;
        } catch (error) {
          mobilePublished = false;
        }
      }
      if (this.spaceJoined) {
        let report: EngineSendReport = await engineRuntimeService.sendText(text, []);
        logger.info('UniClipboard official Engine accepted peer count: ' + report.totalAccepted.toString());
        this.latestContentId = report.entryId;
        if (report.totalAccepted > 0 || report.totalPending > 0) {
          this.spacePeerConnected = true;
          delivered = true;
        } else if (!mobilePublished) {
          throw new Error('no official Engine peer accepted the clipboard');
        }
      }
      if (!delivered && !this.spaceJoined && this.hasConfig()) {
        try {
          let client: MobileSyncClient = new MobileSyncClient(this.getConfig());
          this.latestContentId = await client.putText(text);
          delivered = true;
          logger.info('UniClipboard text sent through desktop relay');
        } catch (error) {
          logger.warn('UniClipboard desktop relay unavailable, trying P2P');
        }
      }
      if (!delivered && mobilePublished) {
        delivered = true;
      }
      if (!delivered) {
        throw new Error('no desktop or space peer accepted the clipboard');
      }
      this.latestText = text;
      this.latestKind = 'Text';
      this.latestImage = null;
      if (this.desktopSelectedId.length === 0) {
        this.releaseDesktopAudio();
        this.refreshCurrentLinkPreview();
      }
      this.addHistory(text, 'sent');
      this.composerText = '';
      this.statusCode = 2;
    } catch (error) {
      if (this.spaceJoined) {
        this.spacePeerConnected = false;
      }
      this.statusCode = 3;
    } finally {
      this.busy = false;
    }
  }

  public async sendImage(): Promise<void> {
    if (!this.spaceJoined && !this.hasConfig() && !this.mobileSyncRunning) {
      this.statusCode = 3;
      this.openConnectionSettings();
      return;
    }
    let pixelMap: image.PixelMap | null = this.composerImage;
    if (pixelMap === null) {
      return;
    }
    this.busy = true;
    this.statusCode = 1;
    this.imageSendState = 1;
    try {
      let delivered: boolean = false;
      let mobilePublished: boolean = false;
      if (this.mobileSyncRunning) {
        try {
          let mobileData: Uint8Array = await this.clipboardService.encodePng(pixelMap);
          this.latestContentId = this.mobileSyncServerService.publishImage(mobileData);
          mobilePublished = true;
        } catch (error) {
          mobilePublished = false;
        }
      }
      if (this.hasConfig()) {
        try {
          let data: Uint8Array = await this.clipboardService.encodePng(pixelMap);
          let client: MobileSyncClient = new MobileSyncClient(this.getConfig());
          this.latestContentId = await client.putImage(data);
          this.latestText = 'image.png';
          delivered = true;
          logger.info('UniClipboard image sent through desktop relay');
        } catch (error) {
          logger.warn('UniClipboard desktop image relay unavailable, trying P2P');
        }
      }
      if (!delivered && this.spaceJoined) {
        try {
          let data: Uint8Array = await this.clipboardService.encodeSpaceImage(pixelMap);
          let report: EngineSendReport = await engineRuntimeService.sendImage(data, 'image/jpeg', []);
          logger.info('UniClipboard official Engine image accepted peer count: ' +
            report.totalAccepted.toString());
          if (report.totalAccepted > 0 || report.totalPending > 0) {
            this.spacePeerConnected = true;
            this.latestContentId = report.entryId;
            this.latestText = 'image.jpg';
            delivered = true;
          } else if (!mobilePublished) {
            throw new Error('no online space peer accepted the clipboard image');
          }
        } catch (error) {
          logger.error('UniClipboard official Engine image send failed: ' + this.errorDetail(error));
          if (!mobilePublished) {
            throw new Error('space image delivery failed: ' + this.errorDetail(error));
          }
        }
      }
      if (!delivered && mobilePublished) {
        delivered = true;
      }
      if (!delivered) {
        throw new Error('no desktop or space peer accepted the clipboard image');
      }
      this.latestKind = 'Image';
      this.latestImage = pixelMap;
      if (this.desktopSelectedId.length === 0) {
        this.releaseDesktopAudio();
        this.clearLinkPreview();
      }
      this.latestImageRevision += 1;
      this.composerImage = null;
      this.addHistory(this.latestText, 'sent', 'Image', pixelMap);
      this.statusCode = 2;
      this.imageSendState = 2;
    } catch (error) {
      if (this.spaceJoined) {
        this.spacePeerConnected = false;
      }
      this.statusCode = 3;
      this.imageSendState = 3;
      this.reportError('image', 'image send failed: ' + this.errorDetail(error));
    } finally {
      this.busy = false;
    }
  }

  public resetComposerFile(removeStagedFile: boolean): void {
    if (removeStagedFile && this.composerFileHistoryId.length > 0 && this.composerFileUri.length > 0) {
      let context: common.Context | undefined = this.getUIContext().getHostContext();
      if (context !== undefined) {
        this.historyStorageService.discardManagedFile(context, this.composerFileUri);
      }
    }
    this.composerFileData = null;
    this.composerFileUri = '';
    this.composerFileSize = 0;
    this.composerFileName = '';
    this.composerFileHistoryId = '';
  }

  public async selectFile(): Promise<void> {
    let context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      this.fileTransferState = 4;
      return;
    }
    this.fileTransferState = 1;
    try {
      let documentPicker: picker.DocumentViewPicker =
        new picker.DocumentViewPicker(context as common.UIAbilityContext);
      let options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      let uris: string[] = await documentPicker.select(options);
      if (uris.length === 0) {
        this.fileTransferState = 0;
        return;
      }
      let selection: ClipboardFileSelection = this.clipboardService.inspectFile(uris[0]);
      if (selection.size <= 0) {
        this.resetComposerFile(true);
        this.fileTransferState = 5;
        return;
      }
      let historyId: string = Date.now().toString();
      let stagedPath: string = this.historyStorageService.stageFile(
        context, selection.uri, historyId, selection.fileName);
      if (stagedPath.length === 0) {
        throw new Error('failed to persist selected file');
      }
      let previousPath: string = this.composerFileUri;
      let previousHistoryId: string = this.composerFileHistoryId;
      this.composerFileData = null;
      this.composerFileUri = stagedPath;
      this.composerFileSize = selection.size;
      this.composerFileName = selection.fileName;
      this.composerFileHistoryId = historyId;
      if (previousHistoryId.length > 0 && previousPath.length > 0 && previousPath !== stagedPath) {
        this.historyStorageService.discardManagedFile(context, previousPath);
      }
      this.fileTransferState = 2;
    } catch (error) {
      this.resetComposerFile(true);
      this.fileTransferState = 4;
    }
  }

  public async sendFile(): Promise<void> {
    let sourceUri: string = this.composerFileUri;
    let sourceSize: number = this.composerFileSize;
    if ((!this.spaceJoined && !this.hasConfig() && !this.mobileSyncRunning) || sourceUri.length === 0 ||
      sourceSize <= 0 || this.composerFileName.length === 0) {
      this.fileTransferState = 4;
      return;
    }
    this.busy = true;
    this.statusCode = 1;
    this.fileTransferState = 3;
    try {
      let delivered: boolean = false;
      let mobilePublished: boolean = false;
      if (this.mobileSyncRunning) {
        try {
          this.latestContentId = this.mobileSyncServerService.publishFile(
            sourceUri, sourceSize, this.composerFileName);
          mobilePublished = true;
        } catch (error) {
          mobilePublished = false;
        }
      }
      if (this.hasConfig() && !this.spaceJoined) {
        try {
          let client: MobileSyncClient = new MobileSyncClient(this.getConfig());
          this.latestContentId = await client.putFileFromUri(
            sourceUri, sourceSize, this.composerFileName);
          this.pendingFileTransferId = '';
          delivered = true;
          logger.info('UniClipboard file sent through desktop relay');
        } catch (error) {
          logger.warn('UniClipboard desktop file relay unavailable, trying P2P');
        }
      }
      if (!delivered && this.spaceJoined) {
        try {
          let report: EngineSendReport = await engineRuntimeService.sendFileFromUri(sourceUri, '', []);
          if (report.totalAccepted > 0 || report.totalPending > 0) {
            this.pendingFileTransferId = report.entryId;
            this.latestContentId = report.entryId;
            this.spacePeerConnected = true;
            delivered = true;
          } else if (!mobilePublished) {
            throw new Error('no online space peer accepted the file');
          }
        } catch (error) {
          if (!mobilePublished) {
            throw new Error('space file delivery failed');
          }
        }
      }
      if (!delivered && mobilePublished) {
        delivered = true;
      }
      if (!delivered) {
        throw new Error('no desktop or space peer accepted the file');
      }
      this.latestKind = 'File';
      this.latestText = this.composerFileName;
      this.latestFileName = this.composerFileName;
      this.latestFileData = null;
      this.latestFilePath = sourceUri;
      this.latestFileRevision += 1;
      this.desktopFilePreviewState = 0;
      this.resetDesktopVideoAspectRatio();
      if (this.desktopSelectedId.length === 0) {
        this.releaseDesktopAudio();
        this.clearLinkPreview();
      }
      this.addHistory(this.composerFileName, 'sent', 'File', null, null, sourceUri,
        this.composerFileHistoryId);
      this.resetComposerFile(false);
      this.fileTransferState = 7;
      this.statusCode = 2;
    } catch (error) {
      this.spacePeerConnected = false;
      this.fileTransferState = 4;
      this.statusCode = 3;
    } finally {
      this.busy = false;
    }
  }

  public async saveSelectedFile(): Promise<void> {
    let data: Uint8Array | null = this.desktopSelectedId.length > 0 ?
      this.desktopSelectedFileData : this.latestFileData;
    let sourcePath: string = this.desktopSelectedId.length > 0 ?
      this.desktopSelectedFilePath : this.latestFilePath;
    let fileName: string = this.desktopSelectedId.length > 0 ? this.desktopSelectedText : this.latestFileName;
    if ((data === null && sourcePath.length === 0) || fileName.length === 0) {
      return;
    }
    let context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    try {
      let documentPicker: picker.DocumentViewPicker =
        new picker.DocumentViewPicker(context as common.UIAbilityContext);
      let options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      options.newFileNames = [fileName];
      let uris: string[] = await documentPicker.save(options);
      if (uris.length > 0) {
        if (sourcePath.length > 0) {
          this.copyLocalFileToUri(sourcePath, uris[0]);
        } else if (data !== null) {
          this.clipboardService.writeFile(uris[0], data);
        }
        this.statusCode = 2;
      }
    } catch (error) {
      this.statusCode = 3;
    }
  }

  public startRealtime(): void {
    if (!this.hasConfig()) {
      this.statusCode = 3;
      this.openConnectionSettings();
      return;
    }
    try {
      this.saveConfig();
      let client: MobileSyncClient = new MobileSyncClient(this.getConfig());
      client.startRealtime();
      this.realtimeAutoConnect = true;
      this.realtimeActive = true;
      this.statusCode = 1;
    } catch (error) {
      this.realtimeActive = false;
      this.statusCode = 3;
      this.reportError('sync', 'failed to start the realtime connection: ' + this.errorDetail(error),
        $r('app.string.error_toast_sync'));
    }
  }

  public stopRealtime(): void {
    let client: MobileSyncClient = new MobileSyncClient(this.getConfig());
    client.stopRealtime();
    this.realtimeAutoConnect = false;
    this.realtimeActive = false;
    this.statusCode = 0;
  }

  public toggleRealtime(): void {
    if (this.realtimeActive) {
      this.stopRealtime();
    } else {
      this.startRealtime();
    }
  }

  public async consumeRealtimeEvents(): Promise<number> {
    let activityCount: number = 0;
    activityCount += await this.consumeMobileSyncEvents();
    this.realtimeTick += 1;
    if (this.spaceJoined) {
      activityCount += await this.pollOfficialEngineInbound();
    }
    if (this.spaceInvitationExpiresAtMs > 0 && Date.now() >= this.spaceInvitationExpiresAtMs) {
      this.spaceIssuedInvitationCode = '';
      this.spaceInvitationExpiresAtMs = 0;
    }
    if (this.spaceJoined && this.realtimeTick % 4 === 0) {
      this.refreshSpaceDevices();
    }
    if (this.mobileSyncEnabled && this.realtimeTick % 4 === 0) {
      await this.refreshMobileSyncDevices();
    }
    if (this.realtimeAutoConnect && this.hasConfig() && !this.realtimeActive &&
      this.realtimeTick % 5 === 0) {
      this.startRealtime();
    }
    if (!this.realtimeActive || this.sseEventBusy) {
      return activityCount;
    }
    this.sseEventBusy = true;
    try {
      let client: MobileSyncClient = new MobileSyncClient(this.getConfig());
      let events: SyncEvent[] = client.drainRealtimeEvents();
      activityCount += events.length;
      let shouldPull: boolean = false;
      let disconnected: boolean = false;
      for (let index: number = 0; index < events.length; index++) {
        let event: SyncEvent = events[index];
        if (event.eventType === 'hello' || event.eventType === 'resync') {
          shouldPull = true;
        } else if (event.eventType === 'update' && event.detail !== this.latestContentId) {
          shouldPull = true;
        } else if (event.eventType === 'disconnected') {
          disconnected = true;
        }
      }
      if (disconnected) {
        this.realtimeActive = false;
        this.statusCode = 3;
        this.reportError('sync', 'realtime connection was disconnected by the server.');
        return activityCount;
      }
      if (shouldPull) {
        await this.pullLatestFromRealtime(client);
      }
    } catch (error) {
      this.realtimeActive = false;
      this.statusCode = 3;
      this.reportError('sync', 'failed to consume realtime events: ' + this.errorDetail(error));
    } finally {
      this.sseEventBusy = false;
    }
    return activityCount;
  }

  public onEngineRuntimeEvent(event: EngineRuntimeEvent): void {
    if (event.kind === 'active_clipboard_changed' || event.kind === 'incoming_entry' ||
      event.kind === 'inbound_notice' || event.kind === 'incoming_pending' ||
      event.kind === 'receive_attempt_state_changed') {
      this.scheduleOfficialEngineInboundRefresh();
    } else if (event.kind === 'device_trust_changed' || event.kind === 'refresh_required') {
      this.refreshSpaceDevices();
    }
  }

  private scheduleOfficialEngineInboundRefresh(): void {
    if (!this.spaceJoined) {
      return;
    }
    if (this.officialEngineInboundRefreshBusy) {
      this.officialEngineInboundRefreshQueued = true;
      return;
    }
    if (this.officialEngineInboundRefreshTimerId >= 0) {
      return;
    }
    this.officialEngineInboundRefreshTimerId = setTimeout((): void => {
      this.officialEngineInboundRefreshTimerId = -1;
      this.consumeOfficialEngineInbound().catch((): void => {
        this.scheduleOfficialEngineInboundRetry();
      });
    }, 0);
  }

  private async consumeOfficialEngineInbound(): Promise<void> {
    if (!this.spaceJoined) {
      return;
    }
    if (this.officialEngineInboundRefreshBusy) {
      this.officialEngineInboundRefreshQueued = true;
      return;
    }
    this.officialEngineInboundRefreshBusy = true;
    let consumed: boolean = false;
    try {
      consumed = await this.consumeOfficialEngineClipboard();
    } catch (error) {
      consumed = false;
    } finally {
      this.officialEngineInboundRefreshBusy = false;
    }
    if (this.officialEngineInboundRefreshQueued) {
      this.officialEngineInboundRefreshQueued = false;
      this.officialEngineInboundRefreshRetryCount = 0;
      this.scheduleOfficialEngineInboundRefresh();
    } else if (consumed) {
      this.officialEngineInboundRefreshRetryCount = 0;
    } else {
      this.scheduleOfficialEngineInboundRetry();
    }
  }

  private async pollOfficialEngineInbound(): Promise<number> {
    if (!this.spaceJoined || this.officialEngineInboundRefreshBusy) {
      return 0;
    }
    this.officialEngineInboundRefreshBusy = true;
    let consumed: boolean = false;
    try {
      consumed = await this.consumeOfficialEngineClipboard();
    } catch (error) {
      consumed = false;
    } finally {
      this.officialEngineInboundRefreshBusy = false;
      this.officialEngineInboundRefreshQueued = false;
    }
    return consumed ? 1 : 0;
  }

  private scheduleOfficialEngineInboundRetry(): void {
    if (!this.spaceJoined || this.officialEngineInboundRefreshTimerId >= 0 ||
      this.officialEngineInboundRefreshRetryCount >= OFFICIAL_ENGINE_ENTRY_MAX_RETRIES) {
      return;
    }
    this.officialEngineInboundRefreshRetryCount += 1;
    this.officialEngineInboundRefreshTimerId = setTimeout((): void => {
      this.officialEngineInboundRefreshTimerId = -1;
      this.consumeOfficialEngineInbound().catch((): void => {
      });
    }, OFFICIAL_ENGINE_ENTRY_RETRY_DELAY_MS);
  }

  private async consumeOfficialEngineClipboard(): Promise<boolean> {
    if (!this.spaceJoined) {
      return true;
    }
    await this.ensureOfficialEngineRunning();
    let active = await engineRuntimeService.queryActiveClipboard();
    if (active === null || active.entryId.length === 0 || active.entryId === this.lastOfficialActiveEntryId) {
      return false;
    }
    if (this.isOfficialEngineLocalDevice(active.activatedBy)) {
      this.lastOfficialActiveEntryId = active.entryId;
      return false;
    }
    try {
      let exportedPath: string = await this.exportOfficialEngineEntry(active.entryId);
      let payload: ClipboardFilePayload = this.clipboardService.readFile(exportedPath);
      let imagePayload: image.PixelMap | null = await this.tryDecodeOfficialEngineImage(payload.data);
      this.lastOfficialActiveEntryId = active.entryId;
      this.latestContentId = active.entryId;
      if (imagePayload !== null) {
        this.applyOfficialEngineImage(active, payload, imagePayload, exportedPath);
      } else if (this.isLikelyOfficialEngineText(payload.data)) {
        this.applyOfficialEngineText(active, payload.data);
      } else {
        this.applyOfficialEngineFile(active, payload, exportedPath);
      }
    } catch (error) {
      return false;
    }
    this.spacePeerConnected = true;
    this.statusCode = 2;
    this.animateLatestContent();
    return true;
  }

  private async ensureOfficialEngineRunning(): Promise<void> {
    let snapshot = engineRuntimeService.getSnapshot();
    if (snapshot.state === EngineRuntimeState.RUNNING) {
      return;
    }
    let context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      throw new Error('no application context for official Engine recovery');
    }
    await engineRuntimeService.prepare(context as common.UIAbilityContext);
    await engineRuntimeService.start();
    let recovery: EngineSessionRecovery = await engineRuntimeService.recoverSession(true);
    if (recovery.resumed) {
      this.setSpaceJoined(true);
    }
  }

  private isOfficialEngineLocalDevice(deviceId: string): boolean {
    for (let index: number = 0; index < this.spaceDevices.length; index += 1) {
      let device: EngineRuntimeDevice = this.spaceDevices[index];
      if (device.deviceId === deviceId) {
        return device.isLocal;
      }
    }
    return false;
  }

  private async exportOfficialEngineEntry(entryId: string): Promise<string> {
    let context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      throw new Error('no application context for official Engine export');
    }
    let directory: string = context.filesDir + '/engine-received';
    try {
      fileIo.mkdirSync(directory, true);
    } catch (error) {
    }
    let path: string = directory + '/entry-' + this.safeOfficialEngineFilePart(entryId) + '-' +
      Date.now().toString() + '.bin';
    let target: fileIo.File = fileIo.openSync(path,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    fileIo.closeSync(target.fd);
    await engineRuntimeService.exportEntryToUri(entryId, path);
    return path;
  }

  private safeOfficialEngineFilePart(value: string): string {
    let safe: string = value.replace(/[^a-zA-Z0-9_-]/g, '_');
    return safe.length > 0 ? safe : 'entry';
  }

  private async tryDecodeOfficialEngineImage(data: Uint8Array): Promise<image.PixelMap | null> {
    if (!this.isOfficialEngineImageData(data)) {
      return null;
    }
    try {
      return await this.clipboardService.decodeImage(data);
    } catch (error) {
      return null;
    }
  }

  private isOfficialEngineImageData(data: Uint8Array): boolean {
    if (data.length >= 8 && data[0] === 137 && data[1] === 80 && data[2] === 78 && data[3] === 71 &&
      data[4] === 13 && data[5] === 10 && data[6] === 26 && data[7] === 10) {
      return true;
    }
    if (data.length >= 3 && data[0] === 255 && data[1] === 216 && data[2] === 255) {
      return true;
    }
    if (data.length >= 6 && data[0] === 71 && data[1] === 73 && data[2] === 70 && data[3] === 56) {
      return true;
    }
    if (data.length >= 2 && data[0] === 66 && data[1] === 77) {
      return true;
    }
    return data.length >= 12 && data[0] === 82 && data[1] === 73 && data[2] === 70 && data[3] === 70 &&
      data[8] === 87 && data[9] === 69 && data[10] === 66 && data[11] === 80;
  }

  private isLikelyOfficialEngineText(data: Uint8Array): boolean {
    if (data.length === 0 || data.length > 1024 * 1024) {
      return false;
    }
    let controls: number = 0;
    for (let index: number = 0; index < data.length; index += 1) {
      let value: number = data[index];
      if (value === 0) {
        return false;
      }
      if (value < 32 && value !== 9 && value !== 10 && value !== 13) {
        controls += 1;
      }
    }
    return controls * 20 < data.length;
  }

  private applyOfficialEngineText(active: EngineActiveClipboard, data: Uint8Array): void {
    let decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { fatal: false, ignoreBOM: true });
    let text: string = decoder.decodeToString(data);
    this.latestText = text;
    this.latestKind = 'Text';
    this.latestImage = null;
    if (this.desktopSelectedId.length === 0) {
      this.releaseDesktopAudio();
      this.refreshCurrentLinkPreview();
    }
    this.addHistory(text, 'received', 'Text', null, null, '', active.entryId, active.activatedBy);
    this.clipboardService.writeText(text).catch((): void => {
    });
    this.notifyReceivedContent('Text', text, null, 0, active.activatedBy);
  }

  private applyOfficialEngineImage(active: EngineActiveClipboard, payload: ClipboardFilePayload,
    pixelMap: image.PixelMap, path: string): void {
    this.latestKind = 'Image';
    this.latestText = 'image.png';
    this.latestImage = pixelMap;
    this.latestImageRevision += 1;
    if (this.desktopSelectedId.length === 0) {
      this.releaseDesktopAudio();
      this.clearLinkPreview();
    }
    this.addHistory(this.latestText, 'received', 'Image', pixelMap, null, path, active.entryId,
      active.activatedBy);
    this.clipboardService.writeImage(pixelMap).catch((): void => {
    });
    this.notifyReceivedContent('Image', this.latestText, pixelMap, payload.data.length, active.activatedBy);
  }

  private applyOfficialEngineFile(active: EngineActiveClipboard, payload: ClipboardFilePayload, path: string): void {
    let fileName: string = this.fileNameForOfficialEnginePayload(payload.data);
    this.latestKind = 'File';
    this.latestText = fileName;
    this.latestFileName = fileName;
    this.latestFileData = null;
    this.latestFilePath = path;
    this.latestFileRevision += 1;
    this.desktopFilePreviewState = 0;
    this.resetDesktopVideoAspectRatio();
    if (this.desktopSelectedId.length === 0) {
      this.releaseDesktopAudio();
      this.clearLinkPreview();
    }
    this.latestImage = null;
    this.addHistory(fileName, 'received', 'File', null, null, path, active.entryId, active.activatedBy);
    this.notifyReceivedContent('File', fileName, null, payload.data.length, active.activatedBy);
  }

  private fileNameForOfficialEnginePayload(data: Uint8Array): string {
    if (data.length >= 5 && data[0] === 37 && data[1] === 80 && data[2] === 68 && data[3] === 70 &&
      data[4] === 45) {
      return 'received-file.pdf';
    }
    if (data.length >= 4 && data[0] === 80 && data[1] === 75 && data[2] === 3 && data[3] === 4) {
      return 'received-file.zip';
    }
    return 'received-file';
  }

  private copyLocalFileToUri(sourcePath: string, targetUri: string): void {
    let source: fileIo.File = fileIo.openSync(sourcePath, fileIo.OpenMode.READ_ONLY);
    try {
      fileIo.copyFileSync(source.fd, targetUri);
    } finally {
      fileIo.closeSync(source.fd);
    }
  }

  public async pullLatestFromRealtime(client: MobileSyncClient): Promise<void> {
    let result: SyncContent = await client.getLatestContent();
    let sameContentId: boolean = result.contentId.length > 0 && result.contentId === this.latestContentId;
    let incomingDisplayText: string = this.contentDisplayText(result);
    let sameLegacyContent: boolean = result.contentId.length === 0 && result.kind === 'Text' &&
      result.kind === this.latestKind &&
      incomingDisplayText === this.latestText;
    if (!sameContentId && !sameLegacyContent) {
      await this.applyLatestContent(result, true);
      let notificationPreview: image.PixelMap | null = result.kind === 'Image' ? this.latestImage : null;
      if (result.kind === 'File' && this.isImageFileName(result.dataName) && result.data.length > 0) {
        try {
          notificationPreview = await this.clipboardService.decodeImage(result.data);
        } catch (error) {
          notificationPreview = null;
        }
      }
      let notificationName: string = result.kind === 'File' && result.dataName.length > 0 ?
        result.dataName : this.contentDisplayText(result);
      this.notifyReceivedContent(result.kind, notificationName, notificationPreview, result.data.length);
    }
    this.statusCode = 2;
  }

  public notifyReceivedContent(kind: string, displayName: string, preview: image.PixelMap | null = null,
    fileSize: number = 0, sourceLabel: string = ''): void {
    let context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    this.receivedNotificationService.notifyReceived(context as common.UIAbilityContext, kind, displayName,
      preview, fileSize, sourceLabel);
  }

  public sourceLabelForDevice(deviceId: string): string {
    if (deviceId.length === 0) {
      return '';
    }
    for (let index: number = 0; index < this.spaceDevices.length; index++) {
      let device: EngineRuntimeDevice = this.spaceDevices[index];
      if (device.deviceId !== deviceId) {
        continue;
      }
      let typeLabel: string = this.sourceDeviceTypeLabel(device.deviceType);
      if (device.deviceName.length > 0) {
        return device.deviceName + ' · ' + typeLabel;
      }
      return typeLabel;
    }
    return '远端设备';
  }

  public sourceDeviceTypeLabel(deviceType: string): string {
    if (deviceType === 'phone') {
      return '手机';
    }
    if (deviceType === 'tablet') {
      return '平板';
    }
    if (deviceType === '2in1') {
      return '电脑';
    }
    if (deviceType === 'tv') {
      return '电视';
    }
    if (deviceType === 'wearable') {
      return '穿戴设备';
    }
    if (deviceType === 'car') {
      return '车机';
    }
    return '电脑';
  }

  public isImageFileName(name: string): boolean {
    let dot: number = name.lastIndexOf('.');
    if (dot < 0 || dot === name.length - 1) {
      return false;
    }
    let extension: string = name.substring(dot + 1).toLowerCase();
    return extension === 'jpg' || extension === 'jpeg' || extension === 'png' || extension === 'gif' ||
      extension === 'webp' || extension === 'bmp';
  }

  public async loadServerHistory(reset: boolean): Promise<void> {
    if (!this.hasConfig()) {
      this.statusCode = 3;
      this.openConnectionSettings();
      return;
    }
    if (this.historyLoading) {
      if (reset) {
        this.historyResetPending = true;
      }
      return;
    }
    if (!reset && this.historyEnd) {
      return;
    }
    let page: number = reset ? 1 : this.historyPage;
    this.historyLoading = true;
    this.statusCode = 1;
    try {
      let client: MobileSyncClient = new MobileSyncClient(this.getConfig());
      let items: ServerHistoryItem[] = await client.queryHistory(
        page, this.historySearchText, this.historyStarredOnly);
      if (reset) {
        this.serverHistory = items;
      } else {
        this.serverHistory = [...this.serverHistory, ...items];
      }
      if (items.length === 0) {
        this.historyEnd = true;
      } else {
        this.historyPage = page + 1;
        this.historyEnd = false;
      }
      this.statusCode = 2;
    } catch (error) {
      this.statusCode = 3;
    } finally {
      this.historyLoading = false;
      if (this.historyResetPending) {
        this.historyResetPending = false;
        this.loadServerHistory(true);
      }
    }
  }

  public replaceServerHistoryItem(updated: ServerHistoryItem): void {
    let items: ServerHistoryItem[] = [];
    for (let index: number = 0; index < this.serverHistory.length; index++) {
      let item: ServerHistoryItem = this.serverHistory[index];
      items.push(item.id === updated.id ? updated : item);
    }
    this.serverHistory = items;
  }

  public async toggleHistoryStarred(item: ServerHistoryItem): Promise<void> {
    if (this.historyMutationBusy) {
      return;
    }
    this.historyMutationBusy = true;
    try {
      let client: MobileSyncClient = new MobileSyncClient(this.getConfig());
      let updated: ServerHistoryItem = await client.setHistoryStarred(item, !item.starred);
      this.replaceServerHistoryItem(updated);
      this.statusCode = 2;
    } catch (error) {
      this.statusCode = 3;
    } finally {
      this.historyMutationBusy = false;
    }
  }

  public async toggleHistoryPinned(item: ServerHistoryItem): Promise<void> {
    if (this.historyMutationBusy) {
      return;
    }
    this.historyMutationBusy = true;
    try {
      let client: MobileSyncClient = new MobileSyncClient(this.getConfig());
      let updated: ServerHistoryItem = await client.setHistoryPinned(item, !item.pinned);
      this.replaceServerHistoryItem(updated);
      this.statusCode = 2;
    } catch (error) {
      this.statusCode = 3;
    } finally {
      this.historyMutationBusy = false;
    }
  }

  public async confirmDeleteHistory(item: ServerHistoryItem): Promise<void> {
    let confirmed: boolean = false;
    try {
      let result = await this.getUIContext().getPromptAction().showDialog({
        title: $r('app.string.history_delete_title'),
        message: $r('app.string.history_delete_message'),
        buttons: [
          { text: $r('app.string.cancel_action'), color: $r('app.color.text_secondary') },
          { text: $r('app.string.history_delete_action'), color: $r('app.color.danger') }
        ]
      });
      confirmed = result.index === 1;
    } catch (error) {
      this.statusCode = 3;
      return;
    }
    if (!confirmed || this.historyMutationBusy) {
      return;
    }
    this.historyMutationBusy = true;
    try {
      let client: MobileSyncClient = new MobileSyncClient(this.getConfig());
      await client.deleteHistory(item);
      let items: ServerHistoryItem[] = [];
      for (let index: number = 0; index < this.serverHistory.length; index++) {
        let current: ServerHistoryItem = this.serverHistory[index];
        if (current.id !== item.id) {
          items.push(current);
        }
      }
      this.serverHistory = items;
      this.statusCode = 2;
    } catch (error) {
      this.statusCode = 3;
    } finally {
      this.historyMutationBusy = false;
    }
  }

}
