import { describe, expect, it } from '@ohos/hypium';
import { ApplicationVersionService } from '../main/ets/service/ApplicationVersionService';

export default function applicationVersionServiceTest(): void {
  describe('ApplicationVersionService', (): void => {
    it('formats the user-visible version with the numeric version code', 0,
      (): void => {
        expect(ApplicationVersionService.format('1.0.6', 1000007))
          .assertEqual('版本 1.0.6（1000007）');
      });

    it('keeps the numeric version code visible when the version name is unavailable', 0,
      (): void => {
        expect(ApplicationVersionService.format('', 1000007))
          .assertEqual('版本未知（1000007）');
      });
  });
}
