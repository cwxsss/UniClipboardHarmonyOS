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
import { setSpaceBackgroundMode, stopSpaceNode, wakeSpaceConnections } from 'uniclipboard_native';
import { AppearanceStorageService } from '../service/AppearanceStorageService';
import {
  BackgroundSyncPreferenceService,
  BackgroundSyncTaskService
} from '../service/BackgroundSyncService';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | null = null;
  private appearanceStorageService: AppearanceStorageService = new AppearanceStorageService();
  private backgroundSyncPreferenceService: BackgroundSyncPreferenceService =
    new BackgroundSyncPreferenceService();
  private backgroundSyncTaskService: BackgroundSyncTaskService = new BackgroundSyncTaskService();

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
    let backgroundSyncEnabled: boolean = this.backgroundSyncPreferenceService.load(this.context);
    AppStorage.setOrCreate('backgroundSyncEnabled', backgroundSyncEnabled);
    AppStorage.setOrCreate('spaceJoined', false);
    try {
      let appearanceMode: string = this.appearanceStorageService.load(this.context);
      this.context.getApplicationContext().setColorMode(
        this.appearanceStorageService.getColorMode(appearanceMode));
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    setSpaceBackgroundMode(false);
    this.backgroundSyncTaskService.stop(this.context).catch((): void => {
      hilog.warn(DOMAIN, 'testTag', 'Background sync task shutdown did not complete cleanly.');
    });
    stopSpaceNode().catch((): void => {
      hilog.warn(DOMAIN, 'testTag', 'Space node shutdown did not complete cleanly.');
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
    });
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
    setSpaceBackgroundMode(false);
    this.backgroundSyncTaskService.stop(this.context).catch((): void => {
      hilog.warn(DOMAIN, 'testTag', 'Background sync task cleanup did not complete cleanly.');
    });
    // HarmonyOS may suspend timers and network work while the ability is in
    // background. Wake the native peer scheduler as soon as the app returns.
    wakeSpaceConnections();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    let backgroundSyncEnabled: boolean | undefined = AppStorage.get<boolean>('backgroundSyncEnabled');
    let spaceJoined: boolean | undefined = AppStorage.get<boolean>('spaceJoined');
    if (backgroundSyncEnabled === true && spaceJoined === true) {
      setSpaceBackgroundMode(true);
      this.backgroundSyncTaskService.start(this.context).catch((): void => {
        hilog.warn(DOMAIN, 'testTag', 'Background sync task startup did not complete cleanly.');
      });
    } else {
      setSpaceBackgroundMode(false);
      this.backgroundSyncTaskService.stop(this.context).catch((): void => {
        hilog.warn(DOMAIN, 'testTag', 'Background sync task cleanup did not complete cleanly.');
      });
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
