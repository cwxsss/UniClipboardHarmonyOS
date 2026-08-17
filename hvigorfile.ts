// @ts-nocheck – Template file, only used when copied into a project directory
import { appTasks } from '@ohos/hvigor-ohos-plugin';
import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';

const powershellCommand = process.platform === 'win32' ? 'powershell.exe' : 'pwsh';
execFileSync(powershellCommand, [
  '-NoProfile',
  '-ExecutionPolicy',
  'Bypass',
  '-File',
  resolve(process.cwd(), 'rust', 'verify-engine-release.ps1')
], { stdio: 'inherit' });

export default {
  system: appTasks /* Built-in plugin of Hvigor. It cannot be modified. */,
  plugins: [] /* Custom plugin to extend the functionality of Hvigor. */,
};
