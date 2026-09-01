import { bundleManager } from '@kit.AbilityKit';

export class ApplicationVersionInfo {
  versionName: string = '';
  versionCode: number = 0;

  constructor(versionName: string, versionCode: number) {
    this.versionName = versionName;
    this.versionCode = versionCode;
  }
}

export class ApplicationVersionService {
  static getSelf(): ApplicationVersionInfo {
    let bundleInfo: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    return new ApplicationVersionInfo(bundleInfo.versionName, bundleInfo.versionCode);
  }

  static format(versionName: string, versionCode: number): string {
    if (versionName.length === 0) {
      return '版本未知（' + versionCode.toString() + '）';
    }
    return '版本 ' + versionName + '（' + versionCode.toString() + '）';
  }
}
