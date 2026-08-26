export class EngineDeviceTrustRelationshipPayload {
  device_id: string = '';
  display_name: string = '';
  is_local: boolean = false;
  reachability: string = 'unknown';
  membership: string = 'unknown';
  sync_relationship: string = 'unknown';
}

export class EngineDeviceTrustSnapshotPayload {
  local_device_id: string = '';
  devices: EngineDeviceTrustRelationshipPayload[] = [];
}

export function deviceTrustRowPriority(source: EngineDeviceTrustRelationshipPayload,
  localDeviceId: string): number {
  if (source.is_local) {
    return 2;
  }
  if (source.device_id === localDeviceId) {
    return 1;
  }
  return 0;
}

export function projectActionableDeviceTrustRows(sources: EngineDeviceTrustRelationshipPayload[],
  localDeviceId: string): EngineDeviceTrustRelationshipPayload[] {
  let actionable: EngineDeviceTrustRelationshipPayload[] = [];
  for (let sourceIndex: number = 0; sourceIndex < sources.length; sourceIndex += 1) {
    let source: EngineDeviceTrustRelationshipPayload = sources[sourceIndex];
    let sourcePriority: number = deviceTrustRowPriority(source, localDeviceId);
    let isLocal: boolean = sourcePriority > 0;
    let isActionableRemote: boolean = source.membership === 'active' &&
      source.sync_relationship === 'usable';
    if (!isLocal && !isActionableRemote) {
      continue;
    }
    let existingIndex: number = -1;
    for (let actionableIndex: number = 0; actionableIndex < actionable.length; actionableIndex += 1) {
      if (actionable[actionableIndex].device_id === source.device_id) {
        existingIndex = actionableIndex;
        break;
      }
    }
    if (existingIndex < 0) {
      actionable.push(source);
    } else if (sourcePriority > deviceTrustRowPriority(actionable[existingIndex], localDeviceId)) {
      actionable[existingIndex] = source;
    }
  }
  return actionable;
}
