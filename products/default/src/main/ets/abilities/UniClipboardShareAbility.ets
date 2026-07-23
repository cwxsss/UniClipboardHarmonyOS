import { ShareExtensionAbility, UIExtensionContentSession, Want } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';

export default class UniClipboardShareAbility extends ShareExtensionAbility {
  onSessionCreate(want: Want, session: UIExtensionContentSession): void {
    this.forwardToMainAbility(want, session);
  }

  private async forwardToMainAbility(want: Want, session: UIExtensionContentSession): Promise<void> {
    try {
      want.bundleName = 'com.uniclipboard.hmos';
      want.moduleName = 'entry';
      want.abilityName = 'EntryAbility';
      await this.context.startAbility(want);
      await session.terminateSelfWithResult({
        resultCode: systemShare.ShareAbilityResultCode.CLOSE
      });
    } catch (error) {
      console.error('UniClipboard failed to forward shared data to the main ability.');
      await session.terminateSelfWithResult({
        resultCode: systemShare.ShareAbilityResultCode.ERROR
      });
    }
  }
}
