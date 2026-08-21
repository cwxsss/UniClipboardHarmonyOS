import { ShareExtensionAbility, UIExtensionContentSession, Want } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { Logger } from 'common';

const logger: Logger = new Logger('ShareAbility');

export default class UniClipboardShareAbility extends ShareExtensionAbility {
  onSessionCreate(want: Want, session: UIExtensionContentSession): void {
    this.forwardToMainAbility(want, session);
  }

  private async forwardToMainAbility(want: Want, session: UIExtensionContentSession): Promise<void> {
    try {
      want.bundleName = this.context.applicationInfo.name;
      want.moduleName = 'entry';
      want.abilityName = 'EntryAbility';
      await this.context.startAbility(want);
      await session.terminateSelfWithResult({
        resultCode: systemShare.ShareAbilityResultCode.CLOSE
      });
    } catch (error) {
      logger.error('UniClipboard failed to forward shared data to the main ability.');
      await session.terminateSelfWithResult({
        resultCode: systemShare.ShareAbilityResultCode.ERROR
      });
    }
  }
}
