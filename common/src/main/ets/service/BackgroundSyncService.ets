import { bundleManager, common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { notificationManager } from '@kit.NotificationKit';
import { Logger } from '../util/Logger';

const logger: Logger = new Logger('BackgroundSync');
const STORE_NAME: string = 'background_sync_preferences';
const ENABLED_KEY: string = 'background_sync_enabled';
const ABILITY_NAME: string = 'EntryAbility';
const BACKGROUND_TASK_MODE: string = 'dataTransfer';

export class BackgroundSyncPreferenceService {
  load(context: common.Context): boolean {
    try {
      let storeOptions: preferences.Options = { name: STORE_NAME };
      let store: preferences.Preferences = preferences.getPreferencesSync(context, storeOptions);
      return store.getSync(ENABLED_KEY, false) as boolean;
    } catch (error) {
      logger.error('UniClipboard failed to restore the background sync preference.');
      return false;
    }
  }

  save(context: common.Context, enabled: boolean): void {
    try {
      let storeOptions: preferences.Options = { name: STORE_NAME };
      let store: preferences.Preferences = preferences.getPreferencesSync(context, storeOptions);
      store.putSync(ENABLED_KEY, enabled);
      store.flushSync();
    } catch (error) {
      logger.error('UniClipboard failed to persist the background sync preference.');
    }
  }
}

export class BackgroundSyncTaskService {
  private active: boolean = false;
  private starting: boolean = false;
  private stopping: boolean = false;
  private shouldRun: boolean = false;

  async start(context: common.UIAbilityContext): Promise<void> {
    this.shouldRun = true;
    if (this.active || this.starting || this.stopping) {
      return;
    }
    this.starting = true;
    try {
      let notificationsEnabled: boolean = await notificationManager.isNotificationEnabled();
      if (!notificationsEnabled) {
        logger.warn('UniClipboard cannot start background device sync because notifications are disabled.');
        return;
      }
      let bundleInfo: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      let wantAgentInfo: wantAgent.WantAgentInfo = {
        wants: [
          {
            bundleName: bundleInfo.name,
            abilityName: ABILITY_NAME
          }
        ],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      let notificationWantAgent: WantAgent = await wantAgent.getWantAgent(wantAgentInfo);
      if (this.shouldRun) {
        let taskModes: string[] = [BACKGROUND_TASK_MODE];
        let taskNotification: backgroundTaskManager.ContinuousTaskNotification =
          await backgroundTaskManager.startBackgroundRunning(context, taskModes, notificationWantAgent);
        this.active = true;
        logger.info('UniClipboard background device sync started. Task ID: ' +
          (taskNotification.continuousTaskId ?? -1).toString() + ', notification ID: ' +
          taskNotification.notificationId.toString() + '.');
      }
    } catch (error) {
      let businessError: BusinessError = error as BusinessError;
      logger.error('UniClipboard failed to start background device sync. Code: ' +
        businessError.code.toString() + ', message: ' + businessError.message);
      this.active = false;
    } finally {
      this.starting = false;
    }
    if (!this.shouldRun && this.active) {
      await this.stop(context);
    }
  }

  async stop(context: common.UIAbilityContext): Promise<void> {
    this.shouldRun = false;
    if (this.starting || this.stopping || !this.active) {
      return;
    }
    this.stopping = true;
    try {
      await backgroundTaskManager.stopBackgroundRunning(context);
      logger.info('UniClipboard background device sync stopped.');
    } catch (error) {
      let businessError: BusinessError = error as BusinessError;
      logger.error('UniClipboard failed to stop background device sync. Code: ' +
        businessError.code.toString() + ', message: ' + businessError.message);
    } finally {
      this.active = false;
      this.stopping = false;
    }
    if (this.shouldRun) {
      await this.start(context);
    }
  }
}
