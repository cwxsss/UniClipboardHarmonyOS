import { describe, expect, it } from '@ohos/hypium';
import {
  EngineMemberSyncPreferences,
  EngineRuntimeDevice,
  EngineRuntimeError,
  EngineRuntimeSnapshot,
  EngineRuntimeState,
  EngineSessionRecovery,
  EngineWorkspaceConvergence
} from 'common';
import {
  ClipboardFeatureController,
  ClipboardFeatureControllerRuntime,
  SpaceDeviceRemovalInteraction
} from '../main/ets/viewmodel/ClipboardFeatureController';

class FakeControllerRuntime implements ClipboardFeatureControllerRuntime {
  removeCount: number = 0;
  queryCount: number = 0;
  autoSendTargets: string[] = [];
  snapshotRows: EngineRuntimeDevice[] = [];
  removeError: EngineRuntimeError | null = null;

  getSnapshot(): EngineRuntimeSnapshot {
    return new EngineRuntimeSnapshot(EngineRuntimeState.RUNNING);
  }

  async prepare(): Promise<void> {
  }

  async start(): Promise<void> {
  }

  async recoverSession(allowSecureStorageUnlock: boolean): Promise<EngineSessionRecovery> {
    return new EngineSessionRecovery(true, false);
  }

  async removeMember(deviceId: string): Promise<EngineWorkspaceConvergence> {
    this.removeCount += 1;
    if (this.removeError !== null) {
      throw this.removeError;
    }
    return new EngineWorkspaceConvergence('complete', 1, 1);
  }

  async queryDevices(): Promise<EngineRuntimeDevice[]> {
    this.queryCount += 1;
    let actionable: EngineRuntimeDevice[] = [];
    for (let index: number = 0; index < this.snapshotRows.length; index += 1) {
      let row: EngineRuntimeDevice = this.snapshotRows[index];
      if (row.isLocal || row.state === 'usable') {
        actionable.push(row);
      }
    }
    return actionable;
  }

  setClipboardAutoSendTargets(targetDevices: string[]): void {
    this.autoSendTargets = targetDevices.slice();
  }

  async queryMemberSyncPreferences(deviceId: string): Promise<EngineMemberSyncPreferences> {
    return new EngineMemberSyncPreferences(true, true, true, true, true, true, true);
  }
}

class FakeRemovalInteraction implements SpaceDeviceRemovalInteraction {
  confirmationIndex: number = 1;
  confirmationCount: number = 0;
  successCount: number = 0;

  async confirmSpaceDeviceRemoval(): Promise<number> {
    this.confirmationCount += 1;
    return this.confirmationIndex;
  }

  reportSpaceDeviceRemovalSuccess(): void {
    this.successCount += 1;
  }
}

function localDevice(): EngineRuntimeDevice {
  return new EngineRuntimeDevice('local-device', 'This phone', true, true, 'usable', 'online');
}

function offlineRemote(): EngineRuntimeDevice {
  return new EngineRuntimeDevice('offline-peer', 'Offline desktop', false, false, 'usable', 'offline');
}

function removedHistory(): EngineRuntimeDevice {
  return new EngineRuntimeDevice('offline-peer', 'Removed desktop history', false, false,
    'removed_peer_device', 'offline');
}

function readyController(runtime: FakeControllerRuntime,
  interaction: FakeRemovalInteraction): ClipboardFeatureController {
  let controller: ClipboardFeatureController = new ClipboardFeatureController(runtime, interaction);
  controller.spaceJoined = true;
  controller.spaceNodeState = 2;
  controller.spaceDevices = [offlineRemote(), localDevice()];
  controller.desktopSelectedSpaceDeviceId = 'offline-peer';
  controller.desktopSelectedSpaceDeviceIsLocal = false;
  runtime.setClipboardAutoSendTargets(['offline-peer']);
  return controller;
}

export default function clipboardFeatureControllerTest(): void {
  describe('ClipboardFeatureController device removal', (): void => {
    it('keeps a removed offline peer absent and clears its selected send target', 0,
      async (): Promise<void> => {
        let runtime: FakeControllerRuntime = new FakeControllerRuntime();
        let interaction: FakeRemovalInteraction = new FakeRemovalInteraction();
        let controller: ClipboardFeatureController = readyController(runtime, interaction);
        runtime.snapshotRows = [removedHistory(), localDevice()];

        await controller.revokeSpaceDevice(offlineRemote());

        expect(controller.spaceDevices.length).assertEqual(1);
        expect(controller.spaceDevices[0].deviceId).assertEqual('local-device');
        expect(controller.desktopSelectedSpaceDeviceId).assertEqual('');
        expect(runtime.autoSendTargets.length).assertEqual(0);
        expect(runtime.removeCount).assertEqual(1);
        expect(runtime.queryCount).assertEqual(1);
        expect(interaction.successCount).assertEqual(1);
        expect(controller.statusCode).assertEqual(2);
      });

    it('treats remove-member not-found as success only after an absent authoritative refresh', 0,
      async (): Promise<void> => {
        let runtime: FakeControllerRuntime = new FakeControllerRuntime();
        let interaction: FakeRemovalInteraction = new FakeRemovalInteraction();
        let controller: ClipboardFeatureController = readyController(runtime, interaction);
        runtime.removeError = new EngineRuntimeError('not_found', 'remove_member');
        runtime.snapshotRows = [removedHistory(), localDevice()];

        await controller.revokeSpaceDevice(offlineRemote());

        expect(runtime.queryCount).assertEqual(1);
        expect(controller.desktopSelectedSpaceDeviceId).assertEqual('');
        expect(runtime.autoSendTargets.length).assertEqual(0);
        expect(interaction.successCount).assertEqual(1);
        expect(controller.statusCode).assertEqual(2);
        expect(controller.recentErrors.length).assertEqual(0);
      });

    it('does not suppress remove-member not-found while the peer is still actionable', 0,
      async (): Promise<void> => {
        let runtime: FakeControllerRuntime = new FakeControllerRuntime();
        let interaction: FakeRemovalInteraction = new FakeRemovalInteraction();
        let controller: ClipboardFeatureController = readyController(runtime, interaction);
        runtime.removeError = new EngineRuntimeError('not_found', 'remove_member');
        runtime.snapshotRows = [offlineRemote(), localDevice()];

        await controller.revokeSpaceDevice(offlineRemote());

        expect(runtime.queryCount).assertEqual(1);
        expect(interaction.successCount).assertEqual(0);
        expect(controller.statusCode).assertEqual(3);
        expect(controller.recentErrors.length).assertEqual(1);
      });

    it('does not suppress non-not-found removal errors', 0, async (): Promise<void> => {
      let runtime: FakeControllerRuntime = new FakeControllerRuntime();
      let interaction: FakeRemovalInteraction = new FakeRemovalInteraction();
      let controller: ClipboardFeatureController = readyController(runtime, interaction);
      runtime.removeError = new EngineRuntimeError('engine_unavailable', 'remove_member', 'transport failed');
      runtime.snapshotRows = [localDevice()];

      await controller.revokeSpaceDevice(offlineRemote());

      expect(runtime.queryCount).assertEqual(0);
      expect(interaction.successCount).assertEqual(0);
      expect(controller.statusCode).assertEqual(3);
      expect(controller.recentErrors.length).assertEqual(1);
    });

    it('does nothing when removal is cancelled', 0, async (): Promise<void> => {
      let runtime: FakeControllerRuntime = new FakeControllerRuntime();
      let interaction: FakeRemovalInteraction = new FakeRemovalInteraction();
      interaction.confirmationIndex = 0;
      let controller: ClipboardFeatureController = readyController(runtime, interaction);

      await controller.revokeSpaceDevice(offlineRemote());

      expect(runtime.removeCount).assertEqual(0);
      expect(runtime.queryCount).assertEqual(0);
      expect(interaction.successCount).assertEqual(0);
      expect(controller.spaceDevices.length).assertEqual(2);
    });

    it('does not offer removal for the local device', 0, async (): Promise<void> => {
      let runtime: FakeControllerRuntime = new FakeControllerRuntime();
      let interaction: FakeRemovalInteraction = new FakeRemovalInteraction();
      let controller: ClipboardFeatureController = readyController(runtime, interaction);

      await controller.revokeSpaceDevice(localDevice());

      expect(interaction.confirmationCount).assertEqual(0);
      expect(runtime.removeCount).assertEqual(0);
      expect(runtime.queryCount).assertEqual(0);
      expect(interaction.successCount).assertEqual(0);
    });
  });

  describe('ClipboardFeatureController space admission', (): void => {
    it('allows an existing member to join another space without re-entering the device name', 0,
      async (): Promise<void> => {
        let runtime: FakeControllerRuntime = new FakeControllerRuntime();
        let interaction: FakeRemovalInteraction = new FakeRemovalInteraction();
        let controller: ClipboardFeatureController = readyController(runtime, interaction);
        controller.spaceInvitationCode = 'ABCD-1234';
        controller.spacePassphrase = 'correct horse battery staple';
        controller.spaceJoinDeviceName = '';

        expect(controller.canJoinSpace()).assertTrue();
      });

    it('still requires a device name for the first space admission', 0,
      async (): Promise<void> => {
        let runtime: FakeControllerRuntime = new FakeControllerRuntime();
        let interaction: FakeRemovalInteraction = new FakeRemovalInteraction();
        let controller: ClipboardFeatureController = new ClipboardFeatureController(runtime, interaction);
        controller.spaceNodeState = 2;
        controller.spaceInvitationCode = 'ABCD-1234';
        controller.spacePassphrase = 'correct horse battery staple';

        expect(controller.canJoinSpace()).assertFalse();
        controller.spaceJoinDeviceName = 'This phone';
        expect(controller.canJoinSpace()).assertTrue();
      });
  });
}
