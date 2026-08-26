import assert from 'node:assert/strict';
import test from 'node:test';

import {
  projectActionableDeviceTrustRows
} from '../common/src/main/ets/service/DeviceTrustProjection.ts';

function row(deviceId, displayName, isLocal, reachability, membership, syncRelationship) {
  return {
    device_id: deviceId,
    display_name: displayName,
    is_local: isLocal,
    reachability,
    membership,
    sync_relationship: syncRelationship
  };
}

test('keeps only unique local and actionable remote trust rows', () => {
  const projected = projectActionableDeviceTrustRows([
    row('local-device', 'This Harmony device', true, 'online', 'unknown', 'removed_local_device'),
    row('online-remote', 'Stale online device', false, 'offline', 'removed', 'usable'),
    row('online-remote', 'Active online device', false, 'online', 'active', 'usable'),
    row('offline-remote', 'Active offline device', false, 'offline', 'active', 'usable'),
    row('removed-membership', 'Removed member', false, 'online', 'removed', 'usable'),
    row('removed-peer', 'Removed peer', false, 'online', 'active', 'removed_peer_device'),
    row('history-only', 'Named historic device', false, 'online', 'unknown', 'unknown')
  ], 'local-device');

  assert.deepEqual(projected.map((item) => item.device_id), [
    'local-device',
    'online-remote',
    'offline-remote'
  ]);
  assert.equal(projected[1].display_name, 'Active online device');
  assert.equal(projected[2].reachability, 'offline');
});

for (const [name, sources] of [
  ['explicit local first', [
    row('local-device', 'Explicit local device', true, 'online', 'active', 'usable'),
    row('local-device', 'Historical local device', false, 'offline', 'removed', 'removed_local_device')
  ]],
  ['explicit local last', [
    row('local-device', 'Historical local device', false, 'offline', 'removed', 'removed_local_device'),
    row('local-device', 'Explicit local device', true, 'online', 'active', 'usable')
  ]]
]) {
  test(`prefers the explicit local row when ${name}`, () => {
    const projected = projectActionableDeviceTrustRows(sources, 'local-device');

    assert.equal(projected.length, 1);
    assert.equal(projected[0].display_name, 'Explicit local device');
    assert.equal(projected[0].is_local, true);
    assert.equal(projected[0].reachability, 'online');
    assert.equal(projected[0].sync_relationship, 'usable');
  });
}
