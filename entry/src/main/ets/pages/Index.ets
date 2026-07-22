import { LengthMetrics, mediaquery, SymbolGlyphModifier, window } from '@kit.ArkUI';
import {
  common,
  ConfigurationConstant
} from '@kit.AbilityKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { image } from '@kit.ImageKit';
import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import { filePreview } from '@kit.PreviewKit';
import { harmonyShare, systemShare } from '@kit.ShareKit';
import { preferences, uniformTypeDescriptor } from '@kit.ArkData';
import {
  hdsMaterial,
  HdsNavDestination,
  HdsNavDestinationTitleMode,
  HdsNavigation,
  HdsNavigationTitleMode,
  HdsTabs,
  IconType,
  IconStyleMode,
  ScrollEffectType
} from '@kit.UIDesignKit';
import {
  ClipboardHistoryItem,
  ServerConfig,
  ServerHistoryItem,
  SyncContent,
  SyncEvent
} from '../model/ClipboardModels';
import { ClipboardFileSelection, ClipboardService } from '../service/ClipboardService';
import {
  APPEARANCE_MODE_DARK,
  APPEARANCE_MODE_LIGHT,
  APPEARANCE_MODE_SYSTEM,
  APPEARANCE_THEME_DEFAULT,
  AppearanceStorageService
} from '../service/AppearanceStorageService';
import { ConfigStorageService } from '../service/ConfigStorageService';
import { BackgroundSyncPreferenceService } from '../service/BackgroundSyncService';
import { HistoryStorageService } from '../service/HistoryStorageService';
import { MobileSyncClient } from '../service/MobileSyncClient';
import { MobileSyncServerService } from '../service/MobileSyncServerService';
import { NativeProtocolService } from '../service/NativeProtocolService';
import { ReceivedNotificationService } from '../service/NotificationService';
import { SpaceNodeService } from '../service/SpaceNodeService';
import { OnboardingGuide } from '../components/OnboardingGuide';
import {
  NativeCreateSpaceResult,
  NativeJoinSpaceResult,
  NativeSpaceDevice,
  NativeSpaceFileEvent,
  NativeSpaceFileSendResult,
  NativeSpaceFileStatusEvent,
  NativeSpaceImageEvent,
  NativeSpaceInvitation,
  NativeSpaceStatus,
  NativeSpaceTextEvent,
  NativeMobileSyncCredential,
  NativeMobileSyncDevice,
  NativeMobileSyncInboundEvent,
  NativeMobileSyncStatus
} from 'uniclipboard_native';

class AudioLyricLine {
  timeMs: number = 0;
  text: string = '';

  constructor(timeMs: number, text: string) {
    this.timeMs = timeMs;
    this.text = text;
  }
}

class AppearanceThemeOption {
  id: string = '';
  primaryColor: string = '';
  secondaryColor: string = '';

  constructor(id: string, primaryColor: string, secondaryColor: string) {
    this.id = id;
    this.primaryColor = primaryColor;
    this.secondaryColor = secondaryColor;
  }
}

const APPEARANCE_THEME_OPTIONS: AppearanceThemeOption[] = [
  new AppearanceThemeOption(APPEARANCE_THEME_DEFAULT, '#0A59F7', '#317AF7'),
  new AppearanceThemeOption('sky_cyan', '#3EB4F8', '#5DEAB5'),
  new AppearanceThemeOption('aurora_green', '#5DEAB5', '#AF64EE'),
  new AppearanceThemeOption('nebula_purple', '#AF64EE', '#FB638D'),
  new AppearanceThemeOption('sunset_orange', '#F99844', '#FFE345'),
  new AppearanceThemeOption('blossom_pink', '#FB638D', '#AF64EE')
];

const FEEDBACK_EMAIL: string = '3514795319@qq.com';
const ONBOARDING_STORE_NAME: string = 'onboarding_preferences';
const ONBOARDING_COMPLETED_KEY: string = 'onboarding_completed';

@Entry
@Component
struct Index {
  @StorageProp('avoidAreaRectHeight') avoidAreaRectHeight: number = 0;
  @StorageProp('navigationRectHeight') navigationRectHeight: number = 0;
  @State selectedTab: number = 0;
  @State isWideScreen: boolean = false;
  @State isLargeScreen: boolean = false;
  @State statusCode: number = 0;
  @State busy: boolean = false;
  @State serverUrl: string = '';
  @State username: string = '';
  @State password: string = '';
  @State connectUri: string = '';
  @State connectUriState: number = 0;
  @State legacyConnectionExpanded: boolean = false;
  @State composerText: string = '';
  @State latestText: string = '';
  @State latestKind: string = 'Text';
  @State latestImage: image.PixelMap | null = null;
  @State latestImageRevision: number = 0;
  @State composerImage: image.PixelMap | null = null;
  @State composerImageRevision: number = 0;
  @State imageReadState: number = 0;
  @State imageSendState: number = 0;
  @State composerFileName: string = '';
  @State latestFileName: string = '';
  @State latestFileRevision: number = 0;
  @State fileTransferState: number = 0;
  @State latestContentId: string = '';
  @State history: ClipboardHistoryItem[] = [];
  @State serverHistory: ServerHistoryItem[] = [];
  @State historyPage: number = 1;
  @State historyEnd: boolean = false;
  @State historyLoading: boolean = false;
  @State historySearchText: string = '';
  @State historyStarredOnly: boolean = false;
  @State historyMutationBusy: boolean = false;
  @State desktopRefreshBusy: boolean = false;
  @State realtimeActive: boolean = false;
  @State showAboutSheet: boolean = false;
  @State showFeedbackSheet: boolean = false;
  @State showOnboardingGuide: boolean = false;
  @State feedbackText: string = '';
  @State aboutMaterialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.SMOOTH;
  @State spaceNodeState: number = 0;
  @StorageLink('spaceJoined') spaceJoined: boolean = false;
  @State spacePeerConnected: boolean = false;
  @State spaceDevices: NativeSpaceDevice[] = [];
  @State spaceDeviceName: string = '';
  @State spaceInvitationCode: string = '';
  @State spacePassphrase: string = '';
  @State spaceJoinDeviceName: string = '';
  @State spaceJoinBusy: boolean = false;
  @State spaceJoinState: number = 0;
  @State spaceSwitchOpen: boolean = false;
  @State spaceActionMode: number = 0;
  @State spaceCreateDeviceName: string = '';
  @State spaceCreateDeviceNameRecommended: boolean = false;
  @State spaceCreatePassphrase: string = '';
  @State spaceCreatePassphraseConfirm: string = '';
  @State spaceCreateBusy: boolean = false;
  @State spaceCreateState: number = 0;
  @State spaceCreatedId: string = '';
  @State spaceIssuedInvitationCode: string = '';
  @State spaceInvitationExpiresAtMs: number = 0;
  @State spaceInvitationScanState: number = 0;
  @State spaceInvitationBusy: boolean = false;
  @State mobileInvitationOpen: boolean = false;
  @State spaceConnectBusy: boolean = false;
  @State spaceConnectingDeviceId: string = '';
  @State spaceConnectState: number = 0;
  @State largeSection: number = 0;
  @State largeSettingsSection: number = 0;
  @State desktopSelectedId: string = '';
  @State desktopSelectedText: string = '';
  @State desktopSelectedMeta: string = '';
  @State desktopSelectedDirection: string = '';
  @State desktopSelectedImage: image.PixelMap | null = null;
  @State desktopSelectedImageRevision: number = 0;
  @State desktopFilePreviewState: number = 0;
  @State desktopVideoAspectRatio: number = 16 / 9;
  @State desktopAudioState: number = 0;
  @State desktopAudioPosition: number = 0;
  @State desktopAudioDuration: number = 0;
  @State desktopAudioSeeking: boolean = false;
  @State desktopAudioCover: image.PixelMap | null = null;
  @State desktopAudioCoverRevision: number = 0;
  @State desktopAudioTitle: string = '';
  @State desktopAudioArtist: string = '';
  @State desktopAudioAlbum: string = '';
  @State desktopAudioLyrics: AudioLyricLine[] = [];
  @State desktopAudioPlainLyrics: string = '';
  @State desktopAudioMetadataState: number = 0;
  @State desktopGestureShareState: number = 0;
  @State desktopGestureShareHintDismissed: boolean = false;
  @State desktopStarredOnly: boolean = false;
  @State desktopTypeFilter: number = 0;
  @State desktopTagFilter: number = 0;
  @State desktopSourceFilter: number = 0;
  @State desktopTimeFilter: number = 0;
  @State desktopExtensionFilter: string = '';
  @State appearanceMode: string = APPEARANCE_MODE_SYSTEM;
  @State appearanceThemeId: string = APPEARANCE_THEME_DEFAULT;
  @State latestContentPulse: number = 1;
  @State historyPulse: number = 1;
  @StorageLink('backgroundSyncEnabled') backgroundSyncEnabled: boolean = false;
  @State mobileSyncEnabled: boolean = false;
  @State mobileSyncRunning: boolean = false;
  @State mobileSyncPort: string = '42720';
  @State mobileSyncUrls: string[] = [];
  @State mobileSyncDevices: NativeMobileSyncDevice[] = [];
  @State mobileSyncBusy: boolean = false;
  @State mobileSyncState: number = 0;
  @State desktopDeviceMutationBusy: boolean = false;
  @State mobileSyncAddOpen: boolean = false;
  @State mobileSyncAdvancedOpen: boolean = false;
  @State mobileSyncDeviceName: string = '';
  @State mobileSyncCustomUsername: string = '';
  @State mobileSyncCustomPassword: string = '';
  @State mobileSyncCredential: NativeMobileSyncCredential | null = null;
  @State mobileSyncPasswordVisible: boolean = false;

  private clipboardService: ClipboardService = new ClipboardService();
  private appearanceStorageService: AppearanceStorageService = new AppearanceStorageService();
  private configStorageService: ConfigStorageService = new ConfigStorageService();
  private backgroundSyncPreferenceService: BackgroundSyncPreferenceService =
    new BackgroundSyncPreferenceService();
  private historyStorageService: HistoryStorageService = new HistoryStorageService();
  private mobileSyncServerService: MobileSyncServerService = new MobileSyncServerService();
  private receivedNotificationService: ReceivedNotificationService =
    ReceivedNotificationService.getInstance();
  private nativeProtocolService: NativeProtocolService = new NativeProtocolService();
  private spaceNodeService: SpaceNodeService = new SpaceNodeService();
  private largeNavStack: NavPathStack = new NavPathStack();
  private wideScreenListener: mediaquery.MediaQueryListener | null = null;
  private largeScreenListener: mediaquery.MediaQueryListener | null = null;
  private sseTimerId: number = -1;
  private historySearchTimerId: number = -1;
  private sseEventBusy: boolean = false;
  private spaceDeviceRefreshBusy: boolean = false;
  private historyResetPending: boolean = false;
  private historyRestoreStarted: boolean = false;
  private historyRestored: boolean = false;
  private historySaveBusy: boolean = false;
  private historySavePending: boolean = false;
  private realtimeTick: number = 0;
  private realtimeAutoConnect: boolean = false;
  private mobileSyncDeviceRefreshBusy: boolean = false;
  private syncScroller: Scroller = new Scroller();
  private devicesScroller: Scroller = new Scroller();
  private settingsScroller: Scroller = new Scroller();
  private aboutScroller: Scroller = new Scroller();
  private configRestored: boolean = false;
  private composerFileData: Uint8Array | null = null;
  private composerFileUri: string = '';
  private composerFileSize: number = 0;
  private composerFileHistoryId: string = '';
  private latestFileData: Uint8Array | null = null;
  private latestFilePath: string = '';
  private latestCachedFilePath: string = '';
  private desktopSelectedFileData: Uint8Array | null = null;
  private desktopSelectedFilePath: string = '';
  private desktopVideoRatioKey: string = '';
  private desktopAudioPlayer: media.AVPlayer | null = null;
  private desktopAudioSourceFile: fileIo.File | null = null;
  private desktopAudioKey: string = '';
  private desktopAudioPlayWhenReady: boolean = false;
  private desktopGestureShareWindowId: number = -1;
  private desktopGestureShareResetTimerId: number = -1;
  private desktopGestureShareRegistering: boolean = false;
  private desktopGestureSharePageVisible: boolean = false;
  private pendingFileTransferId: string = '';
  private openOnboardingAfterAbout: boolean = false;

  private loadOnboardingState(): void {
    try {
      let context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      let options: preferences.Options = { name: ONBOARDING_STORE_NAME };
      let store: preferences.Preferences = preferences.getPreferencesSync(context, options);
      let completed: boolean = store.getSync(ONBOARDING_COMPLETED_KEY, false) as boolean;
      this.showOnboardingGuide = !completed;
    } catch (error) {
      this.showOnboardingGuide = true;
      console.error('Index: failed to load onboarding state: ' + JSON.stringify(error));
    }
  }

  private completeOnboarding(): void {
    try {
      let context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      let options: preferences.Options = { name: ONBOARDING_STORE_NAME };
      let store: preferences.Preferences = preferences.getPreferencesSync(context, options);
      store.putSync(ONBOARDING_COMPLETED_KEY, true);
      store.flushSync();
    } catch (error) {
      console.error('Index: failed to save onboarding state: ' + JSON.stringify(error));
    }
  }

  private reopenOnboardingGuide(): void {
    if (this.showAboutSheet) {
      this.openOnboardingAfterAbout = true;
      this.showAboutSheet = false;
      return;
    }
    this.showOnboardingGuide = true;
  }

  private onAboutSheetDisappear(): void {
    this.showAboutSheet = false;
    if (this.openOnboardingAfterAbout) {
      this.openOnboardingAfterAbout = false;
      this.showOnboardingGuide = true;
    }
  }

  @Builder
  private OnboardingGuideBuilder() {
    OnboardingGuide({
      visible: this.showOnboardingGuide,
      onCompleted: (): void => {
        this.completeOnboarding();
      }
    })
  }

  aboutToAppear(): void {
    this.loadOnboardingState();
    let materialTypes: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes();
    if (materialTypes.indexOf(hdsMaterial.MaterialType.IMMERSIVE) >= 0) {
      this.aboutMaterialLevel = hdsMaterial.MaterialLevel.EXQUISITE;
    }
    let wideListener: mediaquery.MediaQueryListener = this.getUIContext().getMediaQuery()
      .matchMediaSync('(840vp<=width)');
    this.wideScreenListener = wideListener;
    this.isWideScreen = wideListener.matches;
    wideListener.on('change', (result: mediaquery.MediaQueryResult): void => {
      this.isWideScreen = result.matches;
      if (!result.matches && this.desktopSelectedId.length > 0) {
        this.showLatestClipboardContent();
      }
    });
    let largeListener: mediaquery.MediaQueryListener = this.getUIContext().getMediaQuery()
      .matchMediaSync('(1200vp<=width)');
    this.largeScreenListener = largeListener;
    this.isLargeScreen = largeListener.matches;
    largeListener.on('change', (result: mediaquery.MediaQueryResult): void => {
      this.isLargeScreen = result.matches;
    });
    this.initializeRecommendedSpaceDeviceName();
    this.selectPage(this.selectedTab);
    this.sseTimerId = setInterval(() => {
      this.consumeRealtimeEvents();
    }, 1000);
    this.restoreConfig();
    this.restoreBackgroundSyncPreference();
    this.restoreAppearanceMode();
    this.restoreAppearanceTheme();
    this.restoreLocalHistory();
    this.initializeSpaceNode();
  }

  onPageShow(): void {
    this.desktopGestureSharePageVisible = true;
    this.registerDesktopGestureShare();
  }

  onPageHide(): void {
    this.desktopGestureSharePageVisible = false;
    this.unregisterDesktopGestureShare();
  }

  aboutToDisappear(): void {
    if (this.wideScreenListener !== null) {
      this.wideScreenListener.off('change');
      this.wideScreenListener = null;
    }
    if (this.largeScreenListener !== null) {
      this.largeScreenListener.off('change');
      this.largeScreenListener = null;
    }
    if (this.sseTimerId >= 0) {
      clearInterval(this.sseTimerId);
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
  }

  private showLatestClipboardContent(): void {
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
  }

  private getConfig(): ServerConfig {
    let config: ServerConfig = {
      baseUrl: this.serverUrl,
      username: this.username,
      password: this.password
    };
    return config;
  }

  private restoreConfig(): void {
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
      if (this.hasConfig()) {
        this.realtimeAutoConnect = true;
        this.startRealtime();
      }
    } catch (error) {
      this.statusCode = 3;
    }
  }

  private saveConfig(): void {
    let context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    this.configStorageService.save(context, this.getConfig());
  }

  private restoreBackgroundSyncPreference(): void {
    let context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    this.backgroundSyncEnabled = this.backgroundSyncPreferenceService.load(context);
  }

  private setBackgroundSyncEnabled(enabled: boolean): void {
    this.backgroundSyncEnabled = enabled;
    let context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context !== undefined) {
      this.backgroundSyncPreferenceService.save(context, enabled);
    }
  }

  private restoreAppearanceMode(): void {
    let context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    this.appearanceMode = this.appearanceStorageService.load(context);
  }

  private restoreAppearanceTheme(): void {
    let context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    let storedThemeId: string = this.appearanceStorageService.loadTheme(context);
    this.appearanceThemeId = this.getAppearanceTheme(storedThemeId).id;
  }

  private selectAppearanceMode(mode: string): void {
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
      console.error('UniClipboard failed to update the appearance mode.');
    }
  }

  private selectAppearanceTheme(themeId: string): void {
    let theme: AppearanceThemeOption = this.getAppearanceTheme(themeId);
    this.appearanceThemeId = theme.id;
    let context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context !== undefined) {
      this.appearanceStorageService.saveTheme(context, theme.id);
    }
  }

  private getAppearanceTheme(themeId: string): AppearanceThemeOption {
    for (let index: number = 0; index < APPEARANCE_THEME_OPTIONS.length; index++) {
      let option: AppearanceThemeOption = APPEARANCE_THEME_OPTIONS[index];
      if (option.id === themeId) {
        return option;
      }
    }
    return APPEARANCE_THEME_OPTIONS[0];
  }

  private appearanceThemeLabel(themeId: string): Resource {
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

  private accentColor(): ResourceColor {
    if (this.appearanceThemeId === APPEARANCE_THEME_DEFAULT) {
      return $r('app.color.accent');
    }
    return this.getAppearanceTheme(this.appearanceThemeId).primaryColor;
  }

  private accentSecondaryColor(): ResourceColor {
    if (this.appearanceThemeId === APPEARANCE_THEME_DEFAULT) {
      return $r('app.color.accent_secondary');
    }
    return this.getAppearanceTheme(this.appearanceThemeId).secondaryColor;
  }

  private historyMenuSymbol(symbol: Resource): SymbolGlyphModifier {
    let modifier: SymbolGlyphModifier = new SymbolGlyphModifier(symbol);
    modifier.fontSize('20vp');
    modifier.fontColor([this.accentSecondaryColor()]);
    return modifier;
  }

  private historyDeleteMenuSymbol(): SymbolGlyphModifier {
    let modifier: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.xmark'));
    modifier.fontSize('20vp');
    modifier.fontColor([$r('app.color.danger')]);
    return modifier;
  }

  private accentSoftColor(): ResourceColor {
    if (this.appearanceThemeId === APPEARANCE_THEME_DEFAULT) {
      return $r('app.color.accent_soft');
    }
    return '#19' + this.getAppearanceTheme(this.appearanceThemeId).primaryColor.substring(1);
  }

  private accentMediumColor(): ResourceColor {
    if (this.appearanceThemeId === APPEARANCE_THEME_DEFAULT) {
      return $r('app.color.accent_medium');
    }
    return '#33' + this.getAppearanceTheme(this.appearanceThemeId).primaryColor.substring(1);
  }

  private titleBarConnectionIcon(): IconType {
    if (this.isConnectionAvailable()) {
      return $r('sys.symbol.connection');
    }
    const modifier: SymbolGlyphModifier =
      new SymbolGlyphModifier($r('sys.symbol.unconnection'));
    modifier.fontColor([$r('app.color.danger')]);
    return modifier;
  }

  private async restoreLocalHistory(): Promise<void> {
    if (this.historyRestoreStarted) {
      return;
    }
    this.historyRestoreStarted = true;
    try {
      let context: common.Context | undefined = this.getUIContext().getHostContext();
      if (context === undefined) {
        return;
      }
      let storedItems: ClipboardHistoryItem[] = await this.historyStorageService.load(context);
      let mergedItems: ClipboardHistoryItem[] = [];
      let knownIds: Set<string> = new Set<string>();
      for (let index: number = 0; index < this.history.length && mergedItems.length < 200; index++) {
        let item: ClipboardHistoryItem = this.history[index];
        mergedItems.push(item);
        knownIds.add(item.id);
      }
      for (let index: number = 0; index < storedItems.length && mergedItems.length < 200; index++) {
        let item: ClipboardHistoryItem = storedItems[index];
        if (!knownIds.has(item.id)) {
          mergedItems.push(item);
          knownIds.add(item.id);
        }
      }
      this.history = mergedItems;
    } catch (error) {
      console.error('UniClipboard failed to restore local clipboard history.');
    } finally {
      this.historyRestored = true;
      if (this.historySavePending) {
        this.historySavePending = false;
        this.scheduleHistorySave();
      }
    }
  }

  private scheduleHistorySave(): void {
    if (!this.historyRestored || this.historySaveBusy) {
      this.historySavePending = true;
      return;
    }
    this.persistLocalHistory();
  }

  private async persistLocalHistory(): Promise<void> {
    let context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      this.historySavePending = true;
      return;
    }
    let items: ClipboardHistoryItem[] = [];
    for (let index: number = 0; index < this.history.length && index < 200; index++) {
      items.push(this.history[index]);
    }
    this.historySaveBusy = true;
    try {
      await this.historyStorageService.save(context, items);
    } catch (error) {
      console.error('UniClipboard failed to persist local clipboard history.');
    } finally {
      this.historySaveBusy = false;
      if (this.historySavePending) {
        this.historySavePending = false;
        this.scheduleHistorySave();
      }
    }
  }

  private async initializeSpaceNode(): Promise<void> {
    if (this.spaceNodeState === 1 || this.spaceNodeState === 2) {
      return;
    }
    this.spaceNodeState = 1;
    this.spacePeerConnected = false;
    try {
      let context: common.Context | undefined = this.getUIContext().getHostContext();
      if (context === undefined) {
        this.spaceNodeState = 3;
        return;
      }
      let status: NativeSpaceStatus = await this.spaceNodeService.start(
        context.filesDir, context.cacheDir, deviceInfo.deviceType);
      this.spaceNodeState = status.running ? 2 : 3;
      this.spaceJoined = status.joined;
      this.spaceDeviceName = status.deviceName;
      this.spaceCreatedId = status.spaceId;
      if (this.spaceJoined) {
        await this.refreshSpaceDevices();
      }
      await this.initializeMobileSyncServer();
    } catch (error) {
      this.spaceNodeState = 3;
    }
  }

  private async initializeMobileSyncServer(): Promise<void> {
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

  private mobileSyncPortNumber(): number {
    let port: number = parseInt(this.mobileSyncPort.trim(), 10);
    if (isNaN(port) || port < 1 || port > 65535) {
      return 42720;
    }
    return port;
  }

  private async refreshMobileSyncDevices(): Promise<void> {
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

  private async toggleMobileSyncServer(enabled: boolean): Promise<void> {
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
    } finally {
      this.mobileSyncBusy = false;
    }
  }

  private async createMobileSyncDevice(): Promise<void> {
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
    } finally {
      this.mobileSyncBusy = false;
    }
  }

  private async revokeMobileSyncDevice(device: NativeMobileSyncDevice): Promise<void> {
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

  private async revokeSpaceDevice(device: NativeSpaceDevice): Promise<void> {
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
      await this.spaceNodeService.revoke(device.deviceId);
      await this.refreshSpaceDevices();
      this.statusCode = 2;
    } catch (error) {
      this.statusCode = 3;
    } finally {
      this.desktopDeviceMutationBusy = false;
    }
  }

  private async consumeMobileSyncEvents(): Promise<void> {
    let events: NativeMobileSyncInboundEvent[] = this.mobileSyncServerService.drainInboundEvents();
    for (let index: number = 0; index < events.length; index++) {
      let event: NativeMobileSyncInboundEvent = events[index];
      this.latestContentId = event.contentId;
      if (event.kind === 'Text') {
        this.latestText = event.text;
        this.latestKind = 'Text';
        this.latestImage = null;
        this.addHistory(event.text, 'received');
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
          this.addHistory(this.latestText, 'received', 'Image', pixelMap);
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
        this.latestFileName = fileName;
        this.latestFileData = event.data;
        this.latestFilePath = '';
        this.latestFileRevision += 1;
        this.addHistory(fileName, 'received', 'File', null, event.data);
        this.notifyReceivedContent('File', fileName, filePreview, event.data.length,
          event.sourceLabel);
      }
      this.statusCode = 2;
      this.animateLatestContent();
    }
    if (events.length > 0) {
      await this.refreshMobileSyncDevices();
    }
  }

  private async initializeRecommendedSpaceDeviceName(): Promise<void> {
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
          console.error('UniClipboard failed to load the recommended device name.');
        }
      }
    }
    if (recommendedName.length > 0) {
      this.spaceCreateDeviceName = recommendedName;
      this.spaceCreateDeviceNameRecommended = true;
    }
  }

  private canJoinSpace(): boolean {
    if (this.spaceNodeState !== 2 || this.spaceJoinBusy ||
      this.spaceInvitationCode.trim().length === 0 || this.spacePassphrase.length === 0) {
      return false;
    }
    if (this.spaceJoined) {
      return this.spaceSwitchOpen;
    }
    return this.spaceJoinDeviceName.trim().length > 0;
  }

  private async joinCurrentSpace(): Promise<void> {
    if (!this.canJoinSpace()) {
      return;
    }
    this.spaceJoinBusy = true;
    this.spaceJoinState = 0;
    try {
      let switching: boolean = this.spaceJoined;
      let deviceName: string = this.spaceJoinDeviceName.trim();
      let result: NativeJoinSpaceResult;
      if (switching) {
        result = await this.spaceNodeService.switchTo(
          this.spaceInvitationCode.trim(), this.spacePassphrase);
      } else {
        result = await this.spaceNodeService.join(
          this.spaceInvitationCode.trim(), this.spacePassphrase, deviceName);
      }
      this.spaceJoined = result.spaceId.length > 0;
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
      console.error('UniClipboard join space failed: ' + errorMessage);
      this.spaceJoinState = 2;
    } finally {
      this.spaceJoinBusy = false;
    }
  }

  private canCreateSpace(): boolean {
    return this.spaceNodeState === 2 && (!this.spaceJoined || this.spaceSwitchOpen) && !this.spaceCreateBusy &&
      this.spaceCreateDeviceName.trim().length > 0 && this.spaceCreatePassphrase.length >= 8 &&
      this.spaceCreatePassphrase === this.spaceCreatePassphraseConfirm;
  }

  private async confirmReplaceCurrentSpace(): Promise<boolean> {
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

  private async createCurrentSpace(): Promise<void> {
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
      let result: NativeCreateSpaceResult;
      if (replacing) {
        result = await this.spaceNodeService.replace(this.spaceCreatePassphrase, deviceName);
      } else {
        result = await this.spaceNodeService.create(this.spaceCreatePassphrase, deviceName);
      }
      this.spaceJoined = result.spaceId.length > 0;
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

  private async issueCurrentSpaceInvitation(): Promise<void> {
    if (!this.canIssueSpaceInvitation()) {
      return;
    }
    this.spaceInvitationBusy = true;
    try {
      let invitation: NativeSpaceInvitation = await this.spaceNodeService.issueInvitation();
      this.spaceIssuedInvitationCode = invitation.code;
      this.spaceInvitationExpiresAtMs = invitation.expiresAtMs;
      this.spaceCreateState = 1;
    } catch (error) {
      this.spaceCreateState = 3;
    } finally {
      this.spaceInvitationBusy = false;
    }
  }

  private canIssueSpaceInvitation(): boolean {
    return this.spaceNodeState === 2 && this.spaceJoined && !this.spaceInvitationBusy &&
      this.spaceCreatePassphrase.length >= 8;
  }

  private buildSpaceInvitationUri(): string {
    if (this.spaceIssuedInvitationCode.length === 0 || this.spaceCreatePassphrase.length === 0) {
      return '';
    }
    return 'uniclipboard://join-space?v=1&code=' + encodeURIComponent(this.spaceIssuedInvitationCode) +
      '&pwd=' + encodeURIComponent(this.spaceCreatePassphrase);
  }

  private async shareCurrentSpaceInvitation(): Promise<void> {
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
      console.error('UniClipboard failed to share the space invitation.');
      this.showFeedbackToast($r('app.string.space_share_invitation_failed'));
    }
  }

  private isSpaceInvitationCode(value: string): boolean {
    let code: string = value.trim().toUpperCase();
    return code.length === 9 && code.charAt(4) === '-';
  }

  private importSpaceInvitation(value: string): boolean {
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

  private scanSpaceInvitation(): void {
    let options: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.QR_CODE],
      enableMultiMode: false,
      enableAlbum: true
    };
    this.spaceInvitationScanState = 0;
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
  }

  private invitationExpiryText(): string {
    if (this.spaceInvitationExpiresAtMs <= 0) {
      return '';
    }
    let expiry: Date = new Date(this.spaceInvitationExpiresAtMs);
    let hours: string = expiry.getHours().toString().padStart(2, '0');
    let minutes: string = expiry.getMinutes().toString().padStart(2, '0');
    let seconds: string = expiry.getSeconds().toString().padStart(2, '0');
    return hours + ':' + minutes + ':' + seconds;
  }

  @Builder
  private spaceJoinCard() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.connection'))
          .fontSize(24)
          .fontColor([this.accentColor()])
        Column({ space: 3 }) {
          Text(!this.spaceJoined && this.spaceActionMode === 0 ? $r('app.string.space_create_title') :
            $r('app.string.space_join_title'))
            .fontSize($r('app.float.font_subtitle_large'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text(this.spaceJoined ?
            (this.spacePeerConnected ? $r('app.string.space_peer_online') :
              $r('app.string.space_peer_waiting')) :
            (this.spaceActionMode === 0 ? $r('app.string.space_create_note') :
              $r('app.string.space_join_note')))
            .fontSize(12)
            .lineHeight(18)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')

      if (this.spaceNodeState === 1) {
        Text($r('app.string.space_node_starting'))
          .fontSize($r('app.float.font_body_medium'))
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      } else if (this.spaceNodeState === 3) {
        Text($r('app.string.space_node_failed'))
          .fontSize($r('app.float.font_body_medium'))
          .fontColor($r('app.color.danger'))
          .width('100%')
        Button($r('app.string.space_node_retry'), { type: ButtonType.Normal })
          .height(46)
          .width('100%')
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.corner_radius_level10'))
          .onClick((): void => {
            this.initializeSpaceNode();
          })
      } else if (this.spaceJoined) {
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Row()
              .width(8)
              .height(8)
              .borderRadius(4)
              .backgroundColor(this.spacePeerConnected ? $r('app.color.success') :
                $r('app.color.text_secondary'))
            Text(this.spaceDeviceName.length > 0 ? this.spaceDeviceName : $r('app.string.space_joined_device'))
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
          }
          .width('100%')
          Text(this.spacePeerConnected ? $r('app.string.space_peer_online') :
            $r('app.string.space_peer_waiting'))
            .fontSize(12)
            .fontColor(this.spacePeerConnected ? $r('app.color.success') :
              $r('app.color.text_secondary'))
            .width('100%')
          if (this.spaceCreatedId.length > 0) {
            Text($r('app.string.desktop_space_id'))
              .fontSize($r('app.float.font_body_small'))
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
            Text(this.spaceCreatedId)
              .fontSize(12)
              .fontColor($r('app.color.text_primary'))
              .copyOption(CopyOptions.LocalDevice)
              .width('100%')
          }
        }
        .width('100%')
        .padding(14)
        .borderRadius($r('app.float.corner_radius_level10'))
        .backgroundColor($r('app.color.surface_muted'))
        if (this.spaceJoinState === 1 && !this.spaceSwitchOpen) {
          Text($r('app.string.space_switch_success'))
            .fontSize(12)
            .fontColor($r('app.color.success'))
            .width('100%')
        }
        Button(this.mobileInvitationOpen ? $r('app.string.space_mobile_invite_collapse') :
          $r('app.string.space_mobile_invite_open'), { type: ButtonType.Normal })
          .height(46)
          .width('100%')
          .fontColor(this.mobileInvitationOpen ? $r('app.color.text_primary') :
            $r('app.color.on_accent'))
          .backgroundColor(this.mobileInvitationOpen ? $r('app.color.surface_muted') :
            this.accentColor())
          .borderRadius($r('app.float.corner_radius_level10'))
          .enabled(!this.spaceInvitationBusy)
          .onClick((): void => {
            this.mobileInvitationOpen = !this.mobileInvitationOpen;
          })
        if (this.mobileInvitationOpen) {
          Text($r('app.string.space_mobile_invite_note'))
            .fontSize($r('app.float.font_body_small'))
            .lineHeight(18)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          this.spaceInvitationCard()
        }
        Button(this.spaceSwitchOpen ? $r('app.string.space_switch_cancel') :
          $r('app.string.space_switch_open'), { type: ButtonType.Normal })
          .height(46)
          .width('100%')
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.corner_radius_level10'))
          .enabled(!this.spaceJoinBusy)
          .onClick((): void => {
            this.getUIContext().animateTo({
              duration: 380,
              curve: Curve.EaseOut
            }, (): void => {
              this.spaceSwitchOpen = !this.spaceSwitchOpen;
              this.spaceInvitationCode = '';
              this.spacePassphrase = '';
              this.spaceJoinState = 0;
              this.spaceInvitationScanState = 0;
            });
          })
        if (this.spaceSwitchOpen) {
          Column({ space: 10 }) {
            Row({ space: 4 }) {
              this.spaceModeButton(0, $r('app.string.space_create_new_mode'))
              this.spaceModeButton(1, $r('app.string.space_join_other_mode'))
            }
            .width('100%')
            .padding(3)
            .borderRadius($r('app.float.corner_radius_level10'))
            .backgroundColor($r('app.color.surface_muted'))
            if (this.spaceActionMode === 0) {
              this.desktopCreateSpaceForm()
            } else {
              this.desktopJoinSpaceForm()
            }
          }
          .transition({ type: TransitionType.Insert, opacity: 0, translate: { y: 24 } })
          .transition({ type: TransitionType.Delete, opacity: 0, translate: { y: -16 } })
        }
      } else if (this.spaceNodeState === 2) {
        Row({ space: 4 }) {
          this.spaceModeButton(0, $r('app.string.space_create_mode'))
          this.spaceModeButton(1, $r('app.string.space_join_mode'))
        }
        .width('100%')
        .padding(3)
        .borderRadius($r('app.float.corner_radius_level10'))
        .backgroundColor($r('app.color.surface_muted'))
        if (this.spaceActionMode === 0) {
          Text($r('app.string.space_create_note'))
            .fontSize(12)
            .lineHeight(18)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          TextInput({
            placeholder: $r('app.string.space_create_device_placeholder'),
            text: this.spaceCreateDeviceName
          })
            .height(50)
            .fontSize($r('app.float.font_body_large'))
            .fontColor(this.spaceCreateDeviceNameRecommended ? $r('app.color.text_secondary') :
              $r('app.color.text_primary'))
            .backgroundColor($r('app.color.surface_muted'))
            .borderRadius($r('app.float.corner_radius_level10'))
            .onFocus((): void => {
              this.spaceCreateDeviceNameRecommended = false;
            })
            .onChange((value: string): void => {
              this.spaceCreateDeviceName = value;
              this.spaceCreateDeviceNameRecommended = false;
              this.spaceCreateState = 0;
            })
          TextInput({
            placeholder: $r('app.string.space_passphrase_placeholder'),
            text: this.spaceCreatePassphrase
          })
            .type(InputType.Password)
            .height(50)
            .fontSize($r('app.float.font_body_large'))
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.surface_muted'))
            .borderRadius($r('app.float.corner_radius_level10'))
            .onChange((value: string): void => {
              this.spaceCreatePassphrase = value;
              this.spaceCreateState = 0;
            })
          TextInput({
            placeholder: $r('app.string.space_create_confirm_placeholder'),
            text: this.spaceCreatePassphraseConfirm
          })
            .type(InputType.Password)
            .height(50)
            .fontSize($r('app.float.font_body_large'))
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.surface_muted'))
            .borderRadius($r('app.float.corner_radius_level10'))
            .onChange((value: string): void => {
              this.spaceCreatePassphraseConfirm = value;
              this.spaceCreateState = 0;
            })
          Text($r('app.string.space_create_requirement'))
            .fontSize(12)
            .lineHeight(18)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          if (this.spaceCreateState === 2) {
            Text($r('app.string.space_create_failed'))
              .fontSize(12)
              .fontColor($r('app.color.danger'))
              .width('100%')
          }
          Button(this.spaceCreateBusy ? $r('app.string.space_creating_action') :
            $r('app.string.space_create_action'), { type: ButtonType.Normal })
            .height(50)
            .width('100%')
            .fontSize($r('app.float.font_body_large'))
            .fontColor($r('app.color.on_accent'))
            .backgroundColor(this.accentColor())
            .borderRadius($r('app.float.corner_radius_level10'))
            .enabled(this.canCreateSpace())
            .onClick((): void => {
              this.createCurrentSpace();
            })
        } else {
          Button($r('app.string.space_scan_invitation'), { type: ButtonType.Normal })
          .height(46)
          .width('100%')
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.corner_radius_level10'))
          .onClick((): void => {
            this.scanSpaceInvitation();
          })
        if (this.spaceInvitationScanState === 1) {
          Text($r('app.string.space_scan_success'))
            .fontSize(12)
            .fontColor($r('app.color.success'))
            .width('100%')
        } else if (this.spaceInvitationScanState === 2) {
          Text($r('app.string.space_scan_invalid'))
            .fontSize(12)
            .fontColor($r('app.color.danger'))
            .width('100%')
        }
        Text($r('app.string.space_manual_link_note'))
          .fontSize(12)
          .lineHeight(18)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        TextInput({
          placeholder: $r('app.string.space_create_device_placeholder'),
          text: this.spaceJoinDeviceName
        })
          .height(50)
          .fontSize($r('app.float.font_body_large'))
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.corner_radius_level10'))
          .onChange((value: string): void => {
            this.spaceJoinDeviceName = value;
            this.spaceJoinState = 0;
          })
        TextInput({
          placeholder: $r('app.string.space_code_placeholder'),
          text: this.spaceInvitationCode
        })
          .height(50)
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.corner_radius_level10'))
          .onChange((value: string): void => {
            this.spaceInvitationCode = value.toUpperCase();
            this.spaceJoinState = 0;
          })
        TextInput({
          placeholder: $r('app.string.space_passphrase_placeholder'),
          text: this.spacePassphrase
        })
          .type(InputType.Password)
          .height(50)
          .fontSize($r('app.float.font_body_large'))
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.corner_radius_level10'))
          .onChange((value: string): void => {
            this.spacePassphrase = value;
            this.spaceJoinState = 0;
          })
        if (this.spaceJoinState === 1) {
          Text($r('app.string.space_join_success'))
            .fontSize(12)
            .fontColor($r('app.color.success'))
            .width('100%')
        } else if (this.spaceJoinState === 2) {
          Text($r('app.string.space_join_failed'))
            .fontSize(12)
            .fontColor($r('app.color.danger'))
            .width('100%')
        }
          Button(this.spaceJoinBusy ? $r('app.string.space_joining_action') :
            $r('app.string.space_join_action'), { type: ButtonType.Normal })
            .height(50)
            .width('100%')
            .fontSize($r('app.float.font_body_large'))
            .fontColor($r('app.color.on_accent'))
            .backgroundColor(this.accentColor())
            .borderRadius($r('app.float.corner_radius_level10'))
            .enabled(this.canJoinSpace())
            .onClick((): void => {
              this.joinCurrentSpace();
            })
        }
      }
    }
    .width('100%')
    .padding($r('app.float.padding_level8'))
    .borderRadius($r('app.float.corner_radius_level8'))
    .backgroundColor($r('app.color.surface'))
  }

  private selectPage(index: number): void {
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

  private openConnectionSettings(): void {
    this.largeSettingsSection = 1;
    this.selectPage(2);
  }

  private openFeedback(): void {
    this.showFeedbackSheet = true;
  }

  private openFeedbackFromAbout(): void {
    this.showAboutSheet = false;
    setTimeout((): void => {
      this.showFeedbackSheet = true;
    }, 220);
  }

  private showFeedbackToast(message: Resource): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (error) {
      console.error('UniClipboard failed to show feedback status.');
    }
  }

  private async submitFeedback(): Promise<void> {
    let feedback: string = this.feedbackText.trim();
    if (feedback.length === 0) {
      this.showFeedbackToast($r('app.string.feedback_empty_hint'));
      return;
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
      return;
    }

    let subject: string = 'UniClipboard Feedback';
    try {
      subject = await context.resourceManager.getStringByName('feedback_email_subject');
    } catch (error) {
      console.error('UniClipboard failed to load the feedback email subject.');
    }
    let abilityContext: common.UIAbilityContext = context as common.UIAbilityContext;
    let emailUri: string = 'mailto:' + FEEDBACK_EMAIL + '?subject=' + encodeURIComponent(subject) +
      '&body=' + encodeURIComponent(feedback);
    abilityContext.startAbility({
      action: 'ohos.want.action.sendToData',
      uri: emailUri
    }).then((): void => {
      this.showFeedbackSheet = false;
    }).catch((error: BusinessError): void => {
      console.error('UniClipboard failed to open the email app: ' + error.code.toString());
      this.showFeedbackToast($r('app.string.feedback_email_open_failed'));
    });
  }

  private selectLargeSection(index: number): void {
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

  private animateLatestContent(): void {
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

  private animateHistoryUpdate(): void {
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

  private async refreshSpaceDevices(): Promise<void> {
    if (!this.spaceJoined || this.spaceNodeState !== 2 || this.spaceDeviceRefreshBusy) {
      return;
    }
    this.spaceDeviceRefreshBusy = true;
    try {
      let devices: NativeSpaceDevice[] = await this.spaceNodeService.devices();
      this.spaceDevices = devices;
      this.spacePeerConnected = devices.some((device: NativeSpaceDevice): boolean => {
        return !device.isLocal && device.online;
      });
    } catch (error) {
      console.error('UniClipboard refresh space devices failed');
    } finally {
      this.spaceDeviceRefreshBusy = false;
    }
  }

  private async connectSpaceDevice(device: NativeSpaceDevice): Promise<void> {
    if (device.isLocal || this.spaceConnectBusy || this.desktopDeviceMutationBusy ||
      this.spaceNodeState !== 2 || !this.spaceJoined) {
      return;
    }
    this.spaceConnectBusy = true;
    this.spaceConnectingDeviceId = device.deviceId;
    this.spaceConnectState = 1;
    try {
      let online: boolean = await this.spaceNodeService.connect(device.deviceId);
      await this.refreshSpaceDevices();
      this.spaceConnectState = online ? 2 : 3;
      if (online) {
        this.spacePeerConnected = true;
        this.statusCode = 2;
      }
    } catch (error) {
      this.spaceConnectState = 3;
      this.statusCode = 3;
    } finally {
      this.spaceConnectingDeviceId = '';
      this.spaceConnectBusy = false;
    }
  }

  private async connectAllSpaceDevices(): Promise<void> {
    if (this.spaceConnectBusy || this.desktopDeviceMutationBusy ||
      this.spaceNodeState !== 2 || !this.spaceJoined) {
      return;
    }
    this.spaceConnectBusy = true;
    this.spaceConnectingDeviceId = '*';
    this.spaceConnectState = 1;
    let anyOnline: boolean = false;
    try {
      await this.refreshSpaceDevices();
      for (let index: number = 0; index < this.spaceDevices.length; index++) {
        let device: NativeSpaceDevice = this.spaceDevices[index];
        if (!device.isLocal) {
          let online: boolean = await this.spaceNodeService.connect(device.deviceId);
          if (online) {
            anyOnline = true;
          }
        }
      }
      await this.refreshSpaceDevices();
      this.spacePeerConnected = anyOnline || this.spacePeerConnected;
      this.spaceConnectState = this.spacePeerConnected ? 2 : 3;
      this.statusCode = this.spacePeerConnected ? 2 : 3;
    } catch (error) {
      this.spaceConnectState = 3;
      this.statusCode = 3;
    } finally {
      this.spaceConnectingDeviceId = '';
      this.spaceConnectBusy = false;
    }
  }

  private async refreshDesktopMessages(): Promise<void> {
    if (this.desktopRefreshBusy) {
      return;
    }
    this.desktopRefreshBusy = true;
    try {
      if (this.spaceJoined) {
        this.spaceNodeService.wakeConnections();
        await this.connectAllSpaceDevices();
        await this.consumeSpaceTextEvents();
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

  private desktopAllFiltersClear(): boolean {
    return !this.desktopStarredOnly && this.desktopTypeFilter === 0 && this.desktopTagFilter === 0 &&
      this.desktopSourceFilter === 0 && this.desktopTimeFilter === 0 && this.desktopExtensionFilter.length === 0;
  }

  private desktopSearchMatches(text: string): boolean {
    let query: string = this.historySearchText.trim().toLowerCase();
    return query.length === 0 || text.toLowerCase().indexOf(query) >= 0;
  }

  private scheduleDesktopHistorySearch(value: string): void {
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

  private submitDesktopHistorySearch(): void {
    if (this.historySearchTimerId >= 0) {
      clearTimeout(this.historySearchTimerId);
      this.historySearchTimerId = -1;
    }
    if (this.hasConfig()) {
      this.loadServerHistory(true);
    }
  }

  private desktopFilterSelected(group: number, value: number): boolean {
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
    return this.desktopTimeFilter === value;
  }

  private applyDesktopFilter(group: number, value: number): void {
    let previousStarredOnly: boolean = this.desktopStarredOnly;
    if (group === 0 && value === 0) {
      this.desktopStarredOnly = false;
      this.desktopTypeFilter = 0;
      this.desktopTagFilter = 0;
      this.desktopSourceFilter = 0;
      this.desktopTimeFilter = 0;
      this.desktopExtensionFilter = '';
    } else if (group === 0) {
      this.desktopStarredOnly = !this.desktopStarredOnly;
    } else if (group === 1) {
      this.desktopTypeFilter = this.desktopTypeFilter === value ? 0 : value;
    } else if (group === 2) {
      this.desktopTagFilter = this.desktopTagFilter === value ? 0 : value;
    } else if (group === 3) {
      this.desktopSourceFilter = value;
    } else {
      this.desktopTimeFilter = value;
    }
    let shouldReload: boolean = previousStarredOnly !== this.desktopStarredOnly;
    this.historyStarredOnly = this.desktopStarredOnly;
    if (shouldReload && this.hasConfig()) {
      this.loadServerHistory(true);
    }
  }

  private applyDesktopExtensionFilter(extension: string): void {
    this.desktopExtensionFilter = this.desktopExtensionFilter === extension ? '' : extension;
  }

  private desktopTextLooksRich(text: string): boolean {
    let lowerText: string = text.toLowerCase();
    return lowerText.indexOf('<p') >= 0 || lowerText.indexOf('<div') >= 0 ||
      lowerText.indexOf('<span') >= 0 || lowerText.indexOf('<strong') >= 0 ||
      lowerText.indexOf('<html') >= 0;
  }

  private desktopLinkHostIsValid(host: string): boolean {
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

  private desktopTextLooksLikeLink(text: string): boolean {
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

  private desktopTextLooksLikeCode(text: string): boolean {
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

  private desktopContentExtension(text: string): string {
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

  private desktopExtensionIsImage(extension: string): boolean {
    return extension === 'jpg' || extension === 'jpeg' || extension === 'png' || extension === 'gif' ||
      extension === 'webp' || extension === 'bmp' || extension === 'svg' || extension === 'heic';
  }

  private desktopExtensionIsCode(extension: string): boolean {
    return extension === 'ts' || extension === 'ets' || extension === 'js' || extension === 'json' ||
      extension === 'rs' || extension === 'go' || extension === 'py' || extension === 'java' ||
      extension === 'c' || extension === 'h' || extension === 'cpp' || extension === 'css' ||
      extension === 'html' || extension === 'xml';
  }

  private desktopTypeMatchesFilter(kind: string, text: string): boolean {
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

  private desktopTagMatchesFilter(kind: string, text: string): boolean {
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

  private desktopSourceMatchesFilter(serverItem: boolean): boolean {
    if (this.desktopSourceFilter === 1) {
      return serverItem;
    }
    if (this.desktopSourceFilter === 2) {
      return !serverItem;
    }
    return true;
  }

  private desktopExtensionMatchesFilter(text: string): boolean {
    if (this.desktopExtensionFilter.length === 0) {
      return true;
    }
    return this.desktopContentExtension(text) === this.desktopExtensionFilter;
  }

  private desktopTimeMatchesFilter(timestampMs: number): boolean {
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

  private desktopFilteredServerHistory(): ServerHistoryItem[] {
    let items: ServerHistoryItem[] = [];
    for (let index: number = 0; index < this.serverHistory.length; index++) {
      let item: ServerHistoryItem = this.serverHistory[index];
      let starredMatches: boolean = !this.desktopStarredOnly || item.starred;
      if (starredMatches && this.desktopSearchMatches(item.text) && this.desktopSourceMatchesFilter(true) &&
        this.desktopTypeMatchesFilter(item.kind, item.text) && this.desktopTagMatchesFilter(item.kind, item.text) &&
        this.desktopTimeMatchesFilter(item.timestampMs) && this.desktopExtensionMatchesFilter(item.text)) {
        items.push(item);
      }
    }
    return items;
  }

  private desktopFilteredSessionHistory(): ClipboardHistoryItem[] {
    let items: ClipboardHistoryItem[] = [];
    for (let index: number = 0; index < this.history.length; index++) {
      let item: ClipboardHistoryItem = this.history[index];
      let starredMatches: boolean = !this.desktopStarredOnly || item.starred;
      if (starredMatches && this.desktopSearchMatches(item.text) && this.desktopSourceMatchesFilter(false) &&
        this.desktopTypeMatchesFilter(item.kind, item.text) && this.desktopTagMatchesFilter(item.kind, item.text) &&
        this.desktopTimeMatchesFilter(item.timestampMs) && this.desktopExtensionMatchesFilter(item.text)) {
        items.push(item);
      }
    }
    return items;
  }

  private async selectDesktopServerItem(item: ServerHistoryItem): Promise<void> {
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

  private selectDesktopSessionItem(item: ClipboardHistoryItem): void {
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
  }

  private desktopDetailText(): string {
    if (this.desktopSelectedText.length > 0) {
      return this.desktopSelectedText;
    }
    return this.latestText;
  }

  private desktopShowsLatestImage(): boolean {
    return this.desktopDisplayImage() !== null;
  }

  private desktopDisplayImage(): image.PixelMap | null {
    if (this.desktopSelectedId.length > 0) {
      return this.desktopSelectedImage;
    }
    return this.latestKind === 'Image' ? this.latestImage : null;
  }

  private desktopShowsFile(): boolean {
    if (this.desktopSelectedId.length > 0) {
      return this.desktopSelectedFileData !== null || this.desktopSelectedFilePath.length > 0;
    }
    return this.latestKind === 'File' &&
      (this.latestFileData !== null || this.latestFilePath.length > 0);
  }

  private desktopFileName(): string {
    if (this.desktopSelectedId.length > 0) {
      return this.desktopSelectedText;
    }
    return this.latestFileName.length > 0 ? this.latestFileName : this.latestText;
  }

  private desktopFileSourcePath(): string {
    if (this.desktopSelectedId.length > 0) {
      return this.desktopSelectedFilePath;
    }
    return this.latestFilePath;
  }

  private desktopFilePreviewUri(): string {
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

  private async registerDesktopGestureShare(): Promise<void> {
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
      console.error('UniClipboard failed to register gesturesShare.');
      this.desktopGestureShareState = 4;
    } finally {
      this.desktopGestureShareRegistering = false;
    }
  }

  private unregisterDesktopGestureShare(): void {
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
      console.error('UniClipboard failed to unregister gesturesShare.');
    }
  }

  private resetDesktopGestureShareStateLater(): void {
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

  private desktopHasGestureShareContent(): boolean {
    return this.desktopShowsFile() || this.desktopShowsLatestImage() || this.desktopDetailText().trim().length > 0;
  }

  private desktopGestureShareContentKind(): number {
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

  private desktopGestureShareFileUtd(): string {
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

  private desktopGestureShareFileContentKind(): number {
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

  private async createDesktopGestureImageUri(): Promise<string> {
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
      console.error('UniClipboard failed to prepare the gesture share image.');
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

  private async createDesktopGestureShareRecord(): Promise<systemShare.SharedRecord | null> {
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

  private async shareDesktopContentByGesture(target: harmonyShare.SharableTarget): Promise<void> {
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
      console.error('UniClipboard gesturesShare failed.');
      this.desktopGestureShareState = 4;
    }
    this.resetDesktopGestureShareStateLater();
  }

  private desktopFileExtension(): string {
    let fileName: string = this.desktopFileName();
    let dotIndex: number = fileName.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex >= fileName.length - 1) {
      return '';
    }
    return fileName.substring(dotIndex + 1).toLowerCase();
  }

  private desktopFileMimeType(): string {
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

  private desktopFileIsVideo(): boolean {
    let extension: string = this.desktopFileExtension();
    return extension === 'mp4' || extension === 'mkv' || extension === 'ts' ||
      extension === 'avi' || extension === 'mov' || extension === 'webm' ||
      extension === 'm4v' || extension === '3gp' || extension === 'mpeg' ||
      extension === 'mpg' || extension === 'ogv' || extension === 'flv';
  }

  private desktopFileIsAudio(): boolean {
    let extension: string = this.desktopFileExtension();
    return extension === 'm4a' || extension === 'aac' || extension === 'mp3' ||
      extension === 'ogg' || extension === 'wav' || extension === 'flac' ||
      extension === 'opus' || extension === 'ape' || extension === 'amr' ||
      extension === 'midi' || extension === 'mid';
  }

  private async releaseDesktopAudio(): Promise<void> {
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
        console.error('UniClipboard failed to release the audio player.');
      }
    }
    if (sourceFile !== null) {
      try {
        fileIo.closeSync(sourceFile.fd);
      } catch (error) {
        console.error('UniClipboard failed to close the audio preview file.');
      }
    }
  }

  private async prepareDesktopAudioPlayer(player: media.AVPlayer, previewKey: string): Promise<void> {
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

  private async prepareDesktopAudio(): Promise<void> {
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
      let player: media.AVPlayer = await media.createAVPlayer();
      if (this.desktopAudioKey !== previewKey) {
        await player.release();
        return;
      }
      this.desktopAudioPlayer = player;
      player.on('stateChange', (state: media.AVPlayerState, _reason: media.StateChangeReason): void => {
        if (this.desktopAudioPlayer !== player || this.desktopAudioKey !== previewKey) {
          return;
        }
        if (state === 'initialized') {
          this.prepareDesktopAudioPlayer(player, previewKey);
        } else if (state === 'prepared') {
          this.desktopAudioDuration = player.duration > 0 ? player.duration : 0;
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
      player.on('timeUpdate', (position: number): void => {
        if (this.desktopAudioPlayer === player && this.desktopAudioKey === previewKey &&
          !this.desktopAudioSeeking) {
          this.desktopAudioPosition = position;
        }
      });
      player.on('durationUpdate', (duration: number): void => {
        if (this.desktopAudioPlayer === player && this.desktopAudioKey === previewKey) {
          this.desktopAudioDuration = duration > 0 ? duration : 0;
        }
      });
      player.on('error', (_error: BusinessError): void => {
        if (this.desktopAudioPlayer === player && this.desktopAudioKey === previewKey) {
          this.desktopAudioState = 5;
        }
      });
      player.fdSrc = sourceDescriptor;
    } catch (error) {
      await this.releaseDesktopAudio();
      this.desktopAudioState = 5;
    }
  }

  private async playDesktopAudio(): Promise<void> {
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

  private async toggleDesktopAudioPlayback(): Promise<void> {
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

  private seekDesktopAudio(position: number): void {
    let player: media.AVPlayer | null = this.desktopAudioPlayer;
    if (player === null || this.desktopAudioDuration <= 0) {
      return;
    }
    if (player.state === 'prepared' || player.state === 'playing' || player.state === 'paused' ||
      player.state === 'completed') {
      player.seek(Math.floor(position));
    }
  }

  private formatAudioTime(timeMs: number): string {
    let safeTime: number = Math.max(0, timeMs);
    let totalSeconds: number = Math.floor(safeTime / 1000);
    let minutes: number = Math.floor(totalSeconds / 60);
    let seconds: number = totalSeconds % 60;
    return minutes.toString() + ':' + (seconds < 10 ? '0' : '') + seconds.toString();
  }

  private resetDesktopAudioMetadata(): void {
    this.desktopAudioCover = null;
    this.desktopAudioCoverRevision++;
    this.desktopAudioTitle = '';
    this.desktopAudioArtist = '';
    this.desktopAudioAlbum = '';
    this.desktopAudioLyrics = [];
    this.desktopAudioPlainLyrics = '';
    this.desktopAudioMetadataState = 0;
  }

  private desktopAudioDisplayTitle(): string {
    return this.desktopAudioTitle.length > 0 ? this.desktopAudioTitle : this.desktopFileName();
  }

  private desktopAudioDisplayArtist(): string {
    if (this.desktopAudioArtist.length > 0 && this.desktopAudioAlbum.length > 0) {
      return this.desktopAudioArtist + ' · ' + this.desktopAudioAlbum;
    }
    return this.desktopAudioArtist.length > 0 ? this.desktopAudioArtist : this.desktopAudioAlbum;
  }

  private embeddedLyricsFromMetadata(metadata: media.AVMetadata): string {
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

  private loadDesktopSidecarLyrics(sourcePath: string): string {
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
        console.error('UniClipboard failed to read the sidecar lyric file.');
      }
    }
    return '';
  }

  private parseDesktopLyricTime(tag: string): number {
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

  private parseDesktopLyrics(lyricText: string): void {
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

  private desktopCurrentLyricIndex(): number {
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

  private desktopLyricTextAtOffset(offset: number): string {
    let index: number = this.desktopCurrentLyricIndex() + offset;
    if (index < 0 || index >= this.desktopAudioLyrics.length) {
      return '';
    }
    return this.desktopAudioLyrics[index].text;
  }

  private async loadDesktopAudioMetadata(sourcePath: string, previewKey: string): Promise<void> {
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
      extractor = await media.createAVMetadataExtractor();
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
        console.error('UniClipboard failed to read the audio metadata.');
      }
      try {
        let cover: image.PixelMap = await extractor.fetchAlbumCover();
        if (this.desktopAudioKey === previewKey) {
          this.desktopAudioCover = cover;
          this.desktopAudioCoverRevision++;
        }
      } catch (error) {
        console.info('UniClipboard audio file has no embedded cover.');
      }
    } catch (error) {
      console.error('UniClipboard failed to open the audio metadata source.');
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

  private desktopFileIsDocument(): boolean {
    let extension: string = this.desktopFileExtension();
    return extension === 'csv' || extension === 'ofd' ||
      extension === 'txt' || extension === 'rtf' || extension === 'md' ||
      extension === 'html' || extension === 'htm' || extension === 'xml';
  }

  private desktopFilePreviewKey(): string {
    if (this.desktopSelectedId.length > 0) {
      return this.desktopSelectedId;
    }
    return this.latestFileRevision.toString();
  }

  private desktopImageAspectRatio(): number {
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
      console.error('UniClipboard failed to read the image preview size.');
    }
    return 1;
  }

  private latestImageAspectRatio(): number {
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
      console.error('UniClipboard failed to read the latest image preview size.');
    }
    return 1;
  }

  private resetDesktopVideoAspectRatio(): void {
    this.desktopVideoAspectRatio = 16 / 9;
    this.desktopVideoRatioKey = '';
  }

  private async loadDesktopVideoAspectRatio(): Promise<void> {
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
      extractor = await media.createAVMetadataExtractor();
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
      console.error('UniClipboard failed to read the video preview size.');
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

  private async openDesktopFilePreview(): Promise<void> {
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
      console.error('UniClipboard failed to open the file preview.');
      this.desktopFilePreviewState = 2;
    }
  }

  private async copyDesktopSelection(): Promise<void> {
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

  private async copyServerHistoryItem(item: ServerHistoryItem): Promise<void> {
    await this.selectDesktopServerItem(item);
    await this.copyDesktopSelection();
  }

  private async copyLocalHistoryItem(item: ClipboardHistoryItem): Promise<void> {
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

  private toggleLocalHistoryStarred(item: ClipboardHistoryItem): void {
    let items: ClipboardHistoryItem[] = [];
    for (let index: number = 0; index < this.history.length; index++) {
      let current: ClipboardHistoryItem = this.history[index];
      if (current.id === item.id) {
        current.starred = !current.starred;
      }
      items.push(current);
    }
    this.history = items;
    this.animateHistoryUpdate();
    this.scheduleHistorySave();
  }

  private async sendLocalHistoryItem(item: ClipboardHistoryItem): Promise<void> {
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

  private async sendServerHistoryItem(item: ServerHistoryItem): Promise<void> {
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

  private async sendServerHistoryItemToTarget(item: ServerHistoryItem, target: string): Promise<void> {
    console.info('UniClipboard history send target: ' + target);
    await this.sendServerHistoryItem(item);
  }

  private async sendLocalHistoryItemToTarget(item: ClipboardHistoryItem, target: string): Promise<void> {
    console.info('UniClipboard history send target: ' + target);
    await this.sendLocalHistoryItem(item);
  }

  private toggleDesktopSelectedStar(): void {
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

  private desktopSelectionStarred(): boolean {
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

  private deleteDesktopSelection(): void {
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

  private async confirmDeleteLocalHistory(item: ClipboardHistoryItem): Promise<void> {
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
      let context: common.Context | undefined = this.getUIContext().getHostContext();
      if (context !== undefined) {
        this.historyStorageService.removePayload(context, item);
      }
      this.scheduleHistorySave();
    } finally {
      this.historyMutationBusy = false;
    }
  }

  private hasConfig(): boolean {
    return this.serverUrl.trim().length > 0 &&
      this.username.trim().length > 0 &&
      this.password.length > 0;
  }

  private currentTime(): string {
    let now: Date = new Date();
    let hours: string = now.getHours().toString().padStart(2, '0');
    let minutes: string = now.getMinutes().toString().padStart(2, '0');
    return hours + ':' + minutes;
  }

  private addHistory(text: string, direction: string, kind: string = 'Text',
    imagePreview: image.PixelMap | null = null, fileData: Uint8Array | null = null,
    filePath: string = '', historyId: string = ''): void {
    let timestampMs: number = Date.now();
    let itemId: string = historyId.length > 0 ? historyId : timestampMs.toString();
    let item: ClipboardHistoryItem = new ClipboardHistoryItem(
      itemId, text, direction, this.currentTime(), kind, imagePreview, fileData, filePath, timestampMs);
    let items: ClipboardHistoryItem[] = [item];
    for (let index: number = 0; index < this.history.length && items.length < 200; index++) {
      items.push(this.history[index]);
    }
    this.history = items;
    this.animateHistoryUpdate();
    this.scheduleHistorySave();
  }

  private connectionChanged(): void {
    this.realtimeAutoConnect = false;
    if (this.realtimeActive) {
      this.stopRealtime();
    }
    this.statusCode = 0;
  }

  private isConnectionAvailable(): boolean {
    if (this.spaceJoined && !this.hasConfig()) {
      return this.spacePeerConnected;
    }
    return this.spacePeerConnected || this.statusCode === 2 || this.realtimeActive;
  }

  private async testConnection(): Promise<void> {
    if (!this.hasConfig()) {
      this.statusCode = 3;
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
    } finally {
      this.busy = false;
    }
  }

  private importConnectUri(): void {
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

  private scanConnectUri(): void {
    let options: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.QR_CODE],
      enableMultiMode: false,
      enableAlbum: true
    };
    this.connectUriState = 0;
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
  }

  private async pullLatest(): Promise<void> {
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
      this.statusCode = 2;
    } catch (error) {
      this.statusCode = 3;
    } finally {
      this.busy = false;
    }
  }

  private async applyLatestContent(result: SyncContent, recordHistory: boolean): Promise<void> {
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
      this.addHistory(displayText, 'received', result.kind, pixelMap, fileData, filePath);
    }
  }

  private cacheLatestFile(data: Uint8Array): string {
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

  private removeLatestCachedFile(): void {
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

  private contentDisplayText(result: SyncContent): string {
    if (result.dataName.length > 0 && (result.kind === 'Image' || result.text.length === 0)) {
      return result.dataName;
    }
    if (result.kind === 'Image' && result.text.length === 0) {
      return 'image.png';
    }
    return result.text;
  }

  private latestCopyable(): boolean {
    return (this.latestKind === 'Text' && this.latestText.length > 0) ||
      (this.latestKind === 'Image' && this.latestImage !== null) ||
      (this.latestKind === 'File' &&
        (this.latestFileData !== null || this.latestFilePath.length > 0));
  }

  private async copyLatest(): Promise<void> {
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

  private async readLocalClipboard(): Promise<void> {
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

  private async readLocalImage(): Promise<void> {
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

  private async sendText(): Promise<void> {
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
      if (this.hasConfig()) {
        try {
          let client: MobileSyncClient = new MobileSyncClient(this.getConfig());
          this.latestContentId = await client.putText(text);
          delivered = true;
          console.info('UniClipboard text sent through desktop relay');
        } catch (error) {
          console.warn('UniClipboard desktop relay unavailable, trying P2P');
        }
      }
      if (!delivered && this.spaceJoined) {
        try {
          let acceptedCount: number = await this.spaceNodeService.sendText(text);
          console.info('UniClipboard P2P accepted peer count: ' + acceptedCount.toString());
          if (acceptedCount > 0) {
            this.spacePeerConnected = true;
            this.latestContentId = '';
            delivered = true;
          } else if (!mobilePublished) {
            throw new Error('no online space peer accepted the clipboard');
          }
        } catch (error) {
          if (!mobilePublished) {
            throw new Error('space text delivery failed');
          }
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

  private async sendImage(): Promise<void> {
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
          console.info('UniClipboard image sent through desktop relay');
        } catch (error) {
          console.warn('UniClipboard desktop image relay unavailable, trying P2P');
        }
      }
      if (!delivered && this.spaceJoined) {
        try {
          let data: Uint8Array = await this.clipboardService.encodeSpaceImage(pixelMap);
          let acceptedCount: number = await this.spaceNodeService.sendImage(data);
          console.info('UniClipboard P2P image accepted peer count: ' + acceptedCount.toString());
          if (acceptedCount > 0) {
            this.spacePeerConnected = true;
            this.latestContentId = '';
            this.latestText = 'image.jpg';
            delivered = true;
          } else if (!mobilePublished) {
            throw new Error('no online space peer accepted the clipboard image');
          }
        } catch (error) {
          if (!mobilePublished) {
            throw new Error('space image delivery failed');
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
    } finally {
      this.busy = false;
    }
  }

  private resetComposerFile(removeStagedFile: boolean): void {
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

  private async selectFile(): Promise<void> {
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

  private async sendFile(): Promise<void> {
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
      if (this.hasConfig()) {
        try {
          let client: MobileSyncClient = new MobileSyncClient(this.getConfig());
          this.latestContentId = await client.putFileFromUri(
            sourceUri, sourceSize, this.composerFileName);
          this.pendingFileTransferId = '';
          delivered = true;
          console.info('UniClipboard file sent through desktop relay');
        } catch (error) {
          console.warn('UniClipboard desktop file relay unavailable, trying P2P');
        }
      }
      if (!delivered && this.spaceJoined) {
        try {
          let sendResult: NativeSpaceFileSendResult = await this.spaceNodeService.sendFileFromUri(
            sourceUri, sourceSize, this.composerFileName);
          if (sendResult.acceptedCount > 0) {
            this.pendingFileTransferId = sendResult.transferId;
            this.latestContentId = '';
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

  private async saveSelectedFile(): Promise<void> {
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
          if (sourcePath.startsWith('/')) {
            await this.spaceNodeService.copyFileToUri(sourcePath, uris[0]);
          } else {
            await this.spaceNodeService.copyUriToUri(sourcePath, uris[0]);
          }
        } else if (data !== null) {
          this.clipboardService.writeFile(uris[0], data);
        }
        this.statusCode = 2;
      }
    } catch (error) {
      this.statusCode = 3;
    }
  }

  private startRealtime(): void {
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
    }
  }

  private stopRealtime(): void {
    let client: MobileSyncClient = new MobileSyncClient(this.getConfig());
    client.stopRealtime();
    this.realtimeAutoConnect = false;
    this.realtimeActive = false;
    this.statusCode = 0;
  }

  private toggleRealtime(): void {
    if (this.realtimeActive) {
      this.stopRealtime();
    } else {
      this.startRealtime();
    }
  }

  private async consumeRealtimeEvents(): Promise<void> {
    await this.consumeMobileSyncEvents();
    await this.consumeSpaceTextEvents();
    this.realtimeTick += 1;
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
      return;
    }
    this.sseEventBusy = true;
    try {
      let client: MobileSyncClient = new MobileSyncClient(this.getConfig());
      let events: SyncEvent[] = client.drainRealtimeEvents();
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
        return;
      }
      if (shouldPull) {
        await this.pullLatestFromRealtime(client);
      }
    } catch (error) {
      this.realtimeActive = false;
      this.statusCode = 3;
    } finally {
      this.sseEventBusy = false;
    }
  }

  private async consumeSpaceTextEvents(): Promise<void> {
    if (!this.spaceJoined) {
      return;
    }
    if (this.spaceDevices.length === 0) {
      await this.refreshSpaceDevices();
    }
    let events: NativeSpaceTextEvent[] = this.spaceNodeService.drainTextEvents();
    for (let index: number = 0; index < events.length; index++) {
      let event: NativeSpaceTextEvent = events[index];
      this.latestText = event.text;
      this.latestKind = 'Text';
      this.latestImage = null;
      if (this.desktopSelectedId.length === 0) {
        this.releaseDesktopAudio();
      }
      this.latestContentId = event.snapshotHash;
      this.addHistory(event.text, 'received');
      try {
        await this.clipboardService.writeText(event.text);
        this.notifyReceivedContent('Text', event.text, null, 0,
          this.sourceLabelForDevice(event.fromDeviceId));
      } catch (error) {
        this.statusCode = 3;
      }
    }
    if (events.length > 0 && this.statusCode !== 3) {
      this.spacePeerConnected = true;
      this.statusCode = 2;
    }
    let imageEvents: NativeSpaceImageEvent[] = this.spaceNodeService.drainImageEvents();
    for (let index: number = 0; index < imageEvents.length; index++) {
      let event: NativeSpaceImageEvent = imageEvents[index];
      try {
        let pixelMap: image.PixelMap = await this.clipboardService.decodeImage(event.data);
        this.latestImage = pixelMap;
        this.latestImageRevision += 1;
        this.latestKind = 'Image';
        this.latestText = 'image.jpg';
        if (this.desktopSelectedId.length === 0) {
          this.releaseDesktopAudio();
        }
        this.latestContentId = event.snapshotHash;
        this.addHistory('image.jpg', 'received', 'Image', pixelMap);
        await this.clipboardService.writeImage(pixelMap);
        this.notifyReceivedContent('Image', 'image.jpg', pixelMap, 0,
          this.sourceLabelForDevice(event.fromDeviceId));
      } catch (error) {
        this.statusCode = 3;
      }
    }
    if (imageEvents.length > 0 && this.statusCode !== 3) {
      this.spacePeerConnected = true;
      this.statusCode = 2;
    }
    let fileEvents: NativeSpaceFileEvent[] = this.spaceNodeService.drainFileEvents();
    for (let index: number = 0; index < fileEvents.length; index++) {
      let event: NativeSpaceFileEvent = fileEvents[index];
      let filePreview: image.PixelMap | null = null;
      if (this.isImageFileName(event.fileName) && event.data.length > 0) {
        try {
          filePreview = await this.clipboardService.decodeImage(event.data);
        } catch (error) {
          filePreview = null;
        }
      }
      this.latestKind = 'File';
      this.latestText = event.fileName;
      this.latestFileName = event.fileName;
      this.latestFileData = event.data;
      this.latestFilePath = event.localPath;
      this.latestFileRevision += 1;
      this.desktopFilePreviewState = 0;
      this.resetDesktopVideoAspectRatio();
      if (this.desktopSelectedId.length === 0) {
        this.releaseDesktopAudio();
      }
      this.latestImage = null;
      this.latestContentId = event.snapshotHash;
      this.addHistory(event.fileName, 'received', 'File', null,
        event.data.length > 0 ? event.data : null, event.localPath);
      this.notifyReceivedContent('File', event.fileName, filePreview, event.data.length,
        this.sourceLabelForDevice(event.fromDeviceId));
    }
    if (fileEvents.length > 0) {
      this.spacePeerConnected = true;
      this.statusCode = 2;
    }
    let fileStatusEvents: NativeSpaceFileStatusEvent[] = this.spaceNodeService.drainFileStatusEvents();
    for (let index: number = 0; index < fileStatusEvents.length; index++) {
      let event: NativeSpaceFileStatusEvent = fileStatusEvents[index];
      if (event.transferId !== this.pendingFileTransferId) {
        continue;
      }
      if (event.status === 'completed') {
        this.fileTransferState = 6;
        this.pendingFileTransferId = '';
        this.statusCode = 2;
      } else if (event.status === 'failed' || event.status === 'cancelled') {
        this.fileTransferState = 4;
        this.pendingFileTransferId = '';
        this.statusCode = 3;
      }
    }
    if (events.length > 0 || imageEvents.length > 0 || fileEvents.length > 0) {
      this.animateLatestContent();
    }
  }

  private async pullLatestFromRealtime(client: MobileSyncClient): Promise<void> {
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

  private notifyReceivedContent(kind: string, displayName: string, preview: image.PixelMap | null = null,
    fileSize: number = 0, sourceLabel: string = ''): void {
    let context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    this.receivedNotificationService.notifyReceived(context as common.UIAbilityContext, kind, displayName,
      preview, fileSize, sourceLabel);
  }

  private sourceLabelForDevice(deviceId: string): string {
    if (deviceId.length === 0) {
      return '';
    }
    for (let index: number = 0; index < this.spaceDevices.length; index++) {
      let device: NativeSpaceDevice = this.spaceDevices[index];
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

  private sourceDeviceTypeLabel(deviceType: string): string {
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

  private isImageFileName(name: string): boolean {
    let dot: number = name.lastIndexOf('.');
    if (dot < 0 || dot === name.length - 1) {
      return false;
    }
    let extension: string = name.substring(dot + 1).toLowerCase();
    return extension === 'jpg' || extension === 'jpeg' || extension === 'png' || extension === 'gif' ||
      extension === 'webp' || extension === 'bmp';
  }

  private async loadServerHistory(reset: boolean): Promise<void> {
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

  private replaceServerHistoryItem(updated: ServerHistoryItem): void {
    let items: ServerHistoryItem[] = [];
    for (let index: number = 0; index < this.serverHistory.length; index++) {
      let item: ServerHistoryItem = this.serverHistory[index];
      items.push(item.id === updated.id ? updated : item);
    }
    this.serverHistory = items;
  }

  private async toggleHistoryStarred(item: ServerHistoryItem): Promise<void> {
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

  private async toggleHistoryPinned(item: ServerHistoryItem): Promise<void> {
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

  private async confirmDeleteHistory(item: ServerHistoryItem): Promise<void> {
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

  @Builder
  private historyServerSendToMenu(item: ServerHistoryItem) {
    Menu() {
      MenuItem({
        symbolStartIcon: this.historyMenuSymbol($r('sys.symbol.link')),
        content: $r('app.string.history_send_to_all_action')
      }).onClick((): void => {
          this.sendServerHistoryItemToTarget(item, 'all');
      })
      ForEach(this.spaceDevices, (device: NativeSpaceDevice) => {
        MenuItem({
          content: device.deviceName
        }).enabled(device.online).onClick((): void => {
            this.sendServerHistoryItemToTarget(item, device.deviceName);
        })
      }, (device: NativeSpaceDevice): string => 'space-' + device.deviceId)
      ForEach(this.mobileSyncDevices, (device: NativeMobileSyncDevice) => {
        MenuItem({
          content: device.label
        }).enabled(device.online).onClick((): void => {
            this.sendServerHistoryItemToTarget(item, device.label);
        })
      }, (device: NativeMobileSyncDevice): string => 'mobile-' + device.deviceId)
    }.menuItemDivider({
      strokeWidth: LengthMetrics.vp(1),
      color: $r('app.color.divider'),
      startMargin: LengthMetrics.vp(12),
      endMargin: LengthMetrics.vp(12)
    })
  }

  @Builder
  private historyLocalSendToMenu(item: ClipboardHistoryItem) {
    Menu() {
      MenuItem({
        symbolStartIcon: this.historyMenuSymbol($r('sys.symbol.link')),
        content: $r('app.string.history_send_to_all_action')
      }).onClick((): void => {
          this.sendLocalHistoryItemToTarget(item, 'all');
      })
      ForEach(this.spaceDevices, (device: NativeSpaceDevice) => {
        MenuItem({
          content: device.deviceName
        }).enabled(device.online).onClick((): void => {
            this.sendLocalHistoryItemToTarget(item, device.deviceName);
        })
      }, (device: NativeSpaceDevice): string => 'space-' + device.deviceId)
      ForEach(this.mobileSyncDevices, (device: NativeMobileSyncDevice) => {
        MenuItem({
          content: device.label
        }).enabled(device.online).onClick((): void => {
            this.sendLocalHistoryItemToTarget(item, device.label);
        })
      }, (device: NativeMobileSyncDevice): string => 'mobile-' + device.deviceId)
    }.menuItemDivider({
      strokeWidth: LengthMetrics.vp(1),
      color: $r('app.color.divider'),
      startMargin: LengthMetrics.vp(12),
      endMargin: LengthMetrics.vp(12)
    })
  }

  @Builder
  private historyServerContextMenu(item: ServerHistoryItem) {
    Menu() {
      MenuItem({
        symbolStartIcon: this.historyMenuSymbol($r('sys.symbol.clipboard_sharing')),
        content: $r('app.string.copy_action')
      }).onClick((): void => {
          this.copyServerHistoryItem(item);
      })
      MenuItem({
        symbolStartIcon: this.historyMenuSymbol($r('sys.symbol.star')),
        content: item.starred ? $r('app.string.history_unstar_action') : $r('app.string.history_star_action')
      }).onClick((): void => {
          this.toggleHistoryStarred(item);
      })
      MenuItem({
        symbolStartIcon: this.historyMenuSymbol($r('sys.symbol.link')),
        content: $r('app.string.history_send_to_action'),
        symbolEndIcon: this.historyMenuSymbol($r('sys.symbol.chevron_forward')),
        builder: (): void => this.historyServerSendToMenu(item)
      })
      MenuItem({
        symbolStartIcon: this.historyDeleteMenuSymbol(),
        content: $r('app.string.history_delete_action')
      }).onClick((): void => {
          this.confirmDeleteHistory(item);
      })
    }.menuItemDivider({
      strokeWidth: LengthMetrics.vp(1),
      color: $r('app.color.divider'),
      startMargin: LengthMetrics.vp(12),
      endMargin: LengthMetrics.vp(12)
    })
  }

  @Builder
  private historyLocalContextMenu(item: ClipboardHistoryItem) {
    Menu() {
      MenuItem({
        symbolStartIcon: this.historyMenuSymbol($r('sys.symbol.clipboard_sharing')),
        content: $r('app.string.copy_action')
      }).onClick((): void => {
          this.copyLocalHistoryItem(item);
      })
      MenuItem({
        symbolStartIcon: this.historyMenuSymbol($r('sys.symbol.star')),
        content: item.starred ? $r('app.string.history_unstar_action') : $r('app.string.history_star_action')
      }).onClick((): void => {
          this.toggleLocalHistoryStarred(item);
      })
      MenuItem({
        symbolStartIcon: this.historyMenuSymbol($r('sys.symbol.link')),
        content: $r('app.string.history_send_to_action'),
        symbolEndIcon: this.historyMenuSymbol($r('sys.symbol.chevron_forward')),
        builder: (): void => this.historyLocalSendToMenu(item)
      })
      MenuItem({
        symbolStartIcon: this.historyDeleteMenuSymbol(),
        content: $r('app.string.history_delete_action')
      }).onClick((): void => {
          this.confirmDeleteLocalHistory(item);
      })
    }.menuItemDivider({
      strokeWidth: LengthMetrics.vp(1),
      color: $r('app.color.divider'),
      startMargin: LengthMetrics.vp(12),
      endMargin: LengthMetrics.vp(12)
    })
  }

  @Builder
  private clipboardImagePreview(pixelMap: image.PixelMap, imageId: string) {
    Image(pixelMap)
      .id(imageId)
      .width('100%')
      .height(220)
      .objectFit(ImageFit.Contain)
      .borderRadius($r('app.float.corner_radius_level4'))
      .backgroundColor($r('app.color.surface_muted'))
  }

  @Builder
  private statusPill() {
    Row({ space: 8 }) {
      Row()
        .width(8)
        .height(8)
        .borderRadius(4)
        .backgroundColor(this.isConnectionAvailable() ? $r('app.color.success') :
          this.statusCode === 3 ? $r('app.color.danger') : $r('app.color.text_secondary'))
      if (this.isConnectionAvailable()) {
        Text($r('app.string.status_online'))
          .fontSize($r('app.float.font_body_small'))
          .fontColor($r('app.color.text_secondary'))
      } else if (this.statusCode === 0) {
        Text($r('app.string.status_offline'))
          .fontSize($r('app.float.font_body_small'))
          .fontColor($r('app.color.text_secondary'))
      } else if (this.statusCode === 1) {
        Text($r('app.string.status_working'))
          .fontSize($r('app.float.font_body_small'))
          .fontColor($r('app.color.text_secondary'))
      } else {
        Text($r('app.string.status_failed'))
          .fontSize($r('app.float.font_body_small'))
          .fontColor($r('app.color.text_secondary'))
      }
    }
    .height(36)
    .padding({ left: 12, right: 12 })
    .borderRadius($r('app.float.corner_radius_level10'))
    .backgroundColor($r('app.color.surface_muted'))
    .flexShrink(0)
  }

  @Builder
  private mobileLatestContent() {
    if (this.desktopHasGestureShareContent() && !this.desktopGestureShareHintDismissed) {
      this.desktopGestureShareHint()
    }
    if (this.latestKind === 'Image' && this.latestImage !== null) {
      if (this.latestImageRevision % 2 === 0) {
        Image(this.latestImage)
          .id('latest-image-even')
          .width('100%')
          .aspectRatio(this.latestImageAspectRatio())
          .constraintSize({ maxHeight: 380 })
          .objectFit(ImageFit.Contain)
          .borderRadius($r('app.float.corner_radius_level4'))
          .backgroundColor($r('app.color.surface_muted'))
      } else {
        Image(this.latestImage)
          .id('latest-image-odd')
          .width('100%')
          .aspectRatio(this.latestImageAspectRatio())
          .constraintSize({ maxHeight: 380 })
          .objectFit(ImageFit.Contain)
          .borderRadius($r('app.float.corner_radius_level4'))
          .backgroundColor($r('app.color.surface_muted'))
      }
      Text(this.latestText)
        .fontSize($r('app.float.font_body_medium'))
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
    } else if (this.latestKind === 'File' && this.desktopShowsFile()) {
      if (this.desktopFileIsVideo() && this.desktopFilePreviewUri().length > 0) {
        Video({ src: this.desktopFilePreviewUri() })
          .id('mobile-latest-video-' + this.desktopFilePreviewKey())
          .width('100%')
          .aspectRatio(this.desktopVideoAspectRatio)
          .constraintSize({ maxHeight: 380 })
          .controls(true)
          .autoPlay(true)
          .objectFit(ImageFit.Contain)
          .borderRadius($r('app.float.corner_radius_level4'))
          .backgroundColor(Color.Black)
          .onPrepared((_preparedInfo: PreparedInfo): void => {
            this.loadDesktopVideoAspectRatio();
          })
          .onError((): void => {
            this.desktopFilePreviewState = 2;
          })
      } else if (this.desktopFileIsAudio()) {
        this.desktopAudioPreview()
      } else {
        Column({ space: 14 }) {
          SymbolGlyph($r('sys.symbol.doc_text'))
            .fontSize(50)
            .fontColor([this.accentColor()])
          Text(this.desktopFileIsDocument() ? $r('app.string.file_preview_document') :
            $r('app.string.file_preview_generic'))
            .fontSize($r('app.float.font_subtitle_large'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text($r('app.string.file_preview_system_note'))
            .fontSize($r('app.float.font_body_medium'))
            .lineHeight(20)
            .textAlign(TextAlign.Center)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(3)
        }
        .width('100%')
        .height(210)
        .justifyContent(FlexAlign.Center)
        .padding({ left: 22, right: 22 })
        .borderRadius($r('app.float.corner_radius_level8'))
        .backgroundColor($r('app.color.surface_muted'))
      }
      Text(this.desktopFileName())
        .fontSize($r('app.float.font_body_large'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Row({ space: 10 }) {
        Button(this.desktopFilePreviewState === 1 ? $r('app.string.file_preview_opening') :
          $r('app.string.file_preview_action'), { type: ButtonType.Normal })
          .height(40)
          .fontColor($r('app.color.on_accent'))
          .backgroundColor(this.accentColor())
          .borderRadius($r('app.float.corner_radius_level10'))
          .enabled(this.desktopFilePreviewUri().length > 0 && this.desktopFilePreviewState !== 1)
          .onClick((): void => {
            this.openDesktopFilePreview();
          })
        if (this.desktopFilePreviewState === 2) {
          Text($r('app.string.file_preview_failed'))
            .fontSize(12)
            .fontColor($r('app.color.danger'))
            .maxLines(2)
        }
      }
      .width('100%')
    } else {
      Text(this.latestText.length > 0 ? this.latestText : $r('app.string.latest_empty'))
        .fontSize(16)
        .fontColor(this.latestText.length > 0 ? $r('app.color.text_primary') :
          $r('app.color.text_secondary'))
        .lineHeight(24)
        .maxLines(7)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .padding(16)
        .borderRadius($r('app.float.corner_radius_level8'))
        .backgroundColor($r('app.color.surface_muted'))
    }
  }

  @Builder
  private syncPage() {
    Scroll(this.syncScroller) {
      Column({ space: 12 }) {
        Column({ space: 16 }) {
          Row({ space: 8 }) {
            Text($r('app.string.latest_title'))
              .fontSize($r('app.float.font_title_small'))
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Text(this.history.length.toString())
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.accentColor())
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .borderRadius($r('app.float.corner_radius_level2'))
              .backgroundColor(this.accentSoftColor())
            Blank()
          }
          this.mobileLatestContent()
          Row({ space: 10 }) {
            Button(!this.hasConfig() && this.spaceJoined ? $r('app.string.space_refresh_sync_action') :
              $r('app.string.pull_action'), { type: ButtonType.Normal })
              .layoutWeight(1)
              .height(46)
              .fontSize(14)
              .fontColor($r('app.color.on_accent'))
              .backgroundColor(this.accentColor())
              .borderRadius($r('app.float.corner_radius_level10'))
              .enabled(!this.busy)
              .onClick(() => {
                this.pullLatest();
              })
            Button(this.latestKind === 'File' ? $r('app.string.save_file_action') :
              $r('app.string.copy_action'), { type: ButtonType.Normal })
              .layoutWeight(1)
              .height(46)
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
              .backgroundColor($r('app.color.surface_muted'))
              .borderRadius($r('app.float.corner_radius_level10'))
              .enabled(this.latestCopyable())
              .onClick(() => {
                this.copyLatest();
              })
          }
        }
        .width('100%')
        .padding($r('app.float.padding_level8'))
        .borderRadius($r('app.float.corner_radius_level8'))
        .backgroundColor($r('app.color.surface'))
        .scale({ x: this.latestContentPulse, y: this.latestContentPulse })

        Column({ space: 12 }) {
          Text($r('app.string.composer_title'))
            .fontSize($r('app.float.font_title_small'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          TextArea({ placeholder: $r('app.string.composer_placeholder'), text: this.composerText })
            .height(124)
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
            .placeholderColor($r('app.color.text_secondary'))
            .backgroundColor($r('app.color.surface_muted'))
            .borderRadius($r('app.float.corner_radius_level8'))
            .padding(14)
            .onChange((value: string) => {
              this.composerText = value;
            })
          Row({ space: 10 }) {
            PasteButton({
              icon: PasteIconStyle.LINES,
              text: PasteDescription.PASTE,
              buttonType: ButtonType.Normal
            })
              .width('48%')
              .height(46)
              .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .iconColor($r('app.color.text_primary'))
              .backgroundColor($r('app.color.paste_button_background'))
              .borderRadius($r('app.float.corner_radius_level10'))
              .onClick((_event: ClickEvent, result: PasteButtonOnClickResult): void => {
                if (result === PasteButtonOnClickResult.SUCCESS) {
                  this.readLocalClipboard();
                } else {
                  this.statusCode = 3;
                }
              })
            Button($r('app.string.send_action'), { type: ButtonType.Normal })
              .layoutWeight(1)
              .height(46)
              .fontSize(14)
              .fontColor($r('app.color.on_accent'))
              .backgroundColor(this.accentColor())
              .borderRadius($r('app.float.corner_radius_level10'))
              .enabled(!this.busy && this.composerText.trim().length > 0)
              .onClick(() => {
                this.sendText();
              })
          }
          Divider()
            .color($r('app.color.divider'))
            .margin({ top: 6, bottom: 2 })
          Text($r('app.string.image_composer_title'))
            .fontSize($r('app.float.font_title_small'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          if (this.composerImage !== null) {
            if (this.composerImageRevision % 2 === 0) {
              Image(this.composerImage)
                .id('composer-image-even')
                .width('100%')
                .height(220)
                .objectFit(ImageFit.Contain)
                .borderRadius($r('app.float.corner_radius_level4'))
                .backgroundColor($r('app.color.surface_muted'))
            } else {
              Image(this.composerImage)
                .id('composer-image-odd')
                .width('100%')
                .height(220)
                .objectFit(ImageFit.Contain)
                .borderRadius($r('app.float.corner_radius_level4'))
                .backgroundColor($r('app.color.surface_muted'))
            }
          } else {
            Text($r('app.string.image_empty'))
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .lineHeight(22)
              .width('100%')
              .padding(14)
              .borderRadius($r('app.float.corner_radius_level8'))
              .backgroundColor($r('app.color.surface_muted'))
          }
          Row({ space: 10 }) {
            PasteButton({
              icon: PasteIconStyle.LINES,
              text: PasteDescription.PASTE,
              buttonType: ButtonType.Normal
            })
              .width('48%')
              .height(46)
              .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .iconColor($r('app.color.text_primary'))
              .backgroundColor($r('app.color.paste_button_background'))
              .borderRadius($r('app.float.corner_radius_level10'))
              .enabled(!this.busy && this.imageReadState !== 1)
              .onClick((_event: ClickEvent, result: PasteButtonOnClickResult): void => {
                if (result === PasteButtonOnClickResult.SUCCESS) {
                  this.readLocalImage();
                } else {
                  this.imageReadState = 4;
                  this.statusCode = 3;
                }
              })
            Button(this.imageSendState === 1 ? $r('app.string.image_sending') :
              $r('app.string.send_image_action'), { type: ButtonType.Normal })
              .layoutWeight(1)
              .height(46)
              .fontSize(14)
              .fontColor($r('app.color.on_accent'))
              .backgroundColor(this.accentColor())
              .borderRadius($r('app.float.corner_radius_level10'))
              .enabled(!this.busy && this.composerImage !== null)
              .onClick(() => {
                this.sendImage();
              })
          }
          if (this.imageSendState === 1) {
            Text($r('app.string.image_sending'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          } else if (this.imageSendState === 2) {
            Text($r('app.string.image_send_success'))
              .fontSize(12)
              .fontColor($r('app.color.success'))
              .width('100%')
          } else if (this.imageSendState === 3) {
            Text($r('app.string.image_send_failed'))
              .fontSize(12)
              .fontColor($r('app.color.danger'))
              .width('100%')
          } else if (this.imageReadState === 2) {
            Text($r('app.string.image_read_success'))
              .fontSize(12)
              .fontColor($r('app.color.success'))
              .width('100%')
          } else if (this.imageReadState === 3) {
            Text($r('app.string.image_read_empty'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          } else if (this.imageReadState === 4) {
            Text($r('app.string.clipboard_permission_denied'))
              .fontSize(12)
              .fontColor($r('app.color.danger'))
              .width('100%')
          } else if (this.imageReadState === 5) {
            Text($r('app.string.image_read_failed'))
              .fontSize(12)
              .fontColor($r('app.color.danger'))
              .width('100%')
          }
          Divider()
            .color($r('app.color.divider'))
            .margin({ top: 6, bottom: 2 })
          this.compactFileComposer()
        }
        .width('100%')
        .padding($r('app.float.padding_level8'))
        .borderRadius($r('app.float.corner_radius_level8'))
        .backgroundColor($r('app.color.surface'))

        Column({ space: 10 }) {
          Row() {
            Text($r('app.string.server_history_title'))
              .fontSize($r('app.float.font_title_small'))
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Blank()
            Button($r('app.string.server_history_refresh'), { type: ButtonType.Normal })
              .height(34)
              .fontSize($r('app.float.font_body_medium'))
              .fontColor(this.accentColor())
              .backgroundColor(this.accentSoftColor())
              .borderRadius($r('app.float.corner_radius_level10'))
              .enabled(!this.historyLoading)
              .onClick(() => {
                this.loadServerHistory(true);
              })
          }
          .width('100%')
          TextInput({ placeholder: $r('app.string.server_history_search_placeholder'),
            text: this.historySearchText })
            .height(44)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.surface_muted'))
            .borderRadius($r('app.float.corner_radius_level10'))
            .onChange((value: string) => {
              this.historySearchText = value;
            })
          Row({ space: 8 }) {
            Button($r('app.string.server_history_search_action'), { type: ButtonType.Normal })
              .layoutWeight(1)
              .height(38)
              .fontSize($r('app.float.font_body_medium'))
              .fontColor($r('app.color.text_primary'))
              .backgroundColor($r('app.color.surface_muted'))
              .borderRadius($r('app.float.corner_radius_level10'))
              .enabled(!this.historyLoading)
              .onClick(() => {
                this.loadServerHistory(true);
              })
            Button(this.historyStarredOnly ? $r('app.string.server_history_all_action') :
              $r('app.string.server_history_starred_action'), { type: ButtonType.Normal })
              .layoutWeight(1)
              .height(38)
              .fontSize($r('app.float.font_body_medium'))
              .fontColor(this.historyStarredOnly ? this.accentColor() : $r('app.color.text_primary'))
              .backgroundColor(this.historyStarredOnly ? this.accentSoftColor() :
                $r('app.color.surface_muted'))
              .borderRadius($r('app.float.corner_radius_level10'))
              .enabled(!this.historyLoading)
              .onClick(() => {
                this.historyStarredOnly = !this.historyStarredOnly;
                this.loadServerHistory(true);
              })
          }
          .width('100%')
          if (this.serverHistory.length === 0) {
            Text($r('app.string.server_history_empty'))
              .fontSize(14)
              .lineHeight(21)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .padding({ top: 8, bottom: 8 })
          } else {
            ForEach(this.serverHistory, (item: ServerHistoryItem) => {
              Column({ space: 5 }) {
                Text(item.text)
                  .fontSize($r('app.float.font_body_large'))
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(3)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                Row({ space: 8 }) {
                  Text(item.time)
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                  if (item.pinned) {
                    Text($r('app.string.server_history_pinned'))
                      .fontSize(12)
                      .fontColor(this.accentColor())
                  }
                  if (item.starred) {
                    Text('★')
                      .fontSize(12)
                      .fontColor(this.accentColor())
                  }
                }
                Row({ space: 8 }) {
                  Button(item.starred ? $r('app.string.history_unstar_action') :
                    $r('app.string.history_star_action'), { type: ButtonType.Normal })
                    .layoutWeight(1)
                    .height(32)
                    .fontSize(12)
                    .fontColor(item.starred ? this.accentColor() : $r('app.color.text_primary'))
                    .backgroundColor($r('app.color.surface_muted'))
                    .borderRadius($r('app.float.corner_radius_level4'))
                    .enabled(!this.historyMutationBusy)
                    .onClick(() => {
                      this.toggleHistoryStarred(item);
                    })
                  Button(item.pinned ? $r('app.string.history_unpin_action') :
                    $r('app.string.history_pin_action'), { type: ButtonType.Normal })
                    .layoutWeight(1)
                    .height(32)
                    .fontSize(12)
                    .fontColor(item.pinned ? this.accentColor() : $r('app.color.text_primary'))
                    .backgroundColor($r('app.color.surface_muted'))
                    .borderRadius($r('app.float.corner_radius_level4'))
                    .enabled(!this.historyMutationBusy)
                    .onClick(() => {
                      this.toggleHistoryPinned(item);
                    })
                  Button($r('app.string.history_delete_action'), { type: ButtonType.Normal })
                    .layoutWeight(1)
                    .height(32)
                    .fontSize(12)
                    .fontColor($r('app.color.danger'))
                    .backgroundColor($r('app.color.surface_muted'))
                    .borderRadius($r('app.float.corner_radius_level4'))
                    .enabled(!this.historyMutationBusy)
                    .onClick(() => {
                      this.confirmDeleteHistory(item);
                    })
                }
                .width('100%')
              }
              .width('100%')
              .padding({ top: 10, bottom: 10 })
              .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
              .clickEffect({ level: ClickEffectLevel.MIDDLE })
              .bindContextMenu(this.historyServerContextMenu(item), ResponseType.LongPress)
            }, (item: ServerHistoryItem) => item.id)
            Button(this.historyEnd ? $r('app.string.server_history_end') :
              $r('app.string.server_history_load_more'), { type: ButtonType.Normal })
              .height(42)
              .width('100%')
              .fontSize($r('app.float.font_body_medium'))
              .fontColor($r('app.color.text_primary'))
              .backgroundColor($r('app.color.surface_muted'))
              .borderRadius($r('app.float.corner_radius_level10'))
              .enabled(!this.historyLoading && !this.historyEnd)
              .onClick(() => {
                this.loadServerHistory(false);
              })
          }
        }
        .width('100%')
        .padding($r('app.float.padding_level8'))
        .borderRadius($r('app.float.corner_radius_level8'))
        .backgroundColor($r('app.color.surface'))

        Column({ space: 10 }) {
          Text($r('app.string.history_title'))
            .fontSize($r('app.float.font_title_small'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          if (this.history.length === 0) {
            Text($r('app.string.history_empty'))
              .fontSize(14)
              .lineHeight(21)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .padding({ top: 8, bottom: 8 })
          } else {
            ForEach(this.history, (item: ClipboardHistoryItem) => {
              Row({ space: 12 }) {
                Column() {
                  SymbolGlyph(item.direction === 'sent' ?
                    $r('sys.symbol.arrowshape_up_to_line_fill') :
                    $r('sys.symbol.arrowshape_down_to_line_fill'))
                    .fontSize(22)
                    .fontWeight(FontWeight.Medium)
                    .fontColor([item.direction === 'sent' ? this.accentColor() :
                      $r('app.color.success')])
                }
                .width(36)
                .height(36)
                .justifyContent(FlexAlign.Center)
                .borderRadius($r('app.float.corner_radius_level10'))
                .backgroundColor($r('app.color.surface_muted'))
                Column({ space: 4 }) {
                  Text(item.text)
                    .fontSize($r('app.float.font_body_large'))
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  Row({ space: 8 }) {
                    Blank()
                    Text(item.direction === 'sent' ? $r('app.string.direction_sent') :
                      $r('app.string.direction_received'))
                      .fontSize(12)
                      .fontColor(item.direction === 'sent' ? this.accentColor() :
                        $r('app.color.success'))
                    Text(item.time)
                      .fontSize(12)
                      .fontColor($r('app.color.text_secondary'))
                  }
                  .width('100%')
                }
                .layoutWeight(1)
              }
              .width('100%')
              .padding({ top: 10, bottom: 10 })
              .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
              .clickEffect({ level: ClickEffectLevel.MIDDLE })
              .bindContextMenu(this.historyLocalContextMenu(item), ResponseType.LongPress)
            }, (item: ClipboardHistoryItem) => item.id)
          }
        }
        .width('100%')
        .padding($r('app.float.padding_level8'))
        .borderRadius($r('app.float.corner_radius_level8'))
        .backgroundColor($r('app.color.surface'))
        .scale({ x: this.historyPulse, y: this.historyPulse })
      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: 56 + this.avoidAreaRectHeight,
        bottom: 116 + this.navigationRectHeight
      })
    }
    .scrollBar(BarState.Off)
    .layoutWeight(1)
  }

  @Builder
  private compactAppearanceOption(mode: string, icon: Resource, label: Resource) {
    Column({ space: 8 }) {
      SymbolGlyph(icon)
        .fontSize(24)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.appearanceMode === mode ? this.accentColor() :
          $r('app.color.text_secondary')])
      Text(label)
        .fontSize($r('app.float.font_body_medium'))
        .fontWeight(this.appearanceMode === mode ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.appearanceMode === mode ? this.accentColor() :
          $r('app.color.text_primary'))
    }
    .layoutWeight(1)
    .height(82)
    .justifyContent(FlexAlign.Center)
    .borderRadius($r('app.float.corner_radius_level8'))
    .backgroundColor(this.appearanceMode === mode ? this.accentSoftColor() :
      $r('app.color.surface_muted'))
    .border({
      width: this.appearanceMode === mode ? 2 : 1,
      color: this.appearanceMode === mode ? this.accentColor() : $r('app.color.divider')
    })
    .clickEffect({ level: ClickEffectLevel.MIDDLE })
    .onClick((): void => {
      this.selectAppearanceMode(mode);
    })
  }

  @Builder
  private compactAppearanceThemeOption(option: AppearanceThemeOption) {
    Row({ space: 10 }) {
      Row({ space: 4 }) {
        Blank()
          .width(22)
          .height(14)
          .borderRadius(7)
          .backgroundColor(option.primaryColor)
        Blank()
          .width(22)
          .height(14)
          .borderRadius(7)
          .backgroundColor(option.secondaryColor)
      }
      Text(this.appearanceThemeLabel(option.id))
        .fontSize(13)
        .fontWeight(this.appearanceThemeId === option.id ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.appearanceThemeId === option.id ? this.accentColor() :
          $r('app.color.text_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .height(56)
    .padding({ left: 12, right: 12 })
    .alignItems(VerticalAlign.Center)
    .borderRadius($r('app.float.corner_radius_level8'))
    .backgroundColor(this.appearanceThemeId === option.id ? this.accentSoftColor() :
      $r('app.color.surface_muted'))
    .border({
      width: this.appearanceThemeId === option.id ? 2 : 1,
      color: this.appearanceThemeId === option.id ? this.accentColor() : $r('app.color.divider')
    })
    .clickEffect({ level: ClickEffectLevel.MIDDLE })
    .onClick((): void => {
      this.selectAppearanceTheme(option.id);
    })
  }

  @Builder
  private compactAppearanceCard() {
    Column({ space: 16 }) {
      Row({ space: 12 }) {
        Column() {
          SymbolGlyph($r('sys.symbol.paintpalette'))
            .fontSize(24)
            .fontWeight(FontWeight.Medium)
            .fontColor([this.accentColor()])
        }
        .width(44)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .borderRadius($r('app.float.corner_radius_level4'))
        .backgroundColor(this.accentSoftColor())
        Column({ space: 4 }) {
          Text($r('app.string.appearance_title'))
            .fontSize($r('app.float.font_subtitle_large'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text($r('app.string.appearance_note'))
            .width('100%')
            .fontSize(12)
            .lineHeight(18)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(2)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      Row({ space: 8 }) {
        this.compactAppearanceOption(APPEARANCE_MODE_SYSTEM, $r('sys.symbol.circle_fill_half'),
          $r('app.string.appearance_follow_system'))
        this.compactAppearanceOption(APPEARANCE_MODE_LIGHT, $r('sys.symbol.sun_max'),
          $r('app.string.appearance_light'))
        this.compactAppearanceOption(APPEARANCE_MODE_DARK, $r('sys.symbol.moon'),
          $r('app.string.appearance_dark'))
      }
      .width('100%')
      Text($r('app.string.appearance_theme_title'))
        .fontSize($r('app.float.font_body_medium'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Column({ space: 10 }) {
        Row({ space: 10 }) {
          this.compactAppearanceThemeOption(APPEARANCE_THEME_OPTIONS[0])
          this.compactAppearanceThemeOption(APPEARANCE_THEME_OPTIONS[1])
        }
        .width('100%')
        Row({ space: 10 }) {
          this.compactAppearanceThemeOption(APPEARANCE_THEME_OPTIONS[2])
          this.compactAppearanceThemeOption(APPEARANCE_THEME_OPTIONS[3])
        }
        .width('100%')
        Row({ space: 10 }) {
          this.compactAppearanceThemeOption(APPEARANCE_THEME_OPTIONS[4])
          this.compactAppearanceThemeOption(APPEARANCE_THEME_OPTIONS[5])
        }
        .width('100%')
      }
      .width('100%')
    }
    .width('100%')
    .padding($r('app.float.padding_level8'))
    .borderRadius($r('app.float.corner_radius_level8'))
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  private backgroundSyncSwitchRow() {
    Row({ space: 16 }) {
      Column({ space: 4 }) {
        Text($r('app.string.background_sync_title'))
          .fontSize($r('app.float.font_body_large'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text($r('app.string.background_sync_note'))
          .fontSize($r('app.float.font_body_small'))
          .lineHeight(18)
          .fontColor($r('app.color.text_secondary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Toggle({ type: ToggleType.Switch, isOn: this.backgroundSyncEnabled })
        .selectedColor(this.accentColor())
        .onChange((enabled: boolean): void => {
          this.setBackgroundSyncEnabled(enabled);
        })
    }
    .width('100%')
    .height(78)
  }

  @Builder
  private mobileSyncManagementCard() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 4 }) {
          Text($r('app.string.mobile_sync_server_title'))
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(this.mobileSyncRunning ? $r('app.string.mobile_sync_server_running') :
            $r('app.string.mobile_sync_server_stopped'))
            .fontSize(12)
            .fontColor(this.mobileSyncRunning ? $r('app.color.success') :
              $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.mobileSyncEnabled })
          .selectedColor(this.accentColor())
          .enabled(!this.mobileSyncBusy)
          .onChange((enabled: boolean): void => {
            this.toggleMobileSyncServer(enabled);
          })
      }
      .width('100%')
      Text($r('app.string.mobile_sync_server_note'))
        .fontSize(12)
        .lineHeight(18)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      Row({ space: 10 }) {
        Text($r('app.string.mobile_sync_port'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        TextInput({ text: this.mobileSyncPort, placeholder: '42720' })
          .layoutWeight(1)
          .height(42)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.corner_radius_level8'))
          .onChange((value: string): void => {
            this.mobileSyncPort = value;
          })
        Button($r('app.string.operation_success'), { type: ButtonType.Normal })
          .height(42)
          .fontSize(12)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.corner_radius_level8'))
          .enabled(!this.mobileSyncBusy)
          .onClick((): void => {
            this.toggleMobileSyncServer(this.mobileSyncEnabled);
          })
      }
      .width('100%')
      if (this.mobileSyncUrls.length > 0) {
        Text($r('app.string.mobile_sync_addresses'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        ForEach(this.mobileSyncUrls, (url: string) => {
          Text(url)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .copyOption(CopyOptions.LocalDevice)
            .width('100%')
            .padding(10)
            .borderRadius($r('app.float.corner_radius_level4'))
            .backgroundColor($r('app.color.surface_muted'))
        }, (url: string): string => url)
      } else {
        Text($r('app.string.mobile_sync_no_address'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
      Row() {
        Text($r('app.string.mobile_sync_registered_devices'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Button($r('app.string.mobile_sync_add_device'), { type: ButtonType.Normal })
          .height(36)
          .fontSize(12)
          .fontColor($r('app.color.on_accent'))
          .backgroundColor(this.accentColor())
          .borderRadius($r('app.float.corner_radius_level8'))
          .enabled(this.mobileSyncRunning && !this.mobileSyncBusy)
          .onClick((): void => {
            this.mobileSyncAddOpen = !this.mobileSyncAddOpen;
            this.mobileSyncCredential = null;
            this.mobileSyncDeviceName = '';
            this.mobileSyncCustomUsername = '';
            this.mobileSyncCustomPassword = '';
            this.mobileSyncAdvancedOpen = false;
            this.mobileSyncState = 0;
          })
      }
      .width('100%')
      if (this.mobileSyncDevices.length === 0) {
        Text($r('app.string.mobile_sync_no_devices'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      } else {
        ForEach(this.mobileSyncDevices, (device: NativeMobileSyncDevice) => {
          Row({ space: 10 }) {
            Stack({ alignContent: Alignment.BottomEnd }) {
              Column() {
                SymbolGlyph($r('sys.symbol.phone'))
                  .fontSize(22)
                  .fontColor([this.accentColor()])
              }
              .width(40)
              .height(40)
              .justifyContent(FlexAlign.Center)
              .borderRadius($r('app.float.corner_radius_level4'))
              .backgroundColor(this.accentSoftColor())
              Row()
                .width(10)
                .height(10)
                .borderRadius(5)
                .backgroundColor(device.online ? $r('app.color.success') :
                  $r('app.color.text_secondary'))
                .border({ width: 2, color: $r('app.color.surface_muted') })
            }
            .width(40)
            .height(40)
            Column({ space: 3 }) {
              Text(device.label)
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(device.online ? $r('app.string.device_status_online') :
                (device.lastSeenAtMs > 0 ? $r('app.string.device_status_offline') :
                  $r('app.string.mobile_sync_never_seen')))
                .fontSize(11)
                .fontColor(device.online ? $r('app.color.success') :
                  $r('app.color.text_secondary'))
            }
            .layoutWeight(1)
            Button($r('app.string.mobile_sync_revoke'), { type: ButtonType.Normal })
              .height(32)
              .fontSize(11)
              .fontColor($r('app.color.danger'))
              .backgroundColor($r('app.color.surface_muted'))
              .borderRadius($r('app.float.corner_radius_level4'))
              .enabled(!this.desktopDeviceMutationBusy)
              .onClick((): void => {
                this.revokeMobileSyncDevice(device);
              })
          }
          .width('100%')
          .padding(8)
          .borderRadius($r('app.float.corner_radius_level4'))
          .backgroundColor($r('app.color.surface_muted'))
        }, (device: NativeMobileSyncDevice): string => device.deviceId)
      }
      if (this.mobileSyncAddOpen && this.mobileSyncCredential === null) {
        Column({ space: 9 }) {
          Text($r('app.string.mobile_sync_add_title'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          Text($r('app.string.mobile_sync_add_note'))
            .fontSize(12)
            .lineHeight(18)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          Text($r('app.string.mobile_sync_device_name'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          TextInput({ placeholder: $r('app.string.mobile_sync_device_placeholder'),
            text: this.mobileSyncDeviceName })
            .height(44)
            .fontSize(14)
            .backgroundColor($r('app.color.surface_muted'))
            .borderRadius($r('app.float.corner_radius_level8'))
            .onChange((value: string): void => {
              this.mobileSyncDeviceName = value;
            })
          Text($r('app.string.mobile_sync_advanced'))
            .fontSize(12)
            .fontColor(this.accentColor())
            .width('100%')
            .onClick((): void => {
              this.mobileSyncAdvancedOpen = !this.mobileSyncAdvancedOpen;
            })
          if (this.mobileSyncAdvancedOpen) {
            TextInput({ placeholder: $r('app.string.mobile_sync_custom_username'),
              text: this.mobileSyncCustomUsername })
              .height(44)
              .fontSize(14)
              .backgroundColor($r('app.color.surface_muted'))
              .borderRadius($r('app.float.corner_radius_level8'))
              .onChange((value: string): void => {
                this.mobileSyncCustomUsername = value;
              })
            TextInput({ placeholder: $r('app.string.mobile_sync_custom_password'),
              text: this.mobileSyncCustomPassword })
              .type(InputType.Password)
              .height(44)
              .fontSize(14)
              .backgroundColor($r('app.color.surface_muted'))
              .borderRadius($r('app.float.corner_radius_level8'))
              .onChange((value: string): void => {
                this.mobileSyncCustomPassword = value;
              })
          }
          Button(this.mobileSyncBusy ? $r('app.string.mobile_sync_creating') :
            $r('app.string.mobile_sync_create'), { type: ButtonType.Normal })
            .width('100%')
            .height(44)
            .fontColor($r('app.color.on_accent'))
            .backgroundColor(this.accentColor())
            .borderRadius($r('app.float.corner_radius_level8'))
            .enabled(this.mobileSyncDeviceName.trim().length > 0 && !this.mobileSyncBusy)
            .onClick((): void => {
              this.createMobileSyncDevice();
            })
        }
        .width('100%')
        .padding(12)
        .borderRadius($r('app.float.corner_radius_level8'))
        .backgroundColor($r('app.color.surface_muted'))
      }
      if (this.mobileSyncCredential !== null) {
        Column({ space: 10 }) {
          Text($r('app.string.mobile_sync_scan_title'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          Row() {
            QRCode(this.mobileSyncCredential.connectUri)
              .width(190)
              .height(190)
              .color($r('app.color.qr_foreground'))
              .backgroundColor($r('app.color.qr_background'))
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          Text($r('app.string.mobile_sync_scan_note'))
            .fontSize(12)
            .lineHeight(18)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          Text($r('app.string.mobile_sync_username'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          Text(this.mobileSyncCredential.username)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .copyOption(CopyOptions.LocalDevice)
            .width('100%')
          Text($r('app.string.mobile_sync_password'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          Text(this.mobileSyncPasswordVisible ? this.mobileSyncCredential.password : '••••••••••••')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .copyOption(CopyOptions.LocalDevice)
            .width('100%')
            .onClick((): void => {
              this.mobileSyncPasswordVisible = !this.mobileSyncPasswordVisible;
            })
          Text($r('app.string.mobile_sync_one_time_secret'))
            .fontSize(12)
            .fontColor($r('app.color.danger'))
            .width('100%')
        }
        .width('100%')
        .padding(12)
        .borderRadius($r('app.float.corner_radius_level8'))
        .border({ width: 1, color: $r('app.color.danger') })
      }
      if (this.mobileSyncState === 3) {
        Text($r('app.string.mobile_sync_server_failed'))
          .fontSize(12)
          .lineHeight(18)
          .fontColor($r('app.color.danger'))
          .width('100%')
      }
    }
    .width('100%')
    .padding($r('app.float.padding_level8'))
    .borderRadius($r('app.float.corner_radius_level8'))
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  private mobileSpaceConnectionGuide() {
    Column({ space: 7 }) {
      Row({ space: 8 }) {
        Text($r('app.string.mobile_space_connection_title'))
          .fontSize($r('app.float.font_subtitle_large'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text($r('app.string.mobile_space_connection_recommended'))
          .fontSize($r('app.float.font_caption_medium'))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.accentColor())
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .borderRadius($r('app.float.corner_radius_level10'))
          .backgroundColor(this.accentSoftColor())
      }
      .width('100%')
      Text($r('app.string.mobile_space_connection_note'))
        .fontSize($r('app.float.font_body_small'))
        .lineHeight(18)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      Row({ space: 7 }) {
        SymbolGlyph($r('sys.symbol.link'))
          .fontSize(16)
          .fontColor([this.accentColor()])
        Text($r('app.string.mobile_connection_difference_note'))
          .fontSize($r('app.float.font_body_small'))
          .lineHeight(18)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .padding(10)
      .borderRadius($r('app.float.corner_radius_level4'))
      .backgroundColor(this.accentSoftColor())
    }
    .width('100%')
    .padding({ left: 4, right: 4 })
  }

  @Builder
  private mobileLegacyConnectionCard() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.externaldrive'))
          .fontSize(22)
          .fontColor([$r('app.color.text_secondary')])
        Column({ space: 3 }) {
          Text($r('app.string.legacy_connection_title'))
            .fontSize($r('app.float.font_body_large'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          Text($r('app.string.legacy_connection_note'))
            .fontSize($r('app.float.font_body_small'))
            .lineHeight(18)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      Button(this.legacyConnectionExpanded ? $r('app.string.legacy_connection_collapse') :
        $r('app.string.legacy_connection_expand'), { type: ButtonType.Normal })
        .height(44)
        .width('100%')
        .fontSize($r('app.float.font_body_medium'))
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius($r('app.float.corner_radius_level10'))
        .onClick((): void => {
          this.legacyConnectionExpanded = !this.legacyConnectionExpanded;
        })
      if (this.legacyConnectionExpanded) {
        Divider()
          .color($r('app.color.divider'))
          .margin({ top: 2, bottom: 2 })
        Text($r('app.string.legacy_connect_code_title'))
          .fontSize($r('app.float.font_body_medium'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        TextArea({ placeholder: $r('app.string.connect_uri_placeholder'), text: this.connectUri })
          .height(96)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_secondary'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.corner_radius_level8'))
          .padding(12)
          .onChange((value: string): void => {
            this.connectUri = value;
            this.connectUriState = 0;
          })
        if (this.connectUriState === 1) {
          Text($r('app.string.connect_uri_success'))
            .fontSize(12)
            .fontColor($r('app.color.success'))
            .width('100%')
        } else if (this.connectUriState === 2) {
          Text($r('app.string.connect_uri_failed'))
            .fontSize(12)
            .fontColor($r('app.color.danger'))
            .width('100%')
        } else if (this.connectUriState === 3) {
          Text($r('app.string.connect_uri_scan_failed'))
            .fontSize(12)
            .fontColor($r('app.color.danger'))
            .width('100%')
        }
        Button($r('app.string.connect_uri_scan_action'), { type: ButtonType.Normal })
          .height(46)
          .width('100%')
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.corner_radius_level10'))
          .onClick((): void => {
            this.scanConnectUri();
          })
        Button($r('app.string.connect_uri_action'), { type: ButtonType.Normal })
          .height(46)
          .width('100%')
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.corner_radius_level10'))
          .enabled(this.connectUri.trim().length > 0)
          .onClick((): void => {
            this.importConnectUri();
          })
        Divider()
          .color($r('app.color.divider'))
          .margin({ top: 6, bottom: 2 })
        Text($r('app.string.legacy_service_form_title'))
          .fontSize($r('app.float.font_body_medium'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text($r('app.string.legacy_server_url_label'))
          .fontSize($r('app.float.font_body_medium'))
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        TextInput({ placeholder: $r('app.string.server_url_placeholder'), text: this.serverUrl })
          .height(50)
          .fontSize($r('app.float.font_body_large'))
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.corner_radius_level10'))
          .onChange((value: string): void => {
            this.serverUrl = value;
            this.connectionChanged();
          })
        Text($r('app.string.username_label'))
          .fontSize($r('app.float.font_body_medium'))
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .margin({ top: 6 })
        TextInput({ placeholder: $r('app.string.username_placeholder'), text: this.username })
          .height(50)
          .fontSize($r('app.float.font_body_large'))
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.corner_radius_level10'))
          .onChange((value: string): void => {
            this.username = value;
            this.connectionChanged();
          })
        Text($r('app.string.password_label'))
          .fontSize($r('app.float.font_body_medium'))
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .margin({ top: 6 })
        TextInput({ placeholder: $r('app.string.password_placeholder'), text: this.password })
          .type(InputType.Password)
          .height(50)
          .fontSize($r('app.float.font_body_large'))
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.corner_radius_level10'))
          .onChange((value: string): void => {
            this.password = value;
            this.connectionChanged();
          })
        Button($r('app.string.test_connection_action'), { type: ButtonType.Normal })
          .height(50)
          .width('100%')
          .fontSize($r('app.float.font_body_large'))
          .fontColor($r('app.color.on_accent'))
          .backgroundColor(this.accentColor())
          .borderRadius($r('app.float.corner_radius_level10'))
          .margin({ top: 12 })
          .enabled(this.hasConfig() && !this.busy)
          .onClick((): void => {
            this.testConnection();
          })
        Button(this.realtimeActive ? $r('app.string.realtime_stop_action') :
          $r('app.string.realtime_start_action'), { type: ButtonType.Normal })
          .height(50)
          .width('100%')
          .fontSize($r('app.float.font_body_large'))
          .fontColor(this.realtimeActive ? $r('app.color.danger') : $r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.corner_radius_level10'))
          .enabled(this.hasConfig())
          .onClick((): void => {
            this.toggleRealtime();
          })
        Text(this.realtimeActive ? $r('app.string.realtime_active_note') :
          $r('app.string.realtime_inactive_note'))
          .fontSize(12)
          .lineHeight(18)
          .fontColor(this.realtimeActive ? $r('app.color.success') : $r('app.color.text_secondary'))
          .width('100%')
      }
    }
    .width('100%')
    .padding($r('app.float.padding_level8'))
    .borderRadius($r('app.float.corner_radius_level8'))
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  private compactDevicePage() {
    Scroll(this.devicesScroller) {
      Column({ space: 12 }) {
        Column({ space: 12 }) {
          Row() {
            Column({ space: 4 }) {
              Text($r('app.string.desktop_paired_devices'))
                .fontSize($r('app.float.font_subtitle_large'))
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text(this.spaceJoined ? $r('app.string.desktop_roster_note') :
                $r('app.string.desktop_no_device'))
                .fontSize($r('app.float.font_body_small'))
                .fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Text(this.spaceDevices.length.toString())
              .fontSize($r('app.float.font_body_small'))
              .fontColor($r('app.color.text_secondary'))
              .padding({ left: 9, right: 9, top: 3, bottom: 3 })
              .borderRadius($r('app.float.corner_radius_level10'))
              .backgroundColor($r('app.color.surface_muted'))
          }
          .width('100%')
          if (this.spaceJoined) {
            Row({ space: 10 }) {
              Button($r('app.string.desktop_refresh_devices'), { type: ButtonType.Normal })
                .layoutWeight(1)
                .height(42)
                .fontSize($r('app.float.font_body_small'))
                .fontColor($r('app.color.text_primary'))
                .backgroundColor($r('app.color.surface_muted'))
                .borderRadius($r('app.float.corner_radius_level10'))
                .enabled(!this.spaceDeviceRefreshBusy && !this.spaceConnectBusy &&
                  !this.desktopDeviceMutationBusy)
                .onClick((): void => {
                  this.refreshSpaceDevices();
                })
              Button(this.spaceConnectBusy ? $r('app.string.desktop_connecting_all_devices') :
                $r('app.string.desktop_connect_all_devices'), { type: ButtonType.Normal })
                .layoutWeight(1)
                .height(42)
                .fontSize($r('app.float.font_body_small'))
                .fontColor($r('app.color.on_accent'))
                .backgroundColor(this.accentColor())
                .borderRadius($r('app.float.corner_radius_level10'))
                .enabled(!this.spaceConnectBusy && !this.desktopDeviceMutationBusy)
                .onClick((): void => {
                  this.connectAllSpaceDevices();
                })
            }
            .width('100%')
            if (this.spaceConnectState === 2) {
              Text($r('app.string.desktop_connect_devices_success'))
                .fontSize($r('app.float.font_body_small'))
                .fontColor($r('app.color.success'))
                .width('100%')
            } else if (this.spaceConnectState === 3) {
              Text($r('app.string.desktop_connect_devices_failed'))
                .fontSize($r('app.float.font_body_small'))
                .fontColor($r('app.color.danger'))
                .width('100%')
            }
            ForEach(this.spaceDevices, (device: NativeSpaceDevice) => {
              this.desktopPairedDeviceRow(device)
            }, (device: NativeSpaceDevice): string => device.deviceId)
          }
          Text($r('app.string.device_management_hint'))
            .fontSize($r('app.float.font_body_small'))
            .lineHeight(18)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }
        .width('100%')
        .padding($r('app.float.padding_level8'))
        .borderRadius($r('app.float.corner_radius_level8'))
        .backgroundColor($r('app.color.surface'))

        Column({ space: 12 }) {
          Row() {
            Text($r('app.string.mobile_sync_registered_devices'))
              .fontSize($r('app.float.font_subtitle_large'))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Blank()
            Text(this.mobileSyncDevices.length.toString())
              .fontSize($r('app.float.font_body_small'))
              .fontColor($r('app.color.text_secondary'))
              .padding({ left: 9, right: 9, top: 3, bottom: 3 })
              .borderRadius($r('app.float.corner_radius_level10'))
              .backgroundColor($r('app.color.surface_muted'))
          }
          .width('100%')
          if (this.mobileSyncDevices.length === 0) {
            Text($r('app.string.mobile_sync_no_devices'))
              .fontSize($r('app.float.font_body_small'))
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .padding({ top: 8, bottom: 8 })
          } else {
            ForEach(this.mobileSyncDevices, (device: NativeMobileSyncDevice) => {
              this.desktopMobileDeviceRow(device)
            }, (device: NativeMobileSyncDevice): string => device.deviceId)
          }
        }
        .width('100%')
        .padding($r('app.float.padding_level8'))
        .borderRadius($r('app.float.corner_radius_level8'))
        .backgroundColor($r('app.color.surface'))
      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: 56 + this.avoidAreaRectHeight,
        bottom: 116 + this.navigationRectHeight
      })
    }
    .scrollBar(BarState.Off)
    .layoutWeight(1)
  }

  @Builder
  private settingsPage() {
    Scroll(this.settingsScroller) {
      Column({ space: 12 }) {
        this.compactAppearanceCard()

        this.mobileSpaceConnectionGuide()

        this.spaceJoinCard()

        Column() {
          this.backgroundSyncSwitchRow()
        }
        .width('100%')
        .padding({ left: 18, right: 18 })
        .borderRadius($r('app.float.corner_radius_level8'))
        .backgroundColor($r('app.color.surface'))

        this.mobileSyncManagementCard()

        this.mobileLegacyConnectionCard()
      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: 56 + this.avoidAreaRectHeight,
        bottom: 116 + this.navigationRectHeight
      })
    }
    .scrollBar(BarState.Off)
    .layoutWeight(1)
  }

  @Builder
  private compactTabBar(index: number, icon: Resource, label: Resource) {
    Column({ space: 4 }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontWeight(this.selectedTab === index ? FontWeight.Bold : FontWeight.Regular)
        .fontColor([this.selectedTab === index ? this.accentColor() :
          $r('app.color.text_secondary')])
      Text(label)
        .fontSize(10)
        .fontWeight(this.selectedTab === index ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.selectedTab === index ? this.accentColor() :
          $r('app.color.text_secondary'))
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height('100%')
  }

  @Builder
  private compactAboutCapability(icon: Resource, label: Resource) {
    Column({ space: 8 }) {
      SymbolGlyph(icon)
        .fontSize(24)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.accentColor()])
      Text(label)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Center)
        .maxLines(1)
    }
    .layoutWeight(1)
    .height(72)
    .justifyContent(FlexAlign.Center)
    .borderRadius($r('app.float.corner_radius_level8'))
    .backgroundColor(this.accentSoftColor())
  }

  @Builder
  private feedbackSheetContent() {
    Column({ space: 0 }) {
      Text($r('app.string.feedback_description'))
        .fontSize($r('app.float.font_body_large'))
        .lineHeight(24)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      Text($r('app.string.feedback_content_label'))
        .fontSize($r('app.float.font_body_large'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ top: 24, bottom: 10 })
      TextArea({
        placeholder: $r('app.string.feedback_content_placeholder'),
        text: this.feedbackText
      })
        .width('100%')
        .height(160)
        .fontSize($r('app.float.font_body_large'))
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_tertiary'))
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius($r('app.float.corner_radius_level8'))
        .border({ width: 1, color: $r('app.color.divider') })
        .padding(16)
        .onChange((value: string): void => {
          this.feedbackText = value;
        })
      Text($r('app.string.feedback_email_label'))
        .fontSize($r('app.float.font_body_large'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ top: 22, bottom: 10 })
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.envelope'))
          .fontSize(20)
          .fontColor([this.accentColor()])
        Text(FEEDBACK_EMAIL)
          .fontSize($r('app.float.font_body_large'))
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
      }
      .width('100%')
      .height(54)
      .padding({ left: 16, right: 16 })
      .borderRadius($r('app.float.corner_radius_level8'))
      .backgroundColor(this.accentSoftColor())
      Button($r('app.string.feedback_write_clipboard_action'), { type: ButtonType.Normal })
        .width('100%')
        .height(50)
        .fontSize($r('app.float.font_body_large'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.on_accent'))
        .backgroundColor(this.accentColor())
        .borderRadius($r('app.float.corner_radius_level10'))
        .margin({ top: 24 })
        .enabled(this.feedbackText.trim().length > 0)
        .onClick((): void => {
          this.submitFeedback();
        })
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 18, bottom: 26 })
  }

  @Builder
  private feedbackSheet() {
    HdsNavigation() {
      Scroll() {
        Column() {
          Blank()
            .width('100%')
            .height(55)
          this.feedbackSheetContent()
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .titleBar({
      content: {
        title: {
          mainTitle: $r('app.string.feedback_dialog_title')
        },
        menu: {
          value: [{
            content: {
              label: 'modal_cancel',
              isEnabled: true,
              type: IconStyleMode.SMALL,
              action: (): void => {
                this.showFeedbackSheet = false;
              }
            }
          }]
        }
      },
      style: {
        scrollEffectOpts: {
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR
        },
        originalStyle: {
          contentStyle: {
            menuStyle: {
              iconColor: this.accentColor()
            }
          }
        },
        scrollEffectStyle: {
          contentStyle: {
            menuStyle: {
              iconColor: this.accentColor()
            }
          }
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      }
    })
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .mode(NavigationMode.Stack)
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private aboutSheetContent() {
    Column({ space: 0 }) {
      Image($r('app.media.uniclipboard_start_icon'))
        .width(82)
        .height(82)
        .borderRadius($r('app.float.corner_radius_level4'))
        .objectFit(ImageFit.Cover)
        .draggable(false)
        .gesture(
          TapGesture({ count: 2 })
            .onAction((): void => {
              this.reopenOnboardingGuide();
            })
        )
      Text($r('app.string.app_title'))
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 16 })
      Text($r('app.string.desktop_version'))
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.accentColor())
        .padding({ left: 12, right: 12, top: 5, bottom: 5 })
        .borderRadius($r('app.float.corner_radius_level10'))
        .backgroundColor(this.accentSoftColor())
        .margin({ top: 8 })
      Text($r('app.string.about_tagline'))
        .fontSize($r('app.float.font_subtitle_large'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Center)
        .margin({ top: 18 })
      Text($r('app.string.about_description'))
        .fontSize(14)
        .lineHeight(21)
        .textAlign(TextAlign.Center)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 8 })
      Row({ space: 10 }) {
        this.compactAboutCapability($r('sys.symbol.rectangle_stack'),
          $r('app.string.about_feature_sync'))
        this.compactAboutCapability($r('sys.symbol.connection'),
          $r('app.string.about_feature_space'))
        this.compactAboutCapability($r('sys.symbol.desktop'),
          $r('app.string.about_feature_native'))
      }
      .width('100%')
      .margin({ top: 22 })
      Text($r('app.string.about_footer'))
        .fontSize($r('app.float.font_body_small'))
        .lineHeight(17)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .margin({ top: 18 })
      Button($r('app.string.about_feedback_action'), { type: ButtonType.Normal })
        .width('100%')
        .height(48)
        .fontSize($r('app.float.font_body_large'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.on_accent'))
        .backgroundColor(this.accentColor())
        .borderRadius($r('app.float.corner_radius_level10'))
        .margin({ top: 22 })
        .onClick((): void => {
          this.openFeedbackFromAbout();
        })
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 20, bottom: 24 })
  }

  @Builder
  private aboutSheet() {
    HdsNavigation() {
      Scroll(this.aboutScroller) {
        Column() {
          Blank()
            .width('100%')
            .height(55)
          this.aboutSheetContent()
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .titleBar({
      content: {
        title: {
          mainTitle: $r('app.string.about_title')
        },
        menu: {
          value: [{
            content: {
              label: 'modal_cancel',
              isEnabled: true,
              type: IconStyleMode.SMALL,
              action: (): void => {
                this.showAboutSheet = false;
              }
            }
          }]
        }
      },
      style: {
        scrollEffectOpts: {
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: this.aboutMaterialLevel
        }
      }
    })
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .mode(NavigationMode.Stack)
    .bindToScrollable([this.aboutScroller])
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private compactSyncNavigation() {
    HdsNavigation() {
      this.syncPage()
    }
    .titleBar({
      avoidLayoutSafeArea: true,
      content: {
        title: {
          mainTitle: $r('app.string.nav_sync'),
          subTitle: $r('app.string.app_subtitle')
        },
        menu: {
          value: [{
            content: {
              icon: this.titleBarConnectionIcon(),
              label: this.isConnectionAvailable() ?
                $r('app.string.status_online') : $r('app.string.status_offline'),
              action: (): void => {
                this.selectPage(1);
              }
            }
          }, {
            content: {
              icon: $r('sys.symbol.info_circle'),
              label: $r('app.string.about_title'),
              action: (): void => {
                this.showAboutSheet = true;
              }
            }
          }]
        }
      },
      style: {
        scrollEffectOpts: {
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR
        },
        originalStyle: {
          contentStyle: {
            menuStyle: {
              iconColor: this.accentColor()
            }
          }
        },
        scrollEffectStyle: {
          contentStyle: {
            menuStyle: {
              iconColor: this.accentColor()
            }
          }
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      }
    })
    .bindToScrollable([this.syncScroller])
    .hideBackButton(true)
    .titleMode(HdsNavigationTitleMode.MINI)
    .mode(NavigationMode.Stack)
    .backgroundColor($r('app.color.page_background'))
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM],
      [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  @Builder
  private compactDevicesNavigation() {
    HdsNavigation() {
      this.compactDevicePage()
    }
    .titleBar({
      avoidLayoutSafeArea: true,
      content: {
        title: {
          mainTitle: $r('app.string.desktop_devices')
        }
      },
      style: {
        scrollEffectOpts: {
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      }
    })
    .bindToScrollable([this.devicesScroller])
    .hideBackButton(true)
    .titleMode(HdsNavigationTitleMode.MINI)
    .mode(NavigationMode.Stack)
    .backgroundColor($r('app.color.page_background'))
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM],
      [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  @Builder
  private compactSettingsNavigation() {
    HdsNavigation() {
      this.settingsPage()
    }
    .titleBar({
      avoidLayoutSafeArea: true,
      content: {
        title: {
          mainTitle: $r('app.string.nav_settings')
        },
        menu: {
          value: [{
            content: {
              icon: this.titleBarConnectionIcon(),
              label: this.isConnectionAvailable() ?
                $r('app.string.status_online') : $r('app.string.status_offline'),
              action: (): void => {
                this.testConnection();
              }
            }
          }, {
            content: {
              icon: $r('sys.symbol.info_circle'),
              label: $r('app.string.about_title'),
              action: (): void => {
                this.showAboutSheet = true;
              }
            }
          }]
        }
      },
      style: {
        scrollEffectOpts: {
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR
        },
        originalStyle: {
          contentStyle: {
            menuStyle: {
              iconColor: this.accentColor()
            }
          }
        },
        scrollEffectStyle: {
          contentStyle: {
            menuStyle: {
              iconColor: this.accentColor()
            }
          }
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      }
    })
    .bindToScrollable([this.settingsScroller])
    .hideBackButton(true)
    .titleMode(HdsNavigationTitleMode.MINI)
    .mode(NavigationMode.Stack)
    .backgroundColor($r('app.color.page_background'))
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM],
      [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  @Builder
  private compactNavigation() {
    HdsTabs({ index: this.selectedTab }) {
      TabContent() {
        this.compactSyncNavigation()
      }
        .tabBar(this.compactTabBar(0, $r('sys.symbol.clipboard_sharing'),
          $r('app.string.nav_sync')))

      TabContent() {
        this.compactDevicesNavigation()
      }
        .tabBar(this.compactTabBar(1, $r('sys.symbol.desktop'),
          $r('app.string.desktop_devices')))

      TabContent() {
        this.compactSettingsNavigation()
      }
        .tabBar(this.compactTabBar(2, $r('sys.symbol.gearshape'),
          $r('app.string.nav_settings')))
    }
    .barPosition(BarPosition.End)
    .vertical(false)
    .scrollable(false)
    .barOverlap(true)
    .barFloatingStyle({
      barWidth: { smallWidth: 260, mediumWidth: 360, largeWidth: 440 },
      barBottomMargin: 28,
      gradientMask: { maskColor: $r('app.color.navigation_mask'), maskHeight: 92 },
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      }
    })
    .onChange((index: number): void => {
      this.selectPage(index);
    })
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM],
      [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .bindSheet($$this.showAboutSheet, this.aboutSheet(), {
      detents: [SheetSize.MEDIUM],
      preferType: SheetType.CENTER,
      dragBar: false,
      showClose: false,
      backgroundColor: $r('app.color.page_background'),
      blurStyle: BlurStyle.Regular,
      onDisappear: (): void => {
        this.onAboutSheetDisappear();
      }
    })
  }

  @Builder
  private largeSidebarItem(index: number, icon: Resource, label: Resource) {
    Row({ space: 8 }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([this.selectedTab === index ? this.accentColor() :
          $r('app.color.text_secondary')])
      Text(label)
        .fontSize(16)
        .fontWeight(this.selectedTab === index ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.selectedTab === index ? this.accentColor() :
          $r('app.color.text_primary'))
      }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
    .borderRadius($r('app.float.corner_radius_level8'))
    .backgroundColor(this.selectedTab === index ? this.accentSoftColor() : Color.Transparent)
    .clickEffect({ level: ClickEffectLevel.MIDDLE })
    .onClick(() => {
      this.selectPage(index);
    })
  }

  @Builder
  private largeSidebar() {
    Column({ space: 8 }) {
      this.largeSidebarItem(0, $r('sys.symbol.clipboard_sharing'), $r('app.string.nav_sync'))
      this.largeSidebarItem(1, $r('sys.symbol.desktop'), $r('app.string.desktop_devices'))
      this.largeSidebarItem(2, $r('sys.symbol.gearshape'), $r('app.string.nav_settings'))
      Blank()
      this.statusPill()
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 20 })
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  private largeDestination(name: string, _param: Object) {
    HdsNavDestination() {
      Column() {
        if (name === 'devices') {
          this.desktopDeviceWorkspace()
        } else if (name === 'settings') {
          this.settingsPage()
        } else {
          this.syncPage()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
    }
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .hideBackButton(true)
    .titleBar({
      content: {
        title: {
          mainTitle: name === 'devices' ? $r('app.string.desktop_devices') :
            (name === 'settings' ? $r('app.string.nav_settings') : $r('app.string.nav_sync'))
        }
      }
    })
  }

  @Builder
  private desktopRailButton(index: number, icon: Resource, label: Resource) {
    Column({ space: 4 }) {
      SymbolGlyph(icon)
        .fontSize(24)
        .fontWeight(this.largeSection === index ? FontWeight.Bold : FontWeight.Regular)
        .fontColor([this.largeSection === index ? this.accentColor() :
          $r('app.color.text_secondary')])
      Text(label)
        .fontSize($r('app.float.font_desktop_rail_label'))
        .fontWeight(this.largeSection === index ? FontWeight.Medium : FontWeight.Regular)
        .maxLines(1)
        .fontColor(this.largeSection === index ? this.accentColor() :
          $r('app.color.text_secondary'))
    }
    .width(64)
    .height(64)
    .justifyContent(FlexAlign.Center)
    .borderRadius($r('app.float.corner_radius_level10'))
    .backgroundColor(this.largeSection === index ? this.accentSoftColor() : Color.Transparent)
    .clickEffect({ level: ClickEffectLevel.MIDDLE })
    .onClick((): void => {
      this.selectLargeSection(index);
    })
  }

  @Builder
  private desktopFeedbackRailButton() {
    Column({ space: 4 }) {
      SymbolGlyph($r('sys.symbol.message'))
        .fontSize(24)
        .fontColor([$r('app.color.text_secondary')])
      Text($r('app.string.nav_feedback'))
        .fontSize($r('app.float.font_desktop_rail_label'))
        .fontWeight(FontWeight.Regular)
        .maxLines(1)
        .fontColor($r('app.color.text_secondary'))
    }
    .width(64)
    .height(64)
    .justifyContent(FlexAlign.Center)
    .borderRadius($r('app.float.corner_radius_level10'))
    .backgroundColor(Color.Transparent)
    .clickEffect({ level: ClickEffectLevel.MIDDLE })
    .onClick((): void => {
      this.openFeedback();
    })
  }

  @Builder
  private desktopRail() {
    Column({ space: 12 }) {
      Column() {
        Image($r('app.media.uniclipboard_start_icon'))
          .width(50)
          .height(50)
          .borderRadius($r('app.float.corner_radius_level4'))
          .objectFit(ImageFit.Cover)
          .draggable(false)
      }
      .width(64)
      .height(64)
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: 6 })
      .gesture(
        TapGesture({ count: 2 })
          .onAction((): void => {
            this.reopenOnboardingGuide();
          })
      )
      this.desktopRailButton(0, $r('sys.symbol.rectangle_stack'), $r('app.string.desktop_clipboard'))
      this.desktopRailButton(1, $r('sys.symbol.desktop'), $r('app.string.desktop_devices'))
      Blank()
      this.desktopFeedbackRailButton()
      this.desktopRailButton(2, $r('sys.symbol.gearshape'), $r('app.string.nav_settings'))
    }
    .width(88)
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 18, bottom: 18 })
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private desktopFilterItem(group: number, value: number, icon: Resource, label: Resource) {
    Row({ space: 12 }) {
      SymbolGlyph(icon)
        .fontSize(19)
        .fontWeight(this.desktopFilterSelected(group, value) ? FontWeight.Medium : FontWeight.Regular)
        .fontColor([this.desktopFilterSelected(group, value) ? this.accentColor() :
          $r('app.color.text_secondary')])
      Text(label)
        .fontSize($r('app.float.font_body_large'))
        .fontWeight(this.desktopFilterSelected(group, value) ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.desktopFilterSelected(group, value) ? $r('app.color.text_primary') :
          $r('app.color.text_secondary'))
    }
    .width('100%')
    .height(44)
    .padding({ left: 14, right: 14 })
    .borderRadius($r('app.float.corner_radius_level10'))
    .backgroundColor(this.desktopFilterSelected(group, value) ? this.accentSoftColor() :
      Color.Transparent)
    .clickEffect({ level: ClickEffectLevel.MIDDLE })
    .onClick((): void => {
      this.applyDesktopFilter(group, value);
    })
  }

  @Builder
  private desktopFilterSectionLabel(label: Resource) {
    Text(label)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_tertiary'))
      .width('100%')
      .padding({ left: 14, top: 14, bottom: 3 })
  }

  @Builder
  private desktopExtensionFilterItem(extension: string, label: Resource) {
    Row({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.doc_text'))
        .fontSize(19)
        .fontWeight(this.desktopExtensionFilter === extension ? FontWeight.Medium : FontWeight.Regular)
        .fontColor([this.desktopExtensionFilter === extension ? this.accentColor() :
          $r('app.color.text_secondary')])
      Text(label)
        .fontSize($r('app.float.font_body_large'))
        .fontWeight(this.desktopExtensionFilter === extension ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.desktopExtensionFilter === extension ? $r('app.color.text_primary') :
          $r('app.color.text_secondary'))
    }
    .width('100%')
    .height(44)
    .padding({ left: 14, right: 14 })
    .borderRadius($r('app.float.corner_radius_level10'))
    .backgroundColor(this.desktopExtensionFilter === extension ? this.accentSoftColor() :
      Color.Transparent)
    .clickEffect({ level: ClickEffectLevel.MIDDLE })
    .onClick((): void => {
      this.applyDesktopExtensionFilter(extension);
    })
  }

  @Builder
  private desktopClipboardFilters() {
    Column() {
      Row() {
        Text($r('app.string.desktop_library'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Blank()
      }
      .width('100%')
      .height(72)
      .padding({ left: 24, right: 20 })
      Scroll() {
        Column({ space: 4 }) {
          this.desktopFilterItem(0, 0, $r('sys.symbol.square_grid_2x2'), $r('app.string.desktop_all'))
          this.desktopFilterItem(0, 1, $r('sys.symbol.star'), $r('app.string.history_star_action'))
          this.desktopFilterSectionLabel($r('app.string.desktop_types'))
          this.desktopFilterItem(1, 1, $r('sys.symbol.doc_text'), $r('app.string.desktop_text'))
          this.desktopFilterItem(1, 2, $r('sys.symbol.textformat'), $r('app.string.desktop_rich_text'))
          this.desktopFilterItem(1, 3, $r('sys.symbol.ohos_photo'), $r('app.string.desktop_images'))
          this.desktopFilterItem(1, 4, $r('sys.symbol.folder'), $r('app.string.desktop_files'))
          this.desktopFilterSectionLabel($r('app.string.desktop_tags'))
          this.desktopFilterItem(2, 1, $r('sys.symbol.link'), $r('app.string.desktop_tag_link'))
          this.desktopFilterItem(2, 2, $r('sys.symbol.code'), $r('app.string.desktop_tag_code'))
          this.desktopFilterItem(2, 3, $r('sys.symbol.ohos_photo'), $r('app.string.desktop_tag_image'))
          this.desktopFilterItem(2, 4, $r('sys.symbol.folder'), $r('app.string.desktop_tag_folder'))
          this.desktopFilterSectionLabel($r('app.string.desktop_sources'))
          this.desktopFilterItem(3, 0, $r('sys.symbol.rectangle_stack'), $r('app.string.desktop_all_sources'))
          this.desktopFilterItem(3, 1, $r('sys.symbol.desktop'), $r('app.string.desktop_server_source'))
          this.desktopFilterItem(3, 2, $r('sys.symbol.phone'), $r('app.string.desktop_session_source'))
          this.desktopFilterSectionLabel($r('app.string.desktop_time'))
          this.desktopFilterItem(4, 0, $r('sys.symbol.clock'), $r('app.string.desktop_unlimited_time'))
          this.desktopFilterItem(4, 1, $r('sys.symbol.clock'), $r('app.string.desktop_today'))
          this.desktopFilterItem(4, 2, $r('sys.symbol.clock'), $r('app.string.desktop_yesterday'))
          this.desktopFilterItem(4, 3, $r('sys.symbol.clock'), $r('app.string.desktop_recent'))
          this.desktopFilterItem(4, 4, $r('sys.symbol.clock'), $r('app.string.desktop_last_30_days'))
          this.desktopFilterItem(4, 5, $r('sys.symbol.clock'), $r('app.string.desktop_this_week'))
          this.desktopFilterItem(4, 6, $r('sys.symbol.clock'), $r('app.string.desktop_this_month'))
          this.desktopFilterSectionLabel($r('app.string.desktop_extensions'))
          this.desktopExtensionFilterItem('txt', $r('app.string.desktop_extension_txt'))
          this.desktopExtensionFilterItem('md', $r('app.string.desktop_extension_md'))
          this.desktopExtensionFilterItem('jpg', $r('app.string.desktop_extension_jpg'))
          this.desktopExtensionFilterItem('png', $r('app.string.desktop_extension_png'))
          this.desktopExtensionFilterItem('pdf', $r('app.string.desktop_extension_pdf'))
          this.desktopExtensionFilterItem('ts', $r('app.string.desktop_extension_ts'))
          this.desktopExtensionFilterItem('js', $r('app.string.desktop_extension_js'))
          this.desktopExtensionFilterItem('json', $r('app.string.desktop_extension_json'))
          this.desktopExtensionFilterItem('rs', $r('app.string.desktop_extension_rs'))
          this.desktopExtensionFilterItem('go', $r('app.string.desktop_extension_go'))
        }
        .width('100%')
        .padding({ left: 10, right: 10, top: 16, bottom: 16 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      Row({ space: 8 }) {
        Row()
          .width(8)
          .height(8)
          .borderRadius(4)
          .backgroundColor(this.spacePeerConnected ? $r('app.color.success') :
            $r('app.color.text_secondary'))
        Text(this.spaceJoined ?
          (this.spacePeerConnected ? $r('app.string.space_peer_online') :
            $r('app.string.space_peer_waiting')) : $r('app.string.status_offline'))
          .fontSize($r('app.float.font_body_small'))
          .maxLines(2)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .padding({ left: 24, right: 20, top: 10, bottom: 12 })
      .border({ width: { top: 1 }, color: $r('app.color.divider') })
    }
    .width(248)
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .border({ width: { right: 1 }, color: $r('app.color.divider') })
  }

  @Builder
  private desktopServerHistoryRow(item: ServerHistoryItem) {
    Column({ space: 7 }) {
      Row() {
        Row({ space: 7 }) {
          SymbolGlyph(item.kind === 'Image' ? $r('sys.symbol.ohos_photo') : $r('sys.symbol.doc_text'))
            .fontSize($r('app.float.font_body_large'))
            .fontColor([item.kind === 'Image' ? $r('app.color.success') : $r('app.color.text_secondary')])
          Text(item.kind)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          if (item.starred) {
            Text('★')
              .fontSize(12)
              .fontColor(this.accentColor())
          }
        }
        Blank()
        Text(item.time)
          .fontSize($r('app.float.font_body_small'))
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      Text(item.text)
        .fontSize($r('app.float.font_body_large'))
        .lineHeight(21)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .fontColor($r('app.color.text_primary'))
        .width('100%')
    }
    .width('100%')
    .height(94)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 18, right: 18 })
    .backgroundColor(this.desktopSelectedId === item.id ? this.accentSoftColor() :
      $r('app.color.surface'))
    .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
    .clickEffect({ level: ClickEffectLevel.MIDDLE })
    .bindContextMenu(this.historyServerContextMenu(item), ResponseType.LongPress)
    .onClick((): void => {
      this.selectDesktopServerItem(item);
    })
  }

  @Builder
  private desktopSessionHistoryRow(item: ClipboardHistoryItem) {
    Row({ space: 12 }) {
      if (item.kind === 'Image' && item.imagePreview !== null) {
        Image(item.imagePreview)
          .id('history-image-' + item.id)
          .width(64)
          .height(64)
          .objectFit(ImageFit.Cover)
          .borderRadius($r('app.float.corner_radius_level4'))
          .backgroundColor($r('app.color.surface_muted'))
      }
      Column({ space: 7 }) {
        Row() {
          Text(item.direction === 'sent' ? $r('app.string.direction_sent') :
            $r('app.string.direction_received'))
            .fontSize(12)
            .fontColor(item.direction === 'sent' ? this.accentColor() : $r('app.color.success'))
          if (item.starred) {
            Text('★')
              .fontSize(12)
              .fontColor(this.accentColor())
          }
          Blank()
          Text(item.time)
            .fontSize($r('app.float.font_body_small'))
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        Text(item.text)
          .fontSize($r('app.float.font_body_large'))
          .lineHeight(21)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor($r('app.color.text_primary'))
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(94)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 18, right: 18 })
    .backgroundColor(this.desktopSelectedId === item.id ? this.accentSoftColor() :
      $r('app.color.surface'))
    .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
    .clickEffect({ level: ClickEffectLevel.MIDDLE })
    .bindContextMenu(this.historyLocalContextMenu(item), ResponseType.LongPress)
    .onClick((): void => {
      this.selectDesktopSessionItem(item);
    })
  }

  @Builder
  private desktopClipboardList(listWidth: number) {
    Column() {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor([$r('app.color.text_secondary')])
        TextInput({ placeholder: $r('app.string.server_history_search_placeholder'),
          text: this.historySearchText })
          .layoutWeight(1)
          .height(42)
          .fontSize(14)
          .backgroundColor(Color.Transparent)
          .onChange((value: string): void => {
            this.scheduleDesktopHistorySearch(value);
          })
          .onSubmit((): void => {
            this.submitDesktopHistorySearch();
          })
        Row({ space: 4 }) {
          Text((this.desktopFilteredServerHistory().length +
            this.desktopFilteredSessionHistory().length).toString())
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          Text($r('app.string.desktop_items'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
      }
      .height(44)
      .width('100%')
      .padding({ left: 16, right: 16 })
      .margin({ left: 16, right: 16, top: 14, bottom: 14 })
      .borderRadius($r('app.float.corner_radius_level10'))
      .backgroundColor($r('app.color.surface_muted'))
      Scroll() {
        Column() {
          if (this.desktopFilteredServerHistory().length === 0 &&
            this.desktopFilteredSessionHistory().length === 0) {
            Column({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.clipboard_sharing'))
                .fontSize(38)
                .fontColor([$r('app.color.text_secondary')])
              Text(this.desktopAllFiltersClear() && this.historySearchText.trim().length === 0 ?
                $r('app.string.server_history_empty') : $r('app.string.desktop_filtered_empty'))
                .fontSize(14)
                .textAlign(TextAlign.Center)
                .fontColor($r('app.color.text_secondary'))
              Button($r('app.string.server_history_refresh'), { type: ButtonType.Normal })
                .fontColor($r('app.color.text_primary'))
                .backgroundColor($r('app.color.surface_muted'))
                .borderRadius($r('app.float.corner_radius_level10'))
                .enabled(!this.desktopRefreshBusy)
                .onClick((): void => {
                  this.refreshDesktopMessages();
                })
            }
            .width('100%')
            .padding({ top: 70, left: 24, right: 24 })
          } else {
            ForEach(this.desktopFilteredServerHistory(), (item: ServerHistoryItem) => {
              this.desktopServerHistoryRow(item)
            }, (item: ServerHistoryItem) => item.id)
            ForEach(this.desktopFilteredSessionHistory(), (item: ClipboardHistoryItem) => {
              this.desktopSessionHistoryRow(item)
            }, (item: ClipboardHistoryItem) => item.id)
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
    }
    .width(listWidth)
    .height('100%')
    .backgroundColor($r('app.color.surface'))
    .border({ width: { right: 1 }, color: $r('app.color.divider') })
  }

  @Builder
  private desktopImageComposer() {
    Row({ space: 10 }) {
      if (this.composerImage !== null) {
        Image(this.composerImage)
          .id('desktop-composer-image-' + this.composerImageRevision.toString())
          .width(46)
          .height(46)
          .objectFit(ImageFit.Cover)
          .borderRadius($r('app.float.corner_radius_level4'))
      } else {
        SymbolGlyph($r('sys.symbol.ohos_photo'))
          .fontSize(26)
          .fontColor([$r('app.color.text_secondary')])
          .width(46)
      }
      Column({ space: 3 }) {
        Text($r('app.string.image_composer_title'))
          .fontSize($r('app.float.font_body_medium'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        if (this.imageSendState === 1) {
          Text($r('app.string.image_sending'))
            .fontSize($r('app.float.font_body_small'))
            .fontColor($r('app.color.text_secondary'))
        } else if (this.imageSendState === 2) {
          Text($r('app.string.image_send_success'))
            .fontSize($r('app.float.font_body_small'))
            .fontColor($r('app.color.success'))
        } else if (this.imageSendState === 3) {
          Text($r('app.string.image_send_failed'))
            .fontSize($r('app.float.font_body_small'))
            .fontColor($r('app.color.danger'))
        } else if (this.imageReadState === 2) {
          Text($r('app.string.image_read_success'))
            .fontSize($r('app.float.font_body_small'))
            .fontColor($r('app.color.success'))
        } else {
          Text($r('app.string.image_empty'))
            .fontSize($r('app.float.font_body_small'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontColor($r('app.color.text_secondary'))
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      PasteButton({
        icon: PasteIconStyle.LINES,
        text: PasteDescription.PASTE,
        buttonType: ButtonType.Normal
      })
        .height(40)
        .fontSize($r('app.float.font_body_medium'))
        .fontColor($r('app.color.text_primary'))
        .iconColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.paste_button_background'))
        .borderRadius($r('app.float.corner_radius_level10'))
        .enabled(!this.busy && this.imageReadState !== 1)
        .onClick((_event: ClickEvent, result: PasteButtonOnClickResult): void => {
          if (result === PasteButtonOnClickResult.SUCCESS) {
            this.readLocalImage();
          } else {
            this.imageReadState = 4;
            this.statusCode = 3;
          }
        })
      Button(this.imageSendState === 1 ? $r('app.string.image_sending') :
        $r('app.string.send_image_action'), { type: ButtonType.Normal })
        .height(40)
        .fontSize($r('app.float.font_body_medium'))
        .fontColor($r('app.color.on_accent'))
        .backgroundColor(this.accentColor())
        .borderRadius($r('app.float.corner_radius_level10'))
        .enabled(!this.busy && this.composerImage !== null)
        .onClick((): void => {
          this.sendImage();
        })
    }
    .width('100%')
    .height(54)
  }

  @Builder
  private compactFileComposer() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.folder'))
          .fontSize(26)
          .fontColor([$r('app.color.text_secondary')])
          .width(46)
        Column({ space: 3 }) {
          Text($r('app.string.file_composer_title'))
            .fontSize($r('app.float.font_body_medium'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          if (this.fileTransferState === 1) {
            Text($r('app.string.file_selecting'))
              .fontSize($r('app.float.font_body_small'))
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          } else if (this.fileTransferState === 2) {
            Text(this.composerFileName)
              .fontSize($r('app.float.font_body_small'))
              .fontColor($r('app.color.success'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          } else if (this.fileTransferState === 3) {
            Text($r('app.string.file_sending'))
              .fontSize($r('app.float.font_body_small'))
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          } else if (this.fileTransferState === 4) {
            Text($r('app.string.file_send_failed'))
              .fontSize($r('app.float.font_body_small'))
              .fontColor($r('app.color.danger'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          } else if (this.fileTransferState === 5) {
            Text($r('app.string.file_too_large'))
              .fontSize($r('app.float.font_body_small'))
              .fontColor($r('app.color.danger'))
              .width('100%')
          } else if (this.fileTransferState === 6) {
            Text($r('app.string.file_send_success'))
              .fontSize($r('app.float.font_body_small'))
              .fontColor($r('app.color.success'))
              .width('100%')
          } else if (this.fileTransferState === 7) {
            Text($r('app.string.file_send_pending'))
              .fontSize($r('app.float.font_body_small'))
              .fontColor($r('app.color.text_secondary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          } else {
            Text($r('app.string.file_empty'))
              .fontSize($r('app.float.font_body_small'))
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      Row({ space: 10 }) {
        Button(this.fileTransferState === 1 ? $r('app.string.file_selecting') :
          $r('app.string.select_file_action'), { type: ButtonType.Normal })
          .layoutWeight(1)
          .height(46)
          .fontSize($r('app.float.font_body_medium'))
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.corner_radius_level10'))
          .enabled(!this.busy && this.fileTransferState !== 1)
          .onClick((): void => {
            this.selectFile();
          })
        Button(this.fileTransferState === 3 ? $r('app.string.file_sending') :
          $r('app.string.send_file_action'), { type: ButtonType.Normal })
          .layoutWeight(1)
          .height(46)
          .fontSize($r('app.float.font_body_medium'))
          .fontColor($r('app.color.on_accent'))
          .backgroundColor(this.accentColor())
          .borderRadius($r('app.float.corner_radius_level10'))
          .enabled(!this.busy && this.composerFileUri.length > 0 && this.spaceJoined)
          .onClick((): void => {
            this.sendFile();
          })
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private fileComposer() {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.folder'))
        .fontSize(26)
        .fontColor([$r('app.color.text_secondary')])
        .width(46)
      Column({ space: 3 }) {
        Text($r('app.string.file_composer_title'))
          .fontSize($r('app.float.font_body_medium'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        if (this.fileTransferState === 1) {
          Text($r('app.string.file_selecting')).fontSize($r('app.float.font_body_small')).fontColor($r('app.color.text_secondary'))
        } else if (this.fileTransferState === 2) {
          Text(this.composerFileName).fontSize($r('app.float.font_body_small')).fontColor($r('app.color.success')).maxLines(1)
        } else if (this.fileTransferState === 3) {
          Text($r('app.string.file_sending')).fontSize($r('app.float.font_body_small')).fontColor($r('app.color.text_secondary'))
        } else if (this.fileTransferState === 4) {
          Text($r('app.string.file_send_failed')).fontSize($r('app.float.font_body_small')).fontColor($r('app.color.danger')).maxLines(1)
        } else if (this.fileTransferState === 5) {
          Text($r('app.string.file_too_large')).fontSize($r('app.float.font_body_small')).fontColor($r('app.color.danger'))
        } else if (this.fileTransferState === 6) {
          Text($r('app.string.file_send_success')).fontSize($r('app.float.font_body_small')).fontColor($r('app.color.success'))
        } else if (this.fileTransferState === 7) {
          Text($r('app.string.file_send_pending')).fontSize($r('app.float.font_body_small')).fontColor($r('app.color.text_secondary'))
        } else {
          Text($r('app.string.file_empty')).fontSize($r('app.float.font_body_small')).fontColor($r('app.color.text_secondary')).maxLines(1)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Button(this.fileTransferState === 1 ? $r('app.string.file_selecting') :
        $r('app.string.select_file_action'), { type: ButtonType.Normal })
        .height(40)
        .fontSize($r('app.float.font_body_medium'))
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius($r('app.float.corner_radius_level10'))
        .enabled(!this.busy && this.fileTransferState !== 1)
        .onClick((): void => {
          this.selectFile();
        })
      Button(this.fileTransferState === 3 ? $r('app.string.file_sending') :
        $r('app.string.send_file_action'), { type: ButtonType.Normal })
        .height(40)
        .fontSize($r('app.float.font_body_medium'))
        .fontColor($r('app.color.on_accent'))
        .backgroundColor(this.accentColor())
        .borderRadius($r('app.float.corner_radius_level10'))
        .enabled(!this.busy && this.composerFileUri.length > 0 && this.spaceJoined)
        .onClick((): void => {
          this.sendFile();
        })
    }
    .width('100%')
    .height(54)
  }

  @Builder
  private desktopAudioPreview() {
    Column({ space: 16 }) {
      if (this.desktopAudioCover !== null) {
        Image(this.desktopAudioCover)
          .id('desktop-audio-cover-' + this.desktopAudioCoverRevision.toString())
          .width(200)
          .aspectRatio(1)
          .objectFit(ImageFit.Cover)
          .borderRadius($r('app.float.corner_radius_level8'))
      } else {
        SymbolGlyph($r('sys.symbol.music'))
          .fontSize(58)
          .fontColor([this.accentColor()])
      }
      Text(this.desktopAudioDisplayTitle())
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Center)
      if (this.desktopAudioDisplayArtist().length > 0) {
        Text(this.desktopAudioDisplayArtist())
          .fontSize($r('app.float.font_body_medium'))
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
      }
      Slider({
        value: this.desktopAudioPosition,
        min: 0,
        max: this.desktopAudioDuration > 0 ? this.desktopAudioDuration : 1,
        step: 100,
        style: SliderStyle.OutSet
      })
        .width('100%')
        .selectedColor(this.accentColor())
        .enabled(this.desktopAudioDuration > 0 && this.desktopAudioState !== 5)
        .onChange((value: number, mode: SliderChangeMode): void => {
          this.desktopAudioPosition = value;
          if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
            this.desktopAudioSeeking = true;
          } else {
            this.desktopAudioSeeking = false;
            this.seekDesktopAudio(value);
          }
        })
      Row() {
        Text(this.formatAudioTime(this.desktopAudioPosition))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Text(this.formatAudioTime(this.desktopAudioDuration))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      Button(this.desktopAudioState === 3 ? $r('app.string.audio_pause_action') :
        $r('app.string.audio_play_action'), { type: ButtonType.Normal })
        .height(42)
        .fontColor($r('app.color.on_accent'))
        .backgroundColor(this.accentColor())
        .borderRadius($r('app.float.corner_radius_level10'))
        .enabled(this.desktopAudioState !== 1 && this.desktopAudioState !== 5 &&
          this.desktopFileSourcePath().length > 0)
        .onClick((): void => {
          this.toggleDesktopAudioPlayback();
        })
      if (this.desktopAudioState === 1) {
        Text($r('app.string.audio_preparing'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      } else if (this.desktopAudioState === 5) {
        Text($r('app.string.audio_play_failed'))
          .fontSize(12)
          .fontColor($r('app.color.danger'))
      }
      Divider()
        .color($r('app.color.divider'))
      Text($r('app.string.audio_lyrics_title'))
        .width('100%')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      if (this.desktopAudioLyrics.length > 0) {
        Column({ space: 10 }) {
          Text(this.desktopLyricTextAtOffset(-1))
            .fontSize($r('app.float.font_body_medium'))
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
          Text(this.desktopLyricTextAtOffset(0))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.accentColor())
            .textAlign(TextAlign.Center)
          Text(this.desktopLyricTextAtOffset(1))
            .fontSize($r('app.float.font_body_medium'))
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .height(104)
        .justifyContent(FlexAlign.Center)
      } else if (this.desktopAudioPlainLyrics.length > 0) {
        Scroll() {
          Text(this.desktopAudioPlainLyrics)
            .width('100%')
            .fontSize($r('app.float.font_body_medium'))
            .lineHeight(22)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .height(140)
        .scrollBar(BarState.Auto)
      } else if (this.desktopAudioMetadataState === 1) {
        Text($r('app.string.audio_metadata_loading'))
          .fontSize($r('app.float.font_body_medium'))
          .fontColor($r('app.color.text_secondary'))
      } else {
        Text($r('app.string.audio_lyrics_unavailable'))
          .fontSize($r('app.float.font_body_medium'))
          .fontColor($r('app.color.text_secondary'))
      }
    }
    .id('desktop-audio-player-' + this.desktopFilePreviewKey())
    .width('100%')
    .padding(24)
    .borderRadius($r('app.float.corner_radius_level8'))
    .backgroundColor($r('app.color.surface_muted'))
    .onAppear((): void => {
      this.prepareDesktopAudio();
    })
  }

  private desktopGestureShareMessage(): Resource {
    if (this.desktopGestureShareState === 2) {
      return $r('app.string.gesture_share_sending');
    }
    if (this.desktopGestureShareState === 3) {
      return $r('app.string.gesture_share_success');
    }
    if (this.desktopGestureShareState === 4) {
      return $r('app.string.gesture_share_failed');
    }
    if (this.desktopGestureShareState === 5) {
      return $r('app.string.gesture_share_unsupported');
    }
    if (this.desktopGestureShareState !== 1) {
      return $r('app.string.gesture_share_preparing');
    }
    let contentKind: number = this.desktopGestureShareContentKind();
    if (contentKind === 2 || contentKind === 4) {
      return $r('app.string.gesture_share_ready_image');
    }
    if (contentKind === 5) {
      return $r('app.string.gesture_share_ready_video');
    }
    if (contentKind === 6) {
      return $r('app.string.gesture_share_ready_audio');
    }
    if (contentKind === 7) {
      return $r('app.string.gesture_share_ready_pdf');
    }
    if (contentKind === 8) {
      return $r('app.string.gesture_share_ready_archive');
    }
    if (contentKind === 9) {
      return $r('app.string.gesture_share_ready_word');
    }
    if (contentKind === 10) {
      return $r('app.string.gesture_share_ready_excel');
    }
    if (contentKind === 11) {
      return $r('app.string.gesture_share_ready_ppt');
    }
    if (contentKind === 12) {
      return $r('app.string.gesture_share_ready_document');
    }
    if (contentKind === 1) {
      return $r('app.string.gesture_share_ready');
    }
    return $r('app.string.gesture_share_ready_text');
  }

  @Builder
  private desktopGestureShareHint() {
    Row({ space: 8 }) {
      if (this.desktopGestureShareContentKind() === 2 || this.desktopGestureShareContentKind() === 4) {
        SymbolGlyph($r('sys.symbol.ohos_photo'))
          .fontSize(26)
          .fontColor([this.desktopGestureShareState === 4 || this.desktopGestureShareState === 5 ?
            $r('app.color.text_secondary') : this.accentColor()])
      } else if (this.desktopGestureShareContentKind() === 5) {
        SymbolGlyph($r('sys.symbol.video'))
          .fontSize(26)
          .fontColor([this.desktopGestureShareState === 4 || this.desktopGestureShareState === 5 ?
            $r('app.color.text_secondary') : this.accentColor()])
      } else if (this.desktopGestureShareContentKind() === 6) {
        SymbolGlyph($r('sys.symbol.music'))
          .fontSize(26)
          .fontColor([this.desktopGestureShareState === 4 || this.desktopGestureShareState === 5 ?
            $r('app.color.text_secondary') : this.accentColor()])
      } else if (this.desktopGestureShareContentKind() === 8) {
        SymbolGlyph($r('sys.symbol.doc_zipper'))
          .fontSize(26)
          .fontColor([this.desktopGestureShareState === 4 || this.desktopGestureShareState === 5 ?
            $r('app.color.text_secondary') : this.accentColor()])
      } else if (this.desktopGestureShareContentKind() === 7) {
        SymbolGlyph($r('sys.symbol.pdf_doc'))
          .fontSize(26)
          .fontColor([this.desktopGestureShareState === 4 || this.desktopGestureShareState === 5 ?
            $r('app.color.text_secondary') : this.accentColor()])
      } else if (this.desktopGestureShareContentKind() === 9) {
        SymbolGlyph($r('sys.symbol.word_book'))
          .fontSize(26)
          .fontColor([this.desktopGestureShareState === 4 || this.desktopGestureShareState === 5 ?
            $r('app.color.text_secondary') : this.accentColor()])
      } else if (this.desktopGestureShareContentKind() === 10) {
        SymbolGlyph($r('sys.symbol.grid'))
          .fontSize(26)
          .fontColor([this.desktopGestureShareState === 4 || this.desktopGestureShareState === 5 ?
            $r('app.color.text_secondary') : this.accentColor()])
      } else if (this.desktopGestureShareContentKind() === 11) {
        SymbolGlyph($r('sys.symbol.play_round_rectangle'))
          .fontSize(26)
          .fontColor([this.desktopGestureShareState === 4 || this.desktopGestureShareState === 5 ?
            $r('app.color.text_secondary') : this.accentColor()])
      } else if (this.desktopGestureShareContentKind() === 1 || this.desktopGestureShareContentKind() === 12) {
        SymbolGlyph($r('sys.symbol.doc_text'))
          .fontSize(26)
          .fontColor([this.desktopGestureShareState === 4 || this.desktopGestureShareState === 5 ?
            $r('app.color.text_secondary') : this.accentColor()])
      } else {
        SymbolGlyph($r('sys.symbol.text_alignleft'))
          .fontSize(26)
          .fontColor([this.desktopGestureShareState === 4 || this.desktopGestureShareState === 5 ?
            $r('app.color.text_secondary') : this.accentColor()])
      }
      Column({ space: 3 }) {
        Text($r('app.string.gesture_share_title'))
          .width('100%')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(this.desktopGestureShareMessage())
          .width('100%')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
      }
      .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor([$r('app.color.text_secondary')])
        .width(32)
        .height(32)
        .padding(7)
        .borderRadius($r('app.float.corner_radius_level10'))
        .backgroundColor($r('app.color.surface_muted'))
        .onClick((): void => {
          this.desktopGestureShareHintDismissed = true;
        })
    }
    .width('100%')
    .padding({ left: 12, right: 8, top: 8, bottom: 8 })
    .borderRadius($r('app.float.corner_radius_level8'))
    .backgroundColor(this.accentSoftColor())
  }

  @Builder
  private desktopClipboardDetail() {
    Column() {
      Row() {
        Column({ space: 3 }) {
          Row({ space: 8 }) {
            if (this.desktopSelectedDirection.length > 0) {
              SymbolGlyph(this.desktopSelectedDirection === 'sent' ?
                $r('sys.symbol.arrowshape_up_to_line_fill') :
                $r('sys.symbol.arrowshape_down_to_line_fill'))
                .fontSize(18)
                .fontWeight(FontWeight.Medium)
                .fontColor([this.desktopSelectedDirection === 'sent' ?
                  this.accentColor() : $r('app.color.success')])
            }
            Text(this.desktopSelectedMeta.length > 0 ? this.desktopSelectedMeta :
              $r('app.string.latest_title'))
              .fontSize($r('app.float.font_body_medium'))
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          Text(this.desktopShowsLatestImage() ? $r('app.string.desktop_images') :
            (this.desktopShowsFile() ? $r('app.string.desktop_files') :
              (this.desktopDetailText().length > 0 ? $r('app.string.desktop_text') :
                $r('app.string.latest_empty'))))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        this.statusPill()
      }
      .height(84)
      .width('100%')
      .padding({ left: 32, right: 32 })
      .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
      Scroll() {
        if (this.desktopShowsLatestImage()) {
          Column({ space: 12 }) {
            if (!this.desktopGestureShareHintDismissed) {
              this.desktopGestureShareHint()
            }
            if (this.desktopSelectedId.length > 0 && this.desktopSelectedImage !== null) {
              if (this.desktopSelectedImageRevision % 2 === 0) {
                Image(this.desktopSelectedImage)
                  .id('desktop-selected-image-even')
                  .width('100%')
                  .aspectRatio(this.desktopImageAspectRatio())
                  .constraintSize({ maxHeight: 520 })
                  .objectFit(ImageFit.Contain)
                  .borderRadius($r('app.float.corner_radius_level4'))
                  .backgroundColor($r('app.color.surface_muted'))
              } else {
                Image(this.desktopSelectedImage)
                  .id('desktop-selected-image-odd')
                  .width('100%')
                  .aspectRatio(this.desktopImageAspectRatio())
                  .constraintSize({ maxHeight: 520 })
                  .objectFit(ImageFit.Contain)
                  .borderRadius($r('app.float.corner_radius_level4'))
                  .backgroundColor($r('app.color.surface_muted'))
              }
            } else if (this.latestImage !== null) {
              if (this.latestImageRevision % 2 === 0) {
                Image(this.latestImage)
                  .id('desktop-latest-image-even')
                  .width('100%')
                  .aspectRatio(this.desktopImageAspectRatio())
                  .constraintSize({ maxHeight: 520 })
                  .objectFit(ImageFit.Contain)
                  .borderRadius($r('app.float.corner_radius_level4'))
                  .backgroundColor($r('app.color.surface_muted'))
              } else {
                Image(this.latestImage)
                  .id('desktop-latest-image-odd')
                  .width('100%')
                  .aspectRatio(this.desktopImageAspectRatio())
                  .constraintSize({ maxHeight: 520 })
                  .objectFit(ImageFit.Contain)
                  .borderRadius($r('app.float.corner_radius_level4'))
                  .backgroundColor($r('app.color.surface_muted'))
              }
            }
            Text(this.desktopDetailText())
              .fontSize($r('app.float.font_body_medium'))
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          }
          .width('100%')
          .padding(this.isLargeScreen ? 40 : 24)
        } else if (this.desktopShowsFile()) {
          Column({ space: 16 }) {
            if (!this.desktopGestureShareHintDismissed) {
              this.desktopGestureShareHint()
            }
            if (this.desktopFileIsVideo() && this.desktopFilePreviewUri().length > 0) {
              Video({ src: this.desktopFilePreviewUri() })
                .id('desktop-file-video-' + this.desktopFilePreviewKey())
                .width('100%')
                .aspectRatio(this.desktopVideoAspectRatio)
                .constraintSize({ maxHeight: 520 })
                .controls(true)
                .autoPlay(true)
                .objectFit(ImageFit.Contain)
                .borderRadius($r('app.float.corner_radius_level4'))
                .backgroundColor(Color.Black)
                .onPrepared((_preparedInfo: PreparedInfo): void => {
                  this.loadDesktopVideoAspectRatio();
                })
                .onError((): void => {
                  this.desktopFilePreviewState = 2;
                })
            } else if (this.desktopFileIsAudio()) {
              this.desktopAudioPreview()
            } else {
              Column({ space: 14 }) {
                SymbolGlyph($r('sys.symbol.doc_text'))
                  .fontSize(54)
                  .fontColor([this.accentColor()])
                Text(this.desktopFileIsAudio() ? $r('app.string.file_preview_audio') :
                  (this.desktopFileIsDocument() ? $r('app.string.file_preview_document') :
                    $r('app.string.file_preview_generic')))
                  .fontSize(18)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                Text($r('app.string.file_preview_system_note'))
                  .fontSize($r('app.float.font_body_medium'))
                  .lineHeight(20)
                  .textAlign(TextAlign.Center)
                  .fontColor($r('app.color.text_secondary'))
                  .maxLines(3)
              }
              .width('100%')
              .height(220)
              .justifyContent(FlexAlign.Center)
              .padding({ left: 24, right: 24 })
              .borderRadius($r('app.float.corner_radius_level8'))
              .backgroundColor($r('app.color.surface_muted'))
            }
            Text(this.desktopFileName())
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            if (this.desktopFileIsVideo()) {
              Text($r('app.string.file_preview_video'))
                .fontSize($r('app.float.font_body_medium'))
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
            }
            Row({ space: 12 }) {
              Button(this.desktopFilePreviewState === 1 ? $r('app.string.file_preview_opening') :
                $r('app.string.file_preview_action'), { type: ButtonType.Normal })
                .height(40)
                .fontColor($r('app.color.on_accent'))
                .backgroundColor(this.accentColor())
                .borderRadius($r('app.float.corner_radius_level10'))
                .enabled(this.desktopFilePreviewUri().length > 0 && this.desktopFilePreviewState !== 1)
                .onClick((): void => {
                  this.openDesktopFilePreview();
                })
              if (this.desktopFilePreviewState === 2) {
                Text($r('app.string.file_preview_failed'))
                  .fontSize(12)
                  .fontColor($r('app.color.danger'))
                  .maxLines(2)
              }
            }
            .width('100%')
          }
          .width('100%')
          .padding(this.isLargeScreen ? 40 : 24)
        } else if (this.desktopDetailText().length > 0) {
          Column({ space: 16 }) {
            if (!this.desktopGestureShareHintDismissed) {
              this.desktopGestureShareHint()
            }
            Text(this.desktopDetailText())
              .fontSize(18)
              .lineHeight(28)
              .fontColor($r('app.color.text_primary'))
              .width('100%')
          }
            .width('100%')
            .padding(this.isLargeScreen ? 40 : 24)
        } else {
          Text($r('app.string.latest_empty'))
            .fontSize(18)
            .lineHeight(28)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .padding(this.isLargeScreen ? 40 : 24)
        }
      }
      .layoutWeight(1)
      .width('100%')
      Column({ space: 10 }) {
        this.desktopImageComposer()
        this.fileComposer()
        TextArea({ placeholder: $r('app.string.composer_placeholder'), text: this.composerText })
          .height(84)
          .fontSize(14)
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.corner_radius_level8'))
          .onChange((value: string): void => {
            this.composerText = value;
          })
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            Row() {
              PasteButton({
                icon: PasteIconStyle.LINES,
                text: PasteDescription.PASTE,
                buttonType: ButtonType.Normal
              })
                .width('100%')
                .height(40)
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
                .iconColor($r('app.color.text_primary'))
                .backgroundColor($r('app.color.paste_button_background'))
                .borderRadius($r('app.float.corner_radius_level10'))
                .enabled(!this.busy)
                .onClick((_event: ClickEvent, result: PasteButtonOnClickResult): void => {
                  if (result === PasteButtonOnClickResult.SUCCESS) {
                    this.readLocalClipboard();
                  } else {
                    this.statusCode = 3;
                  }
                })
            }
            .layoutWeight(1)
            Button(!this.hasConfig() && this.spaceJoined ? $r('app.string.space_refresh_sync_action') :
              $r('app.string.pull_action'), { type: ButtonType.Normal })
              .height(40)
              .fontSize(14)
              .fontColor($r('app.color.on_accent'))
              .backgroundColor(this.accentColor())
              .borderRadius($r('app.float.corner_radius_level10'))
              .layoutWeight(1)
              .enabled(!this.busy)
              .onClick((): void => {
                this.pullLatest();
              })
            Button(this.desktopShowsFile() ? $r('app.string.save_file_action') :
              $r('app.string.copy_action'), { type: ButtonType.Normal })
              .height(40)
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
              .backgroundColor($r('app.color.surface_muted'))
              .borderRadius($r('app.float.corner_radius_level10'))
              .layoutWeight(1)
              .enabled(this.desktopShowsLatestImage() || this.desktopShowsFile() ||
                this.desktopDetailText().length > 0)
              .onClick((): void => {
                if (this.desktopShowsFile()) {
                  this.saveSelectedFile();
                } else {
                  this.copyDesktopSelection();
                }
              })
          }
          .width('100%')
          Row({ space: 8 }) {
            Button(this.desktopSelectionStarred() ? $r('app.string.history_unstar_action') :
              $r('app.string.history_star_action'), { type: ButtonType.Normal })
              .height(40)
              .fontSize(14)
              .fontColor(this.desktopSelectionStarred() ? this.accentColor() :
                $r('app.color.text_primary'))
              .backgroundColor($r('app.color.surface_muted'))
              .borderRadius($r('app.float.corner_radius_level10'))
              .layoutWeight(1)
              .enabled(this.desktopSelectedId.length > 0)
              .onClick((): void => {
                this.toggleDesktopSelectedStar();
              })
            Button($r('app.string.history_delete_action'), { type: ButtonType.Normal })
              .height(40)
              .fontSize(14)
              .fontColor($r('app.color.danger'))
              .backgroundColor($r('app.color.surface_muted'))
              .borderRadius($r('app.float.corner_radius_level10'))
              .layoutWeight(1)
              .enabled(this.desktopSelectedId.length > 0)
              .onClick((): void => {
                this.deleteDesktopSelection();
              })
            Button($r('app.string.send_action'), { type: ButtonType.Normal })
              .height(40)
              .fontSize(14)
              .fontColor($r('app.color.on_accent'))
              .backgroundColor(this.accentColor())
              .borderRadius($r('app.float.corner_radius_level10'))
              .layoutWeight(1)
              .enabled(!this.busy && this.composerText.trim().length > 0)
              .onClick((): void => {
                this.sendText();
              })
          }
          .width('100%')
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 14, bottom: 18 })
      .border({ width: { top: 1 }, color: $r('app.color.divider') })
    }
    .layoutWeight(1)
    .height('100%')
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  private desktopClipboardWorkspace() {
    this.desktopClipboardFallback()
  }

  @Builder
  private desktopClipboardFallback() {
    Row() {
      this.desktopClipboardFilters()
      this.desktopClipboardList(430)
      this.desktopClipboardDetail()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private tabletClipboardWorkspace() {
    Row() {
      this.desktopClipboardList(300)
      this.desktopClipboardDetail()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private spaceModeButton(mode: number, label: Resource) {
    Button(label, { type: ButtonType.Normal })
      .layoutWeight(1)
      .height(38)
      .fontSize($r('app.float.font_body_medium'))
      .fontColor(this.spaceActionMode === mode ? $r('app.color.text_primary') :
        $r('app.color.text_secondary'))
      .backgroundColor(this.spaceActionMode === mode ? this.accentSoftColor() : Color.Transparent)
      .borderRadius($r('app.float.corner_radius_level10'))
      .onClick((): void => {
        this.spaceActionMode = mode;
        this.spaceCreateState = 0;
        this.spaceJoinState = 0;
      })
  }

  @Builder
  private desktopCreateSpaceForm() {
    Column({ space: 10 }) {
      Text(this.spaceJoined ? $r('app.string.space_create_new_title') :
        $r('app.string.space_create_title'))
        .fontSize($r('app.float.font_body_large'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Text(this.spaceJoined ? $r('app.string.space_create_new_note') :
        $r('app.string.space_create_note'))
        .fontSize($r('app.float.font_body_small'))
        .lineHeight(17)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      TextInput({ placeholder: $r('app.string.space_create_device_placeholder'),
        text: this.spaceCreateDeviceName })
        .height(44)
        .fontColor(this.spaceCreateDeviceNameRecommended ? $r('app.color.text_secondary') :
          $r('app.color.text_primary'))
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius($r('app.float.corner_radius_level10'))
        .onFocus((): void => {
          this.spaceCreateDeviceNameRecommended = false;
        })
        .onChange((value: string): void => {
          this.spaceCreateDeviceName = value;
          this.spaceCreateDeviceNameRecommended = false;
          this.spaceCreateState = 0;
        })
      TextInput({ placeholder: $r('app.string.space_passphrase_placeholder'),
        text: this.spaceCreatePassphrase })
        .type(InputType.Password)
        .height(44)
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius($r('app.float.corner_radius_level10'))
        .onChange((value: string): void => {
          this.spaceCreatePassphrase = value;
          this.spaceCreateState = 0;
        })
      TextInput({ placeholder: $r('app.string.space_create_confirm_placeholder'),
        text: this.spaceCreatePassphraseConfirm })
        .type(InputType.Password)
        .height(44)
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius($r('app.float.corner_radius_level10'))
        .onChange((value: string): void => {
          this.spaceCreatePassphraseConfirm = value;
          this.spaceCreateState = 0;
        })
      Text($r('app.string.space_create_requirement'))
        .fontSize(10)
        .lineHeight(15)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      if (this.spaceCreateState === 2) {
        Text($r('app.string.space_create_failed'))
          .fontSize($r('app.float.font_body_small'))
          .fontColor($r('app.color.danger'))
          .width('100%')
      }
      Button(this.spaceCreateBusy ? $r('app.string.space_creating_action') :
        (this.spaceJoined ? $r('app.string.space_create_new_action') :
          $r('app.string.space_create_action')), { type: ButtonType.Normal })
        .width('100%')
        .height(44)
        .fontColor($r('app.color.on_accent'))
        .backgroundColor(this.accentColor())
        .borderRadius($r('app.float.corner_radius_level10'))
        .enabled(this.canCreateSpace())
        .onClick((): void => {
          this.createCurrentSpace();
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private desktopJoinSpaceForm() {
    Column({ space: 10 }) {
      Text(this.spaceJoined ? $r('app.string.space_switch_note') : $r('app.string.space_join_note'))
        .fontSize($r('app.float.font_body_small'))
        .lineHeight(17)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      Button($r('app.string.space_scan_invitation'), { type: ButtonType.Normal })
        .height(42)
        .width('100%')
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius($r('app.float.corner_radius_level10'))
        .onClick((): void => {
          this.scanSpaceInvitation();
        })
      if (!this.spaceJoined) {
        TextInput({ placeholder: $r('app.string.space_create_device_placeholder'),
          text: this.spaceJoinDeviceName })
          .height(46)
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.corner_radius_level10'))
          .onChange((value: string): void => {
            this.spaceJoinDeviceName = value;
            this.spaceJoinState = 0;
          })
      }
      TextInput({ placeholder: $r('app.string.space_code_placeholder'),
        text: this.spaceInvitationCode })
        .height(46)
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius($r('app.float.corner_radius_level10'))
        .onChange((value: string): void => {
          this.spaceInvitationCode = value.toUpperCase();
          this.spaceJoinState = 0;
        })
      TextInput({ placeholder: $r('app.string.space_passphrase_placeholder'),
        text: this.spacePassphrase })
        .type(InputType.Password)
        .height(46)
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius($r('app.float.corner_radius_level10'))
        .onChange((value: string): void => {
          this.spacePassphrase = value;
          this.spaceJoinState = 0;
        })
      if (this.spaceJoinState === 2) {
        Text(this.spaceJoined ? $r('app.string.space_switch_failed') :
          $r('app.string.space_join_failed'))
          .fontSize($r('app.float.font_body_small'))
          .fontColor($r('app.color.danger'))
          .width('100%')
      }
      Button(this.spaceJoinBusy ?
        (this.spaceJoined ? $r('app.string.space_switching_action') :
          $r('app.string.space_joining_action')) :
        (this.spaceJoined ? $r('app.string.space_switch_action') :
          $r('app.string.space_join_action')), { type: ButtonType.Normal })
        .width('100%')
        .height(44)
        .fontColor($r('app.color.on_accent'))
        .backgroundColor(this.accentColor())
        .borderRadius($r('app.float.corner_radius_level10'))
        .enabled(this.canJoinSpace())
        .onClick((): void => {
          this.joinCurrentSpace();
        })
    }
    .width('100%')
  }

  @Builder
  private spaceInvitationCard() {
    Column({ space: 9 }) {
      Text($r('app.string.space_invitation_title'))
        .fontSize($r('app.float.font_body_medium'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Text($r('app.string.space_qr_note'))
        .fontSize(10)
        .lineHeight(15)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      TextInput({ placeholder: $r('app.string.space_invitation_passphrase_placeholder'),
        text: this.spaceCreatePassphrase })
        .type(InputType.Password)
        .height(40)
        .fontSize(12)
        .backgroundColor($r('app.color.surface'))
        .borderRadius($r('app.float.corner_radius_level4'))
        .onChange((value: string): void => {
          this.spaceCreatePassphrase = value;
          this.spaceCreateState = 0;
          this.spaceIssuedInvitationCode = '';
          this.spaceInvitationExpiresAtMs = 0;
        })
      if (this.buildSpaceInvitationUri().length > 0) {
        Row() {
          QRCode(this.buildSpaceInvitationUri())
            .width(176)
            .height(176)
            .color($r('app.color.qr_foreground'))
            .backgroundColor($r('app.color.qr_background'))
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: 5, bottom: 5 })
        Text($r('app.string.space_invitation_code_label'))
          .fontSize($r('app.float.font_body_small'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text(this.spaceIssuedInvitationCode)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.accentColor())
          .letterSpacing(2)
          .copyOption(CopyOptions.LocalDevice)
          .width('100%')
        Text($r('app.string.space_passphrase_label'))
          .fontSize(10)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        Text(this.spaceCreatePassphrase)
          .fontSize($r('app.float.font_body_medium'))
          .fontColor($r('app.color.text_primary'))
          .copyOption(CopyOptions.LocalDevice)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (this.spaceInvitationExpiresAtMs > 0) {
          Row({ space: 5 }) {
            Text($r('app.string.space_invitation_expires'))
              .fontSize(10)
              .fontColor($r('app.color.text_secondary'))
            Text(this.invitationExpiryText())
              .fontSize(10)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
        }
        Text($r('app.string.space_share_invitation_note'))
          .fontSize($r('app.float.font_caption_medium'))
          .lineHeight(15)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        Button($r('app.string.space_share_invitation_action'), { type: ButtonType.Normal })
          .width('100%')
          .height(42)
          .fontSize($r('app.float.font_body_medium'))
          .fontColor($r('app.color.on_accent'))
          .backgroundColor(this.accentColor())
          .borderRadius($r('app.float.corner_radius_level10'))
          .onClick((): void => {
            this.shareCurrentSpaceInvitation();
          })
      }
      Text(this.spaceCreateState === 3 ? $r('app.string.space_invitation_failed') :
        $r('app.string.space_invitation_note'))
        .fontSize(10)
        .lineHeight(15)
        .fontColor(this.spaceCreateState === 3 ? $r('app.color.danger') :
          $r('app.color.text_secondary'))
        .width('100%')
      Button(this.spaceInvitationBusy ? $r('app.string.space_issuing_invitation') :
        $r('app.string.space_issue_invitation'), { type: ButtonType.Normal })
        .width('100%')
        .height(40)
        .fontSize(12)
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.surface'))
        .borderRadius($r('app.float.corner_radius_level10'))
        .enabled(this.canIssueSpaceInvitation())
        .onClick((): void => {
          this.issueCurrentSpaceInvitation();
        })
    }
    .width('100%')
    .padding(14)
    .borderRadius($r('app.float.corner_radius_level10'))
    .backgroundColor($r('app.color.surface_muted'))
  }

  @Builder
  private desktopDeviceTypeGlyph(deviceType: string) {
    if (deviceType === 'phone') {
      SymbolGlyph($r('sys.symbol.phone'))
        .fontSize(24)
        .fontColor([$r('app.color.text_primary')])
    } else if (deviceType === 'tablet') {
      SymbolGlyph($r('sys.symbol.pad'))
        .fontSize(24)
        .fontColor([$r('app.color.text_primary')])
    } else if (deviceType === 'tv') {
      SymbolGlyph($r('sys.symbol.TV_tv'))
        .fontSize(24)
        .fontColor([$r('app.color.text_primary')])
    } else if (deviceType === 'wearable') {
      SymbolGlyph($r('sys.symbol.watch'))
        .fontSize(24)
        .fontColor([$r('app.color.text_primary')])
    } else if (deviceType === 'car') {
      SymbolGlyph($r('sys.symbol.car'))
        .fontSize(24)
        .fontColor([$r('app.color.text_primary')])
    } else {
      SymbolGlyph($r('sys.symbol.desktop'))
        .fontSize(24)
        .fontColor([$r('app.color.text_primary')])
    }
  }

  @Builder
  private desktopDeviceTypeLabel(deviceType: string) {
    if (deviceType === 'phone') {
      Text($r('app.string.device_type_phone'))
        .fontSize($r('app.float.font_body_small'))
        .fontColor($r('app.color.text_secondary'))
    } else if (deviceType === 'tablet') {
      Text($r('app.string.device_type_tablet'))
        .fontSize($r('app.float.font_body_small'))
        .fontColor($r('app.color.text_secondary'))
    } else if (deviceType === '2in1') {
      Text($r('app.string.device_type_2in1'))
        .fontSize($r('app.float.font_body_small'))
        .fontColor($r('app.color.text_secondary'))
    } else if (deviceType === 'tv') {
      Text($r('app.string.device_type_tv'))
        .fontSize($r('app.float.font_body_small'))
        .fontColor($r('app.color.text_secondary'))
    } else if (deviceType === 'wearable') {
      Text($r('app.string.device_type_wearable'))
        .fontSize($r('app.float.font_body_small'))
        .fontColor($r('app.color.text_secondary'))
    } else if (deviceType === 'car') {
      Text($r('app.string.device_type_car'))
        .fontSize($r('app.float.font_body_small'))
        .fontColor($r('app.color.text_secondary'))
    } else {
      Text($r('app.string.device_type_unknown'))
        .fontSize($r('app.float.font_body_small'))
        .fontColor($r('app.color.text_secondary'))
    }
  }

  @Builder
  private desktopPairedDeviceContextMenu(device: NativeSpaceDevice) {
    Menu() {
      if (device.isLocal) {
        MenuItem({
          content: $r('app.string.desktop_this_device')
        }).enabled(false)
      } else {
        MenuItem({
          symbolStartIcon: this.historyDeleteMenuSymbol(),
          content: $r('app.string.space_revoke_device_confirm')
        })
          .enabled(!this.desktopDeviceMutationBusy)
          .onClick((): void => {
            this.revokeSpaceDevice(device);
          })
      }
    }.menuItemDivider({
      strokeWidth: LengthMetrics.vp(1),
      color: $r('app.color.divider'),
      startMargin: LengthMetrics.vp(12),
      endMargin: LengthMetrics.vp(12)
    })
  }

  @Builder
  private desktopMobileDeviceContextMenu(device: NativeMobileSyncDevice) {
    Menu() {
      MenuItem({
        symbolStartIcon: this.historyDeleteMenuSymbol(),
        content: $r('app.string.mobile_sync_revoke_confirm')
      })
        .enabled(!this.desktopDeviceMutationBusy)
        .onClick((): void => {
          this.revokeMobileSyncDevice(device);
        })
    }.menuItemDivider({
      strokeWidth: LengthMetrics.vp(1),
      color: $r('app.color.divider'),
      startMargin: LengthMetrics.vp(12),
      endMargin: LengthMetrics.vp(12)
    })
  }

  @Builder
  private desktopPairedDeviceRow(device: NativeSpaceDevice) {
    Row({ space: 11 }) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          this.desktopDeviceTypeGlyph(device.deviceType)
        }
        .width(44)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .borderRadius(13)
        .backgroundColor(this.accentSoftColor())
        Row()
          .width(10)
          .height(10)
          .borderRadius(5)
          .backgroundColor(device.online ? $r('app.color.success') : $r('app.color.text_secondary'))
          .border({ width: 2, color: $r('app.color.surface_muted') })
      }
      .width(44)
      .height(44)
      Column({ space: 4 }) {
        Text(device.deviceName)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Row({ space: 8 }) {
          this.desktopDeviceTypeLabel(device.deviceType)
          Text(device.isLocal ? $r('app.string.desktop_this_device') :
            (device.online ? $r('app.string.device_status_online') :
              (device.state === 'unknown' ? $r('app.string.device_status_unknown') :
                $r('app.string.device_status_offline'))))
            .fontSize($r('app.float.font_body_small'))
            .fontColor(device.online ? $r('app.color.success') : $r('app.color.text_secondary'))
        }
      }
      .layoutWeight(1)
      if (!device.isLocal) {
        Button(this.spaceConnectingDeviceId === device.deviceId ?
          $r('app.string.desktop_connecting_device') :
          (device.online ? $r('app.string.desktop_device_connected') :
            $r('app.string.desktop_connect_device')), { type: ButtonType.Normal })
          .height(32)
          .fontSize($r('app.float.font_body_small'))
          .fontColor(device.online ? $r('app.color.success') : $r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface'))
          .borderRadius($r('app.float.corner_radius_level4'))
          .enabled(!device.online && !this.spaceConnectBusy && !this.desktopDeviceMutationBusy)
          .onClick((): void => {
            this.connectSpaceDevice(device);
          })
      }
    }
    .width('100%')
    .height(64)
    .padding({ left: 10, right: 12 })
    .borderRadius($r('app.float.corner_radius_level10'))
    .backgroundColor($r('app.color.surface_muted'))
    .bindContextMenu(this.desktopPairedDeviceContextMenu(device), ResponseType.LongPress)
  }

  @Builder
  private desktopMobileDeviceRow(device: NativeMobileSyncDevice) {
    Row({ space: 11 }) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          SymbolGlyph($r('sys.symbol.phone'))
            .fontSize(24)
            .fontColor([this.accentColor()])
        }
        .width(44)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .borderRadius(13)
        .backgroundColor(this.accentSoftColor())
        Row()
          .width(10)
          .height(10)
          .borderRadius(5)
          .backgroundColor(device.online ? $r('app.color.success') : $r('app.color.text_secondary'))
          .border({ width: 2, color: $r('app.color.surface_muted') })
      }
      .width(44)
      .height(44)
      Column({ space: 4 }) {
        Text(device.label)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Row({ space: 8 }) {
          Text(device.username)
            .fontSize($r('app.float.font_body_small'))
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(device.online ? $r('app.string.device_status_online') :
            (device.lastSeenAtMs > 0 ? $r('app.string.device_status_offline') :
              $r('app.string.device_status_unknown')))
            .fontSize($r('app.float.font_body_small'))
            .fontColor(device.online ? $r('app.color.success') : $r('app.color.text_secondary'))
        }
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height(64)
    .padding({ left: 10, right: 12 })
    .borderRadius($r('app.float.corner_radius_level10'))
    .backgroundColor($r('app.color.surface_muted'))
    .bindContextMenu(this.desktopMobileDeviceContextMenu(device), ResponseType.LongPress)
  }

  @Builder
  private desktopDeviceWorkspace() {
    Row() {
      Scroll() {
        Column({ space: 12 }) {
        Text($r('app.string.desktop_devices'))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text(this.spaceJoined ? $r('app.string.desktop_roster_note') :
          $r('app.string.desktop_no_device'))
          .fontSize($r('app.float.font_body_medium'))
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        if (this.spaceNodeState === 3) {
          Text($r('app.string.space_node_failed'))
            .fontSize($r('app.float.font_body_medium'))
            .fontColor($r('app.color.danger'))
            .width('100%')
        }
        if (this.spaceJoined) {
          Row({ space: 8 }) {
            Button($r('app.string.desktop_refresh_devices'), { type: ButtonType.Normal })
              .layoutWeight(1)
              .height(40)
              .fontSize(12)
              .fontColor($r('app.color.text_primary'))
              .backgroundColor($r('app.color.surface_muted'))
              .borderRadius($r('app.float.corner_radius_level10'))
              .enabled(!this.spaceDeviceRefreshBusy && !this.spaceConnectBusy &&
                !this.desktopDeviceMutationBusy)
              .onClick((): void => {
                this.refreshSpaceDevices();
              })
            Button(this.spaceConnectBusy ? $r('app.string.desktop_connecting_all_devices') :
              $r('app.string.desktop_connect_all_devices'), { type: ButtonType.Normal })
              .layoutWeight(1)
              .height(40)
              .fontSize(12)
              .fontColor($r('app.color.on_accent'))
              .backgroundColor(this.accentColor())
              .borderRadius($r('app.float.corner_radius_level10'))
              .enabled(!this.spaceConnectBusy && !this.desktopDeviceMutationBusy)
              .onClick((): void => {
                this.connectAllSpaceDevices();
              })
          }
          .width('100%')
          if (this.spaceConnectState === 2) {
            Text($r('app.string.desktop_connect_devices_success'))
              .fontSize($r('app.float.font_body_small'))
              .fontColor($r('app.color.success'))
              .width('100%')
          } else if (this.spaceConnectState === 3) {
            Text($r('app.string.desktop_connect_devices_failed'))
              .fontSize($r('app.float.font_body_small'))
              .fontColor($r('app.color.danger'))
              .width('100%')
          }
          Button(this.spaceSwitchOpen ? $r('app.string.space_switch_cancel') :
            $r('app.string.space_switch_open'), { type: ButtonType.Normal })
            .width('100%')
            .height(40)
            .fontSize(12)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.surface_muted'))
            .borderRadius($r('app.float.corner_radius_level10'))
            .enabled(!this.spaceJoinBusy)
            .onClick((): void => {
              this.getUIContext().animateTo({
                duration: 380,
                curve: Curve.EaseOut
              }, (): void => {
                this.spaceSwitchOpen = !this.spaceSwitchOpen;
                this.spaceInvitationCode = '';
                this.spacePassphrase = '';
                this.spaceJoinState = 0;
                this.spaceInvitationScanState = 0;
              });
            })
          if (this.spaceSwitchOpen) {
            Column({ space: 10 }) {
              Row({ space: 4 }) {
                this.spaceModeButton(0, $r('app.string.space_create_new_mode'))
                this.spaceModeButton(1, $r('app.string.space_join_other_mode'))
              }
              .width('100%')
              .padding(3)
              .borderRadius($r('app.float.corner_radius_level10'))
              .backgroundColor($r('app.color.surface_muted'))
              if (this.spaceActionMode === 0) {
                this.desktopCreateSpaceForm()
              } else {
                this.desktopJoinSpaceForm()
              }
            }
            .transition({ type: TransitionType.Insert, opacity: 0, translate: { y: 24 } })
            .transition({ type: TransitionType.Delete, opacity: 0, translate: { y: -16 } })
          } else if (this.spaceJoinState === 1) {
            Text($r('app.string.space_switch_success'))
              .fontSize($r('app.float.font_body_small'))
              .fontColor($r('app.color.success'))
              .width('100%')
          }
        }
        if (!this.spaceJoined) {
          Row({ space: 4 }) {
            this.spaceModeButton(0, $r('app.string.space_create_mode'))
            this.spaceModeButton(1, $r('app.string.space_join_mode'))
          }
          .width('100%')
          .padding(3)
          .borderRadius($r('app.float.corner_radius_level10'))
          .backgroundColor($r('app.color.surface_muted'))
          if (this.spaceActionMode === 0) {
            this.desktopCreateSpaceForm()
          } else {
            this.desktopJoinSpaceForm()
          }
        }
        Row() {
          Text($r('app.string.desktop_paired_devices'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          Blank()
          if (this.spaceJoined) {
            Text(this.spaceDevices.length.toString())
              .fontSize($r('app.float.font_body_small'))
              .fontColor($r('app.color.text_secondary'))
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .borderRadius($r('app.float.corner_radius_level4'))
              .backgroundColor($r('app.color.surface_muted'))
          }
        }
        .width('100%')
        .margin({ top: 14 })
        if (this.spaceJoined) {
          ForEach(this.spaceDevices, (device: NativeSpaceDevice) => {
            this.desktopPairedDeviceRow(device)
          }, (device: NativeSpaceDevice): string => device.deviceId)
        }
        Row() {
          Text($r('app.string.desktop_mobile_devices'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          Blank()
          Text(this.mobileSyncDevices.length.toString())
            .fontSize($r('app.float.font_body_small'))
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .borderRadius($r('app.float.corner_radius_level4'))
            .backgroundColor($r('app.color.surface_muted'))
        }
        .width('100%')
        .margin({ top: 14 })
        if (this.mobileSyncDevices.length === 0) {
          Text($r('app.string.mobile_sync_no_devices'))
            .fontSize($r('app.float.font_body_small'))
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        } else {
          ForEach(this.mobileSyncDevices, (device: NativeMobileSyncDevice) => {
            this.desktopMobileDeviceRow(device)
          }, (device: NativeMobileSyncDevice): string => device.deviceId)
        }
        Blank()
        if (this.spaceJoined) {
          Button(this.spaceConnectBusy ? $r('app.string.desktop_connecting_all_devices') :
            $r('app.string.desktop_connect_all_devices'), { type: ButtonType.Normal })
            .width('100%')
            .height(44)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.surface_muted'))
            .borderRadius($r('app.float.corner_radius_level10'))
            .enabled(!this.spaceConnectBusy && !this.desktopDeviceMutationBusy)
            .onClick((): void => {
              this.connectAllSpaceDevices();
            })
        }
        }
        .width('100%')
        .constraintSize({ minHeight: '100%' })
        .justifyContent(FlexAlign.Start)
        .padding({ left: 22, right: 22, top: 28, bottom: 18 })
        .align(Alignment.TopStart)
      }
      .width(this.isLargeScreen ? 350 : 300)
      .height('100%')
      .border({ width: { right: 1 }, color: $r('app.color.divider') })
      .scrollBar(BarState.Auto)
      Scroll() {
        Column({ space: 0 }) {
          Row({ space: 18 }) {
          Column() {
            this.desktopDeviceTypeGlyph(deviceInfo.deviceType)
          }
          .width(72)
          .height(72)
          .justifyContent(FlexAlign.Center)
          .borderRadius($r('app.float.corner_radius_level8'))
          .backgroundColor(this.accentSoftColor())
          Column({ space: 7 }) {
            Text(this.spaceDeviceName.length > 0 ? this.spaceDeviceName :
              $r('app.string.space_joined_device'))
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Text(this.spaceJoined ?
              (this.spacePeerConnected ? $r('app.string.space_peer_online') :
                $r('app.string.space_peer_waiting')) :
              (this.spaceActionMode === 0 ? $r('app.string.space_create_note') :
                $r('app.string.space_join_note')))
              .fontSize(14)
              .fontColor(this.spacePeerConnected ? $r('app.color.success') :
                $r('app.color.text_secondary'))
          }
          Blank()
          }
          .width('100%')
          .padding({ bottom: 36 })
          Text($r('app.string.desktop_identity'))
          .fontSize($r('app.float.font_body_medium'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding({ bottom: 10 })
        this.desktopInfoRow($r('app.string.desktop_platform'), 'HarmonyOS')
        this.desktopInfoRow($r('app.string.desktop_node_status'),
          this.spaceNodeState === 2 ? $r('app.string.status_online') : $r('app.string.status_offline'))
        this.desktopInfoRow($r('app.string.desktop_space_status'),
          this.spaceJoined ? $r('app.string.space_join_success') : $r('app.string.status_offline'))
        if (this.spaceCreatedId.length > 0) {
          this.desktopInfoRow($r('app.string.desktop_space_id'), this.spaceCreatedId)
        }
        if (this.spaceJoined) {
          Text($r('app.string.space_tablet_invite_title'))
            .fontSize($r('app.float.font_body_medium'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .padding({ top: 28, bottom: 10 })
          Text($r('app.string.space_tablet_invite_note'))
            .fontSize(12)
            .lineHeight(18)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .padding({ bottom: 10 })
          this.spaceInvitationCard()
        }
        this.mobileSyncManagementCard()
        Text($r('app.string.desktop_sync_policy'))
          .fontSize($r('app.float.font_body_medium'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding({ top: 34, bottom: 8 })
        this.desktopSwitchRow($r('app.string.desktop_auto_clipboard'),
          $r('app.string.desktop_auto_clipboard_note'), this.spaceJoined)
          this.desktopSwitchRow($r('app.string.desktop_file_sync'),
            $r('app.string.desktop_file_sync_note'), this.spaceJoined)
        }
        .width('100%')
        .padding({
          left: this.isLargeScreen ? 72 : 32,
          right: this.isLargeScreen ? 72 : 32,
          top: this.isLargeScreen ? 48 : 32,
          bottom: 32
        })
      }
      .layoutWeight(1)
      .height('100%')
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  private desktopInfoRow(label: Resource, value: Resource | string) {
    Row() {
      Text(label)
        .width(190)
        .fontSize($r('app.float.font_body_medium'))
        .fontColor($r('app.color.text_secondary'))
      Text(value)
        .fontSize($r('app.float.font_body_large'))
        .fontColor($r('app.color.text_primary'))
    }
    .width('100%')
    .height(56)
    .border({ width: { top: 1 }, color: $r('app.color.divider') })
  }

  @Builder
  private desktopSwitchRow(title: Resource, note: Resource, checked: boolean) {
    Row() {
      Column({ space: 3 }) {
        Text(title)
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
        Text(note)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      Blank()
      Toggle({ type: ToggleType.Switch, isOn: checked })
        .selectedColor(this.accentColor())
        .enabled(false)
    }
    .width('100%')
    .height(78)
    .border({ width: { top: 1 }, color: $r('app.color.divider') })
  }

  @Builder
  private desktopSettingsNavItem(index: number, icon: Resource, label: Resource) {
    Row({ space: 12 }) {
      SymbolGlyph(icon)
        .fontSize(20)
        .fontWeight(this.largeSettingsSection === index ? FontWeight.Medium : FontWeight.Regular)
        .fontColor([this.largeSettingsSection === index ? this.accentColor() :
          $r('app.color.text_secondary')])
      Text(label)
        .fontSize($r('app.float.font_body_large'))
        .fontWeight(this.largeSettingsSection === index ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.largeSettingsSection === index ? this.accentColor() :
          $r('app.color.text_primary'))
    }
    .width('100%')
    .height(50)
    .padding({ left: 14, right: 14 })
    .borderRadius($r('app.float.corner_radius_level10'))
    .backgroundColor(this.largeSettingsSection === index ? this.accentSoftColor() :
      Color.Transparent)
    .clickEffect({ level: ClickEffectLevel.MIDDLE })
    .onClick((): void => {
      this.largeSettingsSection = index;
    })
  }

  @Builder
  private desktopSettingsWorkspace() {
    Row() {
      Column({ space: 6 }) {
        Text($r('app.string.nav_settings'))
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .padding({ left: 12, bottom: 14 })
        this.desktopSettingsNavItem(0, $r('sys.symbol.gearshape'),
          $r('app.string.desktop_general_settings'))
        this.desktopSettingsNavItem(1, $r('sys.symbol.connection'),
          $r('app.string.desktop_connection_settings'))
        this.desktopSettingsNavItem(2, $r('sys.symbol.paintpalette'),
          $r('app.string.desktop_appearance_settings'))
        this.desktopSettingsNavItem(3, $r('sys.symbol.info_circle'), $r('app.string.about_title'))
        Blank()
        Text($r('app.string.app_title'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .padding({ left: 14, bottom: 8 })
      }
      .width(this.isLargeScreen ? 252 : 220)
      .height('100%')
      .padding({ left: 12, right: 12, top: 24, bottom: 16 })
      .backgroundColor($r('app.color.page_background'))
      Scroll() {
        Column({ space: 18 }) {
          if (this.largeSettingsSection === 0) {
            this.desktopGeneralSettings()
          } else if (this.largeSettingsSection === 1) {
            this.desktopConnectionSettings()
          } else if (this.largeSettingsSection === 2) {
            this.desktopAppearanceSettings()
          } else {
            this.desktopAboutSettings()
          }
        }
        .width('100%')
        .padding({
          left: this.isLargeScreen ? 40 : 24,
          right: this.isLargeScreen ? 40 : 24,
          top: 34,
          bottom: 34
        })
      }
      .layoutWeight(1)
      .height('100%')
      .scrollBar(BarState.Auto)
      .backgroundColor($r('app.color.surface'))
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private desktopGeneralSettings() {
    Text($r('app.string.desktop_general_settings'))
      .fontSize(28)
      .fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.text_primary'))
      .width('100%')
    Column() {
      this.desktopInfoRow($r('app.string.desktop_device_name'),
        this.spaceDeviceName.length > 0 ? this.spaceDeviceName : $r('app.string.space_joined_device'))
      this.backgroundSyncSwitchRow()
    }
    .width('100%')
    .padding({ left: 24, right: 24 })
    .borderRadius($r('app.float.corner_radius_level8'))
    .border({ width: 1, color: $r('app.color.divider') })
  }

  @Builder
  private desktopConnectionSettings() {
    Text($r('app.string.desktop_connection_settings'))
      .fontSize(28)
      .fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.text_primary'))
      .width('100%')
    this.spaceJoinCard()
    Column({ space: 12 }) {
      Text($r('app.string.desktop_legacy_connection_title'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Text($r('app.string.desktop_legacy_connection_note'))
        .fontSize(12)
        .lineHeight(18)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      Text($r('app.string.connect_uri_label'))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      TextArea({ placeholder: $r('app.string.connect_uri_placeholder'), text: this.connectUri })
        .height(80)
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius($r('app.float.corner_radius_level10'))
        .onChange((value: string): void => {
          this.connectUri = value;
          this.connectUriState = 0;
        })
      if (this.connectUriState === 1) {
        Text($r('app.string.connect_uri_success'))
          .fontSize(12)
          .fontColor($r('app.color.success'))
          .width('100%')
      } else if (this.connectUriState === 2) {
        Text($r('app.string.connect_uri_failed'))
          .fontSize(12)
          .fontColor($r('app.color.danger'))
          .width('100%')
      } else if (this.connectUriState === 3) {
        Text($r('app.string.connect_uri_scan_failed'))
          .fontSize(12)
          .fontColor($r('app.color.danger'))
          .width('100%')
      }
      Row({ space: 10 }) {
        Button($r('app.string.connect_uri_scan_action'), { type: ButtonType.Normal })
          .height(42)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.corner_radius_level10'))
          .onClick((): void => {
            this.scanConnectUri();
          })
        Button($r('app.string.connect_uri_action'), { type: ButtonType.Normal })
          .height(42)
          .fontColor($r('app.color.on_accent'))
          .backgroundColor(this.accentColor())
          .borderRadius($r('app.float.corner_radius_level10'))
          .onClick((): void => {
            this.importConnectUri();
          })
      }
    }
    .width('100%')
    .padding(22)
    .borderRadius($r('app.float.corner_radius_level8'))
    .border({ width: 1, color: $r('app.color.divider') })
    Column({ space: 12 }) {
      Row() {
        Text($r('app.string.legacy_service_form_title'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        this.statusPill()
      }
      .width('100%')
      Text($r('app.string.legacy_server_url_label'))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      TextInput({ placeholder: $r('app.string.server_url_placeholder'), text: this.serverUrl })
        .height(46)
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius($r('app.float.corner_radius_level10'))
        .onChange((value: string): void => {
          this.serverUrl = value;
          this.connectionChanged();
        })
      Row({ space: 12 }) {
        Column({ space: 7 }) {
          Text($r('app.string.username_label'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          TextInput({ placeholder: $r('app.string.username_placeholder'), text: this.username })
            .height(46)
            .backgroundColor($r('app.color.surface_muted'))
            .borderRadius($r('app.float.corner_radius_level10'))
            .onChange((value: string): void => {
              this.username = value;
              this.connectionChanged();
            })
        }
        .layoutWeight(1)
        Column({ space: 7 }) {
          Text($r('app.string.password_label'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          TextInput({ placeholder: $r('app.string.password_placeholder'), text: this.password })
            .type(InputType.Password)
            .height(46)
            .backgroundColor($r('app.color.surface_muted'))
            .borderRadius($r('app.float.corner_radius_level10'))
            .onChange((value: string): void => {
              this.password = value;
              this.connectionChanged();
            })
        }
        .layoutWeight(1)
      }
      .width('100%')
      Row({ space: 10 }) {
        Button($r('app.string.test_connection_action'), { type: ButtonType.Normal })
          .layoutWeight(1)
          .height(44)
          .fontColor($r('app.color.on_accent'))
          .backgroundColor(this.accentColor())
          .borderRadius($r('app.float.corner_radius_level10'))
          .enabled(this.hasConfig() && !this.busy)
          .onClick((): void => {
            this.testConnection();
          })
        Button(this.realtimeActive ? $r('app.string.realtime_stop_action') :
          $r('app.string.realtime_start_action'), { type: ButtonType.Normal })
          .layoutWeight(1)
          .height(44)
          .fontColor(this.realtimeActive ? $r('app.color.danger') : $r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.corner_radius_level10'))
          .enabled(this.hasConfig())
          .onClick((): void => {
            this.toggleRealtime();
          })
      }
      .width('100%')
      Text(this.realtimeActive ? $r('app.string.realtime_active_note') :
        $r('app.string.realtime_inactive_note'))
        .fontSize(12)
        .lineHeight(18)
        .fontColor(this.realtimeActive ? $r('app.color.success') : $r('app.color.text_secondary'))
        .width('100%')
    }
    .width('100%')
    .padding(22)
    .borderRadius($r('app.float.corner_radius_level8'))
    .border({ width: 1, color: $r('app.color.divider') })
  }

  @Builder
  private desktopAppearanceSettings() {
    Text($r('app.string.desktop_appearance_settings'))
      .fontSize(28)
      .fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.text_primary'))
      .width('100%')
    Row({ space: 18 }) {
      Column({ space: 12 }) {
        Row()
          .width('100%')
          .height(18)
          .borderRadius(9)
          .backgroundColor('#17212B')
        Row()
          .width('72%')
          .height(12)
          .borderRadius(6)
          .backgroundColor('#65717C')
        Blank()
        Text($r('app.string.desktop_light_theme'))
          .fontSize(14)
          .fontColor('#17212B')
      }
      .layoutWeight(1)
      .height(190)
      .padding(22)
      .borderRadius($r('app.float.corner_radius_level8'))
      .backgroundColor('#FFF0F3F5')
      .border({
        width: this.appearanceMode === APPEARANCE_MODE_LIGHT ? 3 : 1,
        color: this.appearanceMode === APPEARANCE_MODE_LIGHT ? this.accentColor() :
          $r('app.color.divider')
      })
      .clickEffect({ level: ClickEffectLevel.MIDDLE })
      .onClick((): void => {
        this.selectAppearanceMode(APPEARANCE_MODE_LIGHT);
      })
      Column({ space: 12 }) {
        Row()
          .width('100%')
          .height(18)
          .borderRadius(9)
          .backgroundColor('#FAFAFA')
        Row()
          .width('72%')
          .height(12)
          .borderRadius(6)
          .backgroundColor('#8A8A92')
        Blank()
        Text($r('app.string.desktop_dark_theme'))
          .fontSize(14)
          .fontColor('#FAFAFA')
      }
      .layoutWeight(1)
      .height(190)
      .padding(22)
      .borderRadius($r('app.float.corner_radius_level8'))
      .backgroundColor('#18181B')
      .border({
        width: this.appearanceMode === APPEARANCE_MODE_DARK ? 3 : 1,
        color: this.appearanceMode === APPEARANCE_MODE_DARK ? this.accentColor() :
          $r('app.color.divider')
      })
      .clickEffect({ level: ClickEffectLevel.MIDDLE })
      .onClick((): void => {
        this.selectAppearanceMode(APPEARANCE_MODE_DARK);
      })
      Column({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.paintpalette'))
          .fontSize(42)
          .fontWeight(FontWeight.Medium)
          .fontColor([this.accentColor()])
        Blank()
        Text($r('app.string.desktop_follow_system'))
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
      }
      .layoutWeight(1)
      .height(190)
      .padding(22)
      .borderRadius($r('app.float.corner_radius_level8'))
      .backgroundColor(this.accentSoftColor())
      .border({
        width: this.appearanceMode === APPEARANCE_MODE_SYSTEM ? 3 : 1,
        color: this.appearanceMode === APPEARANCE_MODE_SYSTEM ? this.accentColor() :
          $r('app.color.divider')
      })
      .clickEffect({ level: ClickEffectLevel.MIDDLE })
      .onClick((): void => {
        this.selectAppearanceMode(APPEARANCE_MODE_SYSTEM);
      })
    }
    .width('100%')
    Text($r('app.string.appearance_theme_title'))
      .fontSize(16)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_primary'))
      .width('100%')
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        this.compactAppearanceThemeOption(APPEARANCE_THEME_OPTIONS[0])
        this.compactAppearanceThemeOption(APPEARANCE_THEME_OPTIONS[1])
        this.compactAppearanceThemeOption(APPEARANCE_THEME_OPTIONS[2])
      }
      .width('100%')
      Row({ space: 10 }) {
        this.compactAppearanceThemeOption(APPEARANCE_THEME_OPTIONS[3])
        this.compactAppearanceThemeOption(APPEARANCE_THEME_OPTIONS[4])
        this.compactAppearanceThemeOption(APPEARANCE_THEME_OPTIONS[5])
      }
      .width('100%')
    }
    .width('100%')
    .height(122)
  }

  @Builder
  private desktopAboutCapability(icon: Resource, title: Resource, note: Resource) {
    Row({ space: 14 }) {
      Column() {
        SymbolGlyph(icon)
          .fontSize(24)
          .fontWeight(FontWeight.Medium)
          .fontColor([this.accentColor()])
      }
      .width(46)
      .height(46)
      .justifyContent(FlexAlign.Center)
      .borderRadius($r('app.float.corner_radius_level4'))
      .backgroundColor(this.accentSoftColor())
      Column({ space: 5 }) {
        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(note)
          .fontSize(12)
          .lineHeight(18)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .layoutWeight(1)
    .height(104)
    .padding({ left: 18, right: 18 })
    .borderRadius($r('app.float.corner_radius_level8'))
    .border({ width: 1, color: $r('app.color.divider') })
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  private desktopAboutInfoRow(label: Resource, value: Resource) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
      Blank()
      Text(value)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
    }
    .width('100%')
    .height(56)
    .border({ width: { top: 1 }, color: $r('app.color.divider') })
  }

  @Builder
  private desktopAboutSettings() {
    Text($r('app.string.about_title'))
      .fontSize(28)
      .fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.text_primary'))
      .width('100%')
    Row({ space: 24 }) {
      Image($r('app.media.uniclipboard_start_icon'))
        .width(112)
        .height(112)
        .borderRadius(30)
        .objectFit(ImageFit.Cover)
      Column({ space: 0 }) {
        Row({ space: 12 }) {
          Text($r('app.string.app_title'))
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text($r('app.string.desktop_version'))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.accentColor())
            .padding({ left: 11, right: 11, top: 5, bottom: 5 })
            .borderRadius(13)
            .backgroundColor(this.accentSoftColor())
        }
        Text($r('app.string.about_tagline'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .margin({ top: 10 })
        Text($r('app.string.about_description'))
          .fontSize(14)
          .lineHeight(22)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(3)
          .margin({ top: 8 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(28)
    .borderRadius($r('app.float.corner_radius_level8'))
    .backgroundColor($r('app.color.surface_muted'))
    Row({ space: 14 }) {
      this.desktopAboutCapability($r('sys.symbol.rectangle_stack'),
        $r('app.string.about_feature_sync'), $r('app.string.about_feature_sync_note'))
      this.desktopAboutCapability($r('sys.symbol.connection'),
        $r('app.string.about_feature_space'), $r('app.string.about_feature_space_note'))
      this.desktopAboutCapability($r('sys.symbol.desktop'),
        $r('app.string.about_feature_native'), $r('app.string.about_feature_native_note'))
    }
    .width('100%')
    Column({ space: 0 }) {
      Text($r('app.string.about_product_info'))
        .fontSize($r('app.float.font_subtitle_large'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .padding({ bottom: 14 })
      this.desktopAboutInfoRow($r('app.string.about_version_label'),
        $r('app.string.desktop_version'))
      this.desktopAboutInfoRow($r('app.string.about_platform_label'),
        $r('app.string.about_platform_value'))
      this.desktopAboutInfoRow($r('app.string.about_devices_label'),
        $r('app.string.about_devices_value'))
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 20, bottom: 4 })
    .borderRadius($r('app.float.corner_radius_level8'))
    .border({ width: 1, color: $r('app.color.divider') })
    Text($r('app.string.about_footer'))
      .fontSize(12)
      .lineHeight(19)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
      .textAlign(TextAlign.Center)
      .padding({ top: 4, bottom: 10 })
  }

  @Builder
  private largeNavigation() {
    Row() {
      this.desktopRail()
      Stack() {
        if (this.largeSection === 0) {
          this.desktopClipboardWorkspace()
        } else if (this.largeSection === 1) {
          this.desktopDeviceWorkspace()
        } else {
          this.desktopSettingsWorkspace()
        }
      }
      .layoutWeight(1)
      .height('100%')
      .borderRadius($r('app.float.corner_radius_level16'))
      .clip(true)
      .backgroundColor($r('app.color.surface'))
    }
    .width('100%')
    .height('100%')
    .padding({ left: 40, right: 40, top: 40, bottom: 40 })
    .backgroundColor($r('app.color.page_background'))
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM],
      [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .bindSheet($$this.showAboutSheet, this.aboutSheet(), {
      detents: [SheetSize.MEDIUM],
      preferType: SheetType.CENTER,
      dragBar: false,
      showClose: false,
      backgroundColor: $r('app.color.page_background'),
      blurStyle: BlurStyle.Regular,
      onDisappear: (): void => {
        this.onAboutSheetDisappear();
      }
    })
  }

  @Builder
  private mediumNavigation() {
    Row() {
      this.desktopRail()
      Stack() {
        if (this.largeSection === 0) {
          this.tabletClipboardWorkspace()
        } else if (this.largeSection === 1) {
          this.desktopDeviceWorkspace()
        } else {
          this.desktopSettingsWorkspace()
        }
      }
      .layoutWeight(1)
      .height('100%')
      .borderRadius($r('app.float.corner_radius_level16'))
      .clip(true)
      .backgroundColor($r('app.color.surface'))
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24, top: 24, bottom: 24 })
    .backgroundColor($r('app.color.page_background'))
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM],
      [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .bindSheet($$this.showAboutSheet, this.aboutSheet(), {
      detents: [SheetSize.MEDIUM],
      preferType: SheetType.CENTER,
      dragBar: false,
      showClose: false,
      backgroundColor: $r('app.color.page_background'),
      blurStyle: BlurStyle.Regular,
      onDisappear: (): void => {
        this.onAboutSheetDisappear();
      }
    })
  }

  build() {
    Stack() {
      Stack() {
        if (this.isLargeScreen) {
          this.largeNavigation()
        } else if (this.isWideScreen) {
          this.mediumNavigation()
        } else {
          this.compactNavigation()
        }
      }
      .width('100%')
      .height('100%')
      .bindSheet($$this.showOnboardingGuide, this.OnboardingGuideBuilder(), {
        preferType: SheetType.CENTER,
        dragBar: false,
        showClose: false,
        backgroundColor: $r('app.color.page_background'),
        blurStyle: BlurStyle.Regular,
        onDisappear: (): void => {
          this.showOnboardingGuide = false;
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .bindSheet($$this.showFeedbackSheet, this.feedbackSheet(), {
      detents: [SheetSize.MEDIUM],
      preferType: SheetType.CENTER,
      dragBar: false,
      showClose: false,
      backgroundColor: $r('app.color.page_background'),
      blurStyle: BlurStyle.Regular,
      onDisappear: (): void => {
        this.showFeedbackSheet = false;
      }
    })
  }
}
