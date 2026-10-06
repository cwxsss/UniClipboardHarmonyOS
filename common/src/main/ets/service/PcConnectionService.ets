import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { engineRuntimeService, EngineRuntimeState } from './EngineRuntimeService';
import { spaceRuntimeSupervisor } from './SpaceRuntimeSupervisor';
import { SpaceProfileStore } from './SpaceProfileStore';
import { BackgroundSyncPreferenceService } from './BackgroundSyncService';
import { pcConnectionState } from './PcConnectionPolicy';

export interface PcConnectionObserver {
  onPcConnectionChanged(busy: boolean): void;
}

/** Serializes UniClipboard connection startup and preserves stored space identities. */
export class PcConnectionService {
  private loaded: boolean = false;
  private operation: Promise<void> | null = null;
  private observers: PcConnectionObserver[] = [];
  private inBackground: boolean = false;
  private closing: boolean = false;

  getGeneration(): number {
    return pcConnectionState.getGeneration();
  }

  isEnabled(): boolean {
    return pcConnectionState.isEnabled();
  }

  restore(context: common.Context): void {
    if (this.loaded) {
      return;
    }
    // Migrate the obsolete channel choice to the sole supported PC connection.
    let store: preferences.Preferences = preferences.getPreferencesSync(context, { name: 'pc_sync_mode' });
    let oldMode: string = store.getSync('mode', '') as string;
    if (oldMode !== 'uniclipboard') {
      store.putSync('mode', 'uniclipboard');
      store.flushSync();
      new BackgroundSyncPreferenceService().save(context, true);
      AppStorage.setOrCreate('backgroundSyncEnabled', true);
    }
    pcConnectionState.enable();
    this.loaded = true;
  }

  addObserver(observer: PcConnectionObserver): void {
    if (this.observers.indexOf(observer) < 0) {
      this.observers.push(observer);
    }
    observer.onPcConnectionChanged(this.operation !== null);
  }

  removeObserver(observer: PcConnectionObserver): void {
    let index: number = this.observers.indexOf(observer);
    if (index >= 0) {
      this.observers.splice(index, 1);
    }
  }

  async ensureActive(context: common.UIAbilityContext): Promise<void> {
    if (this.closing) {
      return;
    }
    this.restore(context);
    let pending: Promise<void> | null = this.operation;
    if (pending !== null) {
      await pending;
      return;
    }
    let state: EngineRuntimeState = engineRuntimeService.getSnapshot().state;
    if (state === EngineRuntimeState.RUNNING && this.isEnabled()) {
      return;
    }
    let task: Promise<void> = this.startConnection(context, state);
    this.operation = task;
    this.publish(true);
    try {
      await task;
    } finally {
      if (this.operation === task) {
        this.operation = null;
      }
      this.publish(false);
    }
  }

  private async startConnection(context: common.UIAbilityContext, state: EngineRuntimeState): Promise<void> {
    if (state === EngineRuntimeState.SUSPENDED && this.isEnabled()) {
      await engineRuntimeService.resume();
      return;
    }
    pcConnectionState.block();
    AppStorage.setOrCreate('spaceJoined', false);
    AppStorage.setOrCreate('officialEngineSessionResumed', false);
    await spaceRuntimeSupervisor.shutdown();
    if (this.closing) {
      return;
    }
    pcConnectionState.enable();
    let directory = new SpaceProfileStore().load(context);
    let recovery = await spaceRuntimeSupervisor.restore(context, directory);
    AppStorage.setOrCreate('spaceJoined', recovery.resumed);
    AppStorage.setOrCreate('officialEngineSessionResumed', recovery.resumed);
  }

  setInBackground(background: boolean): void {
    this.inBackground = background;
  }

  isInBackground(): boolean {
    return this.inBackground;
  }

  async shutdown(context: common.Context): Promise<void> {
    this.closing = true;
    pcConnectionState.block();
    let pending: Promise<void> | null = this.operation;
    if (pending !== null) {
      try {
        await pending;
      } catch (error) {
      }
    }
    pcConnectionState.block();
    await spaceRuntimeSupervisor.shutdown();
    this.loaded = false;
    this.closing = false;
  }

  private publish(busy: boolean): void {
    AppStorage.setOrCreate('pcConnectionBusy', busy);
    for (let index: number = 0; index < this.observers.length; index += 1) {
      this.observers[index].onPcConnectionChanged(busy);
    }
  }
}

export const pcConnectionService: PcConnectionService = new PcConnectionService();
