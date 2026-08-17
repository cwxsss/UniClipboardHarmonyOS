import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { mediaquery } from '@kit.ArkUI';
import { ClipboardFeatureController } from 'clipboard_feature';
import { Logger } from 'common';
import { OnboardingGuide } from '../components/OnboardingGuide';
import { CompactClipboardView } from '../view/compact/CompactClipboardView';
import { ExpandedClipboardView } from '../view/expanded/ExpandedClipboardView';

const logger: Logger = new Logger('IndexPage');

const ONBOARDING_STORE_NAME: string = 'onboarding_preferences';
const ONBOARDING_COMPLETED_KEY: string = 'onboarding_completed';

@Entry
@Component
struct Index {
  @StorageProp('avoidAreaRectHeight') avoidAreaRectHeight: number = 0;
  @StorageProp('navigationRectHeight') navigationRectHeight: number = 0;
  @StorageLink('appearanceBackgroundImage') appearanceBackgroundImage: string = '';
  @StorageLink('appearanceBackgroundOpacity') appearanceBackgroundOpacity: number = 0.4;
  @StorageLink('appearanceBackgroundBlur') appearanceBackgroundBlur: number = 8;
  @State controller: ClipboardFeatureController = ClipboardFeatureController.getInstance();
  @State showOnboardingGuide: boolean = false;
  private wideScreenListener: mediaquery.MediaQueryListener | null = null;
  private largeScreenListener: mediaquery.MediaQueryListener | null = null;

  aboutToAppear(): void {
    this.loadOnboardingState();
    this.controller.start(this.getUIContext());
    let wideListener: mediaquery.MediaQueryListener = this.getUIContext().getMediaQuery()
      .matchMediaSync('(840vp<=width)');
    let largeListener: mediaquery.MediaQueryListener = this.getUIContext().getMediaQuery()
      .matchMediaSync('(1200vp<=width)');
    this.wideScreenListener = wideListener;
    this.largeScreenListener = largeListener;
    this.controller.setScreenMode(wideListener.matches, largeListener.matches);
    wideListener.on('change', (result: mediaquery.MediaQueryResult): void => {
      this.controller.setScreenMode(result.matches, this.controller.isLargeScreen);
    });
    largeListener.on('change', (result: mediaquery.MediaQueryResult): void => {
      this.controller.setScreenMode(this.controller.isWideScreen, result.matches);
    });
  }

  private loadOnboardingState(): void {
    try {
      let context: common.Context | undefined = this.getUIContext().getHostContext();
      if (context === undefined) {
        this.showOnboardingGuide = true;
        return;
      }
      let options: preferences.Options = { name: ONBOARDING_STORE_NAME };
      let store: preferences.Preferences = preferences.getPreferencesSync(context, options);
      let completed: boolean = store.getSync(ONBOARDING_COMPLETED_KEY, false) as boolean;
      this.showOnboardingGuide = !completed;
    } catch (error) {
      this.showOnboardingGuide = true;
      logger.error('Index: failed to load onboarding state: ' + JSON.stringify(error));
    }
  }

  private completeOnboarding(): void {
    try {
      let context: common.Context | undefined = this.getUIContext().getHostContext();
      if (context === undefined) {
        return;
      }
      let options: preferences.Options = { name: ONBOARDING_STORE_NAME };
      let store: preferences.Preferences = preferences.getPreferencesSync(context, options);
      store.putSync(ONBOARDING_COMPLETED_KEY, true);
      store.flushSync();
    } catch (error) {
      logger.error('Index: failed to save onboarding state: ' + JSON.stringify(error));
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

  onPageShow(): void {
    this.controller.onPageShow();
  }

  onPageHide(): void {
    this.controller.onPageHide();
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
    this.controller.stop();
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.page_background'))
      if (this.appearanceBackgroundImage.length > 0) {
        Image(this.appearanceBackgroundImage)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .opacity(this.appearanceBackgroundOpacity)
          .blur(this.appearanceBackgroundBlur)
      }
      if (this.controller.isWideScreen) {
        ExpandedClipboardView({
          avoidAreaRectHeight: this.avoidAreaRectHeight
        })
      } else {
        CompactClipboardView({
          avoidAreaRectHeight: this.avoidAreaRectHeight,
          navigationRectHeight: this.navigationRectHeight
        })
      }
    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.showOnboardingGuide, this.OnboardingGuideBuilder(), {
      preferType: SheetType.CENTER,
      dragBar: false,
      showClose: false,
      backgroundColor: $r('app.color.page_background'),
      onDisappear: (): void => {
        this.showOnboardingGuide = false;
      }
    })
  }
}
