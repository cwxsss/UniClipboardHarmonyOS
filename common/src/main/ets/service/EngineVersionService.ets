import engine from '@uniclipboard/engine';

export class EngineVersionService {
  static getVersion(): string {
    return engine.coreVersion();
  }
}
