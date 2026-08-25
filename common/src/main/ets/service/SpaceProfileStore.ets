import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { Logger } from '../util/Logger';

const STORE_NAME: string = 'space_profile_directory';
const DIRECTORY_KEY: string = 'directory_v1';
export const LEGACY_SPACE_PROFILE_ID: string = '.engine-v1-1';
const PROFILE_ID_PATTERN: RegExp = /^[a-zA-Z0-9._-]{1,96}$/;
const logger: Logger = new Logger('SpaceProfileStore');

export class SpaceProfileRecord {
  profileId: string;
  enabled: boolean;
  activeSend: boolean;
  joined: boolean;

  constructor(profileId: string, enabled: boolean, activeSend: boolean, joined: boolean = true) {
    this.profileId = profileId;
    this.enabled = enabled;
    this.activeSend = activeSend;
    this.joined = joined;
  }
}

export class SpaceProfileDirectory {
  profiles: SpaceProfileRecord[];

  constructor(profiles: SpaceProfileRecord[]) {
    this.profiles = profiles;
  }

  activeProfileId(): string {
    for (let index: number = 0; index < this.profiles.length; index += 1) {
      if (this.profiles[index].activeSend) {
        return this.profiles[index].profileId;
      }
    }
    return LEGACY_SPACE_PROFILE_ID;
  }
}

export class SpaceProfileStore {
  load(context: common.Context): SpaceProfileDirectory {
    try {
      let store: preferences.Preferences = this.getStore(context);
      let serialized: string = store.getSync(DIRECTORY_KEY, '') as string;
      let directory: SpaceProfileDirectory = this.parse(serialized);
      this.save(context, directory);
      return directory;
    } catch (error) {
      logger.error('UniClipboard failed to load the space profile directory.');
      return this.legacyDirectory();
    }
  }

  save(context: common.Context, directory: SpaceProfileDirectory): void {
    let normalized: SpaceProfileDirectory = this.normalize(directory.profiles);
    directory.profiles = normalized.profiles;
    try {
      let store: preferences.Preferences = this.getStore(context);
      store.putSync(DIRECTORY_KEY, JSON.stringify(normalized.profiles));
      store.flushSync();
    } catch (error) {
      logger.error('UniClipboard failed to persist the space profile directory.');
    }
  }

  add(directory: SpaceProfileDirectory): SpaceProfileRecord {
    let profile: SpaceProfileRecord = new SpaceProfileRecord(this.newProfileId(), true, false, false);
    directory.profiles.push(profile);
    directory.profiles = this.normalize(directory.profiles).profiles;
    return profile;
  }

  setActive(directory: SpaceProfileDirectory, profileId: string): void {
    let found: boolean = false;
    for (let index: number = 0; index < directory.profiles.length; index += 1) {
      let profile: SpaceProfileRecord = directory.profiles[index];
      profile.activeSend = profile.profileId === profileId;
      found = found || profile.activeSend;
    }
    if (!found) {
      throw new Error('unknown space profile');
    }
    directory.profiles = this.normalize(directory.profiles).profiles;
  }

  remove(directory: SpaceProfileDirectory, profileId: string): void {
    if (profileId === LEGACY_SPACE_PROFILE_ID) {
      throw new Error('legacy space profile cannot be removed');
    }
    directory.profiles = directory.profiles.filter((profile: SpaceProfileRecord): boolean =>
      profile.profileId !== profileId);
    directory.profiles = this.normalize(directory.profiles).profiles;
  }

  private parse(serialized: string): SpaceProfileDirectory {
    if (serialized.trim().length === 0) {
      return this.legacyDirectory();
    }
    try {
      let source: Object[] = JSON.parse(serialized) as Object[];
      let profiles: SpaceProfileRecord[] = [];
      for (let index: number = 0; index < source.length; index += 1) {
        let item: Object = source[index];
        let profileId: string = (item as Record<string, Object>)['profileId'] as string;
        let enabled: boolean = (item as Record<string, Object>)['enabled'] === true;
        let activeSend: boolean = (item as Record<string, Object>)['activeSend'] === true;
        let joined: boolean = (item as Record<string, Object>)['joined'] !== false;
        if (typeof profileId === 'string' && PROFILE_ID_PATTERN.test(profileId)) {
          profiles.push(new SpaceProfileRecord(profileId, enabled, activeSend, joined));
        }
      }
      return this.normalize(profiles);
    } catch (error) {
      return this.legacyDirectory();
    }
  }

  private normalize(source: SpaceProfileRecord[]): SpaceProfileDirectory {
    let profiles: SpaceProfileRecord[] = [];
    let seen: Set<string> = new Set<string>();
    for (let index: number = 0; index < source.length; index += 1) {
      let profile: SpaceProfileRecord = source[index];
      if (!PROFILE_ID_PATTERN.test(profile.profileId) || seen.has(profile.profileId)) {
        continue;
      }
      seen.add(profile.profileId);
      profiles.push(new SpaceProfileRecord(profile.profileId, profile.enabled, profile.activeSend, profile.joined));
    }
    if (!seen.has(LEGACY_SPACE_PROFILE_ID)) {
      profiles.unshift(new SpaceProfileRecord(LEGACY_SPACE_PROFILE_ID, true, profiles.length === 0, true));
    }
    let activeAssigned: boolean = false;
    for (let index: number = 0; index < profiles.length; index += 1) {
      let profile: SpaceProfileRecord = profiles[index];
      if (profile.activeSend && profile.joined && !activeAssigned) {
        activeAssigned = true;
      } else {
        profile.activeSend = false;
      }
    }
    if (!activeAssigned) {
      let fallback: SpaceProfileRecord | undefined = profiles.find(
        (profile: SpaceProfileRecord): boolean => profile.joined);
      if (fallback !== undefined) {
        fallback.activeSend = true;
      } else {
        profiles[0].activeSend = true;
      }
    }
    return new SpaceProfileDirectory(profiles);
  }

  private newProfileId(): string {
    return 'space-' + util.generateRandomUUID();
  }

  private legacyDirectory(): SpaceProfileDirectory {
    return new SpaceProfileDirectory([
      new SpaceProfileRecord(LEGACY_SPACE_PROFILE_ID, true, true, true)
    ]);
  }

  private getStore(context: common.Context): preferences.Preferences {
    let options: preferences.Options = { name: STORE_NAME };
    return preferences.getPreferencesSync(context, options);
  }
}
