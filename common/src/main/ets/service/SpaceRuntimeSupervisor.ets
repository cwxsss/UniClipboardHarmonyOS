import { common } from '@kit.AbilityKit';
import {
  EngineRuntimeService,
  EngineSessionRecovery,
  engineRuntimeService
} from './EngineRuntimeService';
import { SpaceProfileDirectory, SpaceProfileRecord } from './SpaceProfileStore';
import { Logger } from '../util/Logger';

const logger: Logger = new Logger('SpaceRuntimeSupervisor');

export class SpaceRuntimeSupervisor {
  private backgroundRuntimes: Map<string, EngineRuntimeService> = new Map<string, EngineRuntimeService>();
  private activeProfileId: string = engineRuntimeService.getProfileId();
  private operation: Promise<void> | null = null;

  async restore(context: common.UIAbilityContext, directory: SpaceProfileDirectory): Promise<EngineSessionRecovery> {
    let activeProfileId: string = directory.activeProfileId();
    let recovery: EngineSessionRecovery = await this.activate(context, directory, activeProfileId);
    await this.startBackgroundProfiles(context, directory, activeProfileId);
    return recovery;
  }

  async activate(context: common.UIAbilityContext, directory: SpaceProfileDirectory,
    profileId: string): Promise<EngineSessionRecovery> {
    let pending: Promise<void> | null = this.operation;
    if (pending !== null) {
      await pending;
    }
    let recovery: EngineSessionRecovery | null = null;
    let task: Promise<void> = this.performActivate(context, directory, profileId,
      (value: EngineSessionRecovery): void => {
        recovery = value;
      });
    this.operation = task;
    try {
      await task;
    } finally {
      if (this.operation === task) {
        this.operation = null;
      }
    }
    if (recovery === null) {
      throw new Error('space runtime activation did not return a recovery result');
    }
    return recovery;
  }

  async shutdown(): Promise<void> {
    let runtimes: EngineRuntimeService[] = Array.from(this.backgroundRuntimes.values());
    this.backgroundRuntimes.clear();
    for (let index: number = 0; index < runtimes.length; index += 1) {
      try {
        await runtimes[index].shutdown();
      } catch (error) {
        logger.warn('UniClipboard failed to stop one background space runtime.');
      }
    }
    await engineRuntimeService.shutdown();
  }

  private async performActivate(context: common.UIAbilityContext, directory: SpaceProfileDirectory,
    profileId: string, resolve: (recovery: EngineSessionRecovery) => void): Promise<void> {
    let target: SpaceProfileRecord | undefined = directory.profiles.find(
      (profile: SpaceProfileRecord): boolean => profile.profileId === profileId && profile.enabled);
    if (target === undefined) {
      throw new Error('requested space profile is unavailable');
    }
    let previousProfileId: string = this.activeProfileId;
    if (previousProfileId !== profileId) {
      await engineRuntimeService.shutdown();
      await this.startBackgroundProfile(context, previousProfileId, directory);
      await this.stopBackgroundProfile(profileId);
    }
    try {
      let recovery: EngineSessionRecovery = await engineRuntimeService.activateProfile(context, profileId);
      this.activeProfileId = profileId;
      resolve(recovery);
    } catch (error) {
      if (previousProfileId !== profileId) {
        await this.stopBackgroundProfile(previousProfileId);
        try {
          let restored: EngineSessionRecovery = await engineRuntimeService.activateProfile(context, previousProfileId);
          this.activeProfileId = previousProfileId;
          logger.warn('UniClipboard restored the previously active space after activation failed.');
          if (restored.resumed) {
            await this.startBackgroundProfiles(context, directory, previousProfileId);
          }
        } catch (restoreError) {
          logger.warn('UniClipboard failed to restore the previously active space.');
        }
      }
      throw new Error('space runtime activation failed');
    }
  }

  private async startBackgroundProfiles(context: common.UIAbilityContext, directory: SpaceProfileDirectory,
    activeProfileId: string): Promise<void> {
    for (let index: number = 0; index < directory.profiles.length; index += 1) {
      let profile: SpaceProfileRecord = directory.profiles[index];
      if (profile.enabled && profile.joined && profile.profileId !== activeProfileId) {
        await this.startBackgroundProfile(context, profile.profileId, directory);
      }
    }
  }

  private async startBackgroundProfile(context: common.UIAbilityContext, profileId: string,
    directory: SpaceProfileDirectory): Promise<void> {
    if (profileId === this.activeProfileId || this.backgroundRuntimes.has(profileId)) {
      return;
    }
    let configured: boolean = directory.profiles.some((profile: SpaceProfileRecord): boolean =>
      profile.profileId === profileId && profile.enabled && profile.joined);
    if (!configured) {
      return;
    }
    let runtime: EngineRuntimeService = EngineRuntimeService.createForProfile(profileId, false);
    await runtime.prepare(context);
    await runtime.start();
    try {
      await runtime.recoverSession(true);
      this.backgroundRuntimes.set(profileId, runtime);
    } catch (error) {
      await runtime.shutdown();
      throw new Error('background space runtime startup failed');
    }
  }

  private async stopBackgroundProfile(profileId: string): Promise<void> {
    let runtime: EngineRuntimeService | undefined = this.backgroundRuntimes.get(profileId);
    if (runtime === undefined) {
      return;
    }
    this.backgroundRuntimes.delete(profileId);
    await runtime.shutdown();
  }
}

export const spaceRuntimeSupervisor: SpaceRuntimeSupervisor = new SpaceRuntimeSupervisor();
