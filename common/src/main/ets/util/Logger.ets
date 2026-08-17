import { hilog } from '@kit.PerformanceAnalysisKit';

const LOG_DOMAIN: number = 0xC1B0;

export class Logger {
  private readonly tag: string;

  constructor(tag: string) {
    this.tag = tag;
  }

  debug(message: string): void {
    hilog.debug(LOG_DOMAIN, this.tag, '%{public}s', message);
  }

  info(message: string): void {
    hilog.info(LOG_DOMAIN, this.tag, '%{public}s', message);
  }

  warn(message: string): void {
    hilog.warn(LOG_DOMAIN, this.tag, '%{public}s', message);
  }

  error(message: string): void {
    hilog.error(LOG_DOMAIN, this.tag, '%{public}s', message);
  }
}
