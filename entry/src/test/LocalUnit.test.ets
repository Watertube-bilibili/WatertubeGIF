import { describe, it, expect } from '@ohos/hypium';
import { AppConstants } from '../main/ets/common/Constants';
import { VideoMetadata } from '../main/ets/common/MediaModels';
import { GifPlan, GifPlanningService, GifPlanOptions } from '../main/ets/services/GifPlanningService';

export default function localUnitTest() {
  describe('GifPlanningService', () => {
    it('preserves portrait aspect ratio', 0, () => {
      let metadata: VideoMetadata = new VideoMetadata();
      metadata.width = 1080;
      metadata.height = 1920;
      metadata.durationSeconds = 40;
      let options: GifPlanOptions = new GifPlanOptions();
      options.width = 480;
      options.fps = 12;
      let plan: GifPlan = GifPlanningService.createPlan(options, metadata);

      expect(plan.width).assertEqual(270);
      expect(plan.height).assertEqual(480);
      expect(plan.frames).assertEqual(480);
    });

    it('keeps full two hour duration in recommendations', 0, () => {
      let metadata: VideoMetadata = new VideoMetadata();
      metadata.width = 1920;
      metadata.height = 1080;
      metadata.durationSeconds = AppConstants.MAX_DURATION_SECONDS;
      let recommendation: GifPlanOptions = GifPlanningService.recommend(metadata, 0);
      let plan: GifPlan = GifPlanningService.createPlan(recommendation, metadata);

      expect(recommendation.seconds).assertEqual(0);
      expect(plan.durationSeconds).assertEqual(AppConstants.MAX_DURATION_SECONDS);
      expect(plan.width <= 360).assertTrue();
      expect(plan.fps >= 1).assertTrue();
    });

    it('reports a bounded estimate range', 0, () => {
      let metadata: VideoMetadata = new VideoMetadata();
      metadata.width = 1920;
      metadata.height = 1080;
      metadata.durationSeconds = 30;
      let plan: GifPlan = GifPlanningService.createPlan(new GifPlanOptions(), metadata);

      expect(plan.estimatedLowBytes > 0).assertTrue();
      expect(plan.estimatedHighBytes > plan.estimatedLowBytes).assertTrue();
    });

    it('caps economy preset for small sharing files', 0, () => {
      let metadata: VideoMetadata = new VideoMetadata();
      metadata.width = 3840;
      metadata.height = 2160;
      metadata.durationSeconds = 60;
      let options: GifPlanOptions = new GifPlanOptions();
      options.width = 960;
      options.fps = 30;
      options.quality = AppConstants.QUALITY_ECONOMY;
      let plan: GifPlan = GifPlanningService.createPlan(options, metadata);

      expect(plan.width).assertEqual(280);
      expect(plan.fps).assertEqual(8);
    });

    it('uses economy recommendations for very long video', 0, () => {
      let metadata: VideoMetadata = new VideoMetadata();
      metadata.width = 1920;
      metadata.height = 1080;
      metadata.durationSeconds = 3600;
      let recommendation: GifPlanOptions = GifPlanningService.recommend(metadata, 0);

      expect(recommendation.quality).assertEqual(AppConstants.QUALITY_ECONOMY);
      expect(recommendation.width <= 280).assertTrue();
      expect(recommendation.fps).assertEqual(3);
    });
  });
}
