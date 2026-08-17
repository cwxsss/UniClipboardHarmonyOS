/*
 * Copyright (c) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { systemShare } from '@kit.ShareKit';
import {
  AppearanceStorageService,
  BackgroundSyncPreferenceService,
  BackgroundSyncTaskService,
  engineRuntimeService
} from 'common';

const DOMAIN = 0x0000;
const SHARE_ACTION: string = 'ohos.want.action.sendData';

export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | null = null;
  private pendingShareWant: Want | null = null;
  private appearanceStorageService: AppearanceStorageService = new AppearanceStorageService();
  private backgroundSyncPreferenceService: BackgroundSyncPreferenceService =
    new BackgroundSyncPreferenceService();
  private backgroundSyncTaskService: BackgroundSyncTaskService = new BackgroundSyncTaskService();
  private engineStartupTask: Promise<void> | null = null;

  private avoidAreaChangeCallback = (data: window.AvoidAreaOptions): void => {
    if (this.mainWindow === null) {
      return;
    }
    let uiContext = this.mainWindow.getUIContext();
    if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
      AppStorage.setOrCreate('avoidAreaRectHeight', uiContext.px2vp(data.area.topRect.height));
    } else if (data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
      AppStorage.setOrCreate('navigationRectHeight', uiContext.px2vp(data.area.bottomRect.height));
    }
  };

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    if (this.isShareWant(want)) {
      this.pendingShareWant = want;
    }
    let backgroundSyncEnabled: boolean = this.backgroundSyncPreferenceService.load(this.context);
    AppStorage.setOrCreate('backgroundSyncEnabled', backgroundSyncEnabled);
    AppStorage.setOrCreate('spaceJoined', false);
    AppStorage.setOrCreate('officialEngineSessionResumed', false);
    this.startEngineRuntime().catch((): void => {
      hilog.warn(DOMAIN, 'testTag', 'Official Engine startup did not complete cleanly.');
    });
    try {
      let appearanceMode: string = this.appearanceStorageService.load(this.context);
      this.context.getApplicationContext().setColorMode(
        this.appearanceStorageService.getColorMode(appearanceMode));
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  private async startEngineRuntime(): Promise<void> {
    let pending: Promise<void> | null = this.engineStartupTask;
    if (pending !== null) {
      await pending;
      return;
    }
    pending = this.performEngineRuntimeStart();
    this.engineStartupTask = pending;
    try {
      await pending;
    } finally {
      if (this.engineStartupTask === pending) {
        this.engineStartupTask = null;
      }
    }
  }

  private async performEngineRuntimeStart(): Promise<void> {
    await engineRuntimeService.prepare(this.context);
    await engineRuntimeService.start();
    let recovery = await engineRuntimeService.recoverSession(true);
    AppStorage.setOrCreate('officialEngineSessionResumed', recovery.resumed);
    if (recovery.resumed) {
      AppStorage.setOrCreate('spaceJoined', true);
    }
    hilog.info(DOMAIN, 'testTag', 'Official Engine started. resumed=%{public}d',
      recovery.resumed ? 1 : 0);
  }

  onDestroy(): void {
    this.backgroundSyncTaskService.stop(this.context).catch((): void => {
      hilog.warn(DOMAIN, 'testTag', 'Background sync task shutdown did not complete cleanly.');
    });
    engineRuntimeService.shutdown().catch((): void => {
      hilog.warn(DOMAIN, 'testTag', 'Engine runtime shutdown did not complete cleanly.');
    });
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      let mainWindow: window.Window = windowStage.getMainWindowSync();
      this.mainWindow = mainWindow;
      mainWindow.setWindowLayoutFullScreen(true).catch((error: BusinessError): void => {
        hilog.error(DOMAIN, 'testTag',
          'Failed to enable immersive layout. Cause: %{public}s', JSON.stringify(error));
      });
      let uiContext = mainWindow.getUIContext();
      let systemArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      let navigationArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      AppStorage.setOrCreate('avoidAreaRectHeight', uiContext.px2vp(systemArea.topRect.height));
      AppStorage.setOrCreate('navigationRectHeight', uiContext.px2vp(navigationArea.bottomRect.height));
      mainWindow.on('avoidAreaChange', this.avoidAreaChangeCallback);
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
      let pendingShareWant: Want | null = this.pendingShareWant;
      this.pendingShareWant = null;
      if (pendingShareWant !== null) {
        this.openShareTarget(pendingShareWant);
      }
    });
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    if (!this.isShareWant(want)) {
      return;
    }
    if (this.mainWindow === null) {
      this.pendingShareWant = want;
      return;
    }
    this.openShareTarget(want);
  }

  private isShareWant(want: Want): boolean {
    return want.action === SHARE_ACTION;
  }

  private async openShareTarget(want: Want): Promise<void> {
    let mainWindow: window.Window | null = this.mainWindow;
    if (mainWindow === null) {
      this.pendingShareWant = want;
      return;
    }
    try {
      let data: systemShare.SharedData = await systemShare.getSharedData(want);
      let storage: LocalStorage = new LocalStorage();
      storage.setOrCreate('shareData', data);
      storage.setOrCreate('shareHostWindow', mainWindow);
      await mainWindow.loadContent('pages/ShareTarget', storage);
      hilog.info(DOMAIN, 'testTag', 'Loaded the share target in the main ability.');
    } catch (error) {
      hilog.error(DOMAIN, 'testTag', 'Failed to open the share target in the main ability.');
    }
  }

  onWindowStageDestroy(): void {
    let mainWindow: window.Window | null = this.mainWindow;
    this.mainWindow = null;
    if (mainWindow !== null) {
      try {
        mainWindow.off('avoidAreaChange', this.avoidAreaChangeCallback);
      } catch (error) {
        // The system can invalidate the native window before this lifecycle
        // callback runs. Listener cleanup must not terminate the ability.
        hilog.warn(DOMAIN, 'testTag', 'Avoid-area listener was already released with the window.');
      }
    }
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    this.backgroundSyncTaskService.stop(this.context).catch((): void => {
      hilog.warn(DOMAIN, 'testTag', 'Background sync task cleanup did not complete cleanly.');
    });
    this.startEngineRuntime().catch((): void => {
      hilog.warn(DOMAIN, 'testTag', 'Official Engine resume did not complete cleanly.');
    });
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    let backgroundSyncEnabled: boolean | undefined = AppStorage.get<boolean>('backgroundSyncEnabled');
    let spaceJoined: boolean | undefined = AppStorage.get<boolean>('spaceJoined');
    if (backgroundSyncEnabled === true && spaceJoined === true) {
      this.backgroundSyncTaskService.start(this.context).catch((): void => {
        hilog.warn(DOMAIN, 'testTag', 'Background sync task startup did not complete cleanly.');
      });
    } else {
      this.backgroundSyncTaskService.stop(this.context).catch((): void => {
        hilog.warn(DOMAIN, 'testTag', 'Background sync task cleanup did not complete cleanly.');
      });
    }
    engineRuntimeService.suspend().catch((): void => {
      hilog.warn(DOMAIN, 'testTag', 'Engine runtime suspend did not complete cleanly.');
    });
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
