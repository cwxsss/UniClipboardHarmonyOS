import engineRuntimeServiceTest from './EngineRuntimeService.test';
import engineClipboardHostTest from './EngineClipboardHost.test';

export default function tests(): void {
  engineRuntimeServiceTest();
  engineClipboardHostTest();
}
