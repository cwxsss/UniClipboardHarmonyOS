import engineRuntimeServiceTest from './EngineRuntimeService.test';
import engineClipboardHostTest from './EngineClipboardHost.test';
import applicationVersionServiceTest from './ApplicationVersionService.test';

export default function tests(): void {
  engineRuntimeServiceTest();
  engineClipboardHostTest();
  applicationVersionServiceTest();
}
