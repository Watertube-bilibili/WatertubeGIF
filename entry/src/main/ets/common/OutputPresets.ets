import { AppConstants } from './Constants';

export class OutputPreset {
  quality: number = AppConstants.DEFAULT_QUALITY;
  label: string = '均衡质量';
  shortLabel: string = '均衡';
  description: string = '480px · 12fps';
  width: number = AppConstants.DEFAULT_WIDTH;
  fps: number = AppConstants.DEFAULT_FPS;

  constructor(quality: number, label: string, shortLabel: string, description: string,
    width: number, fps: number) {
    this.quality = quality;
    this.label = label;
    this.shortLabel = shortLabel;
    this.description = description;
    this.width = width;
    this.fps = fps;
  }
}

export class OutputPresetService {
  static resolve(quality: number): OutputPreset {
    if (quality === AppConstants.QUALITY_ECONOMY) {
      return new OutputPreset(quality, '省流低清', '省流', '240px · 6fps', 240, 6);
    }
    if (quality === AppConstants.QUALITY_WECHAT) {
      return new OutputPreset(quality, '微信清晰', '微信', '360px · 10fps', 360, 10);
    }
    if (quality === AppConstants.QUALITY_ULTRA) {
      return new OutputPreset(quality, '超高质量', '超高', '720px · 20fps', 720, 20);
    }
    return new OutputPreset(AppConstants.QUALITY_MEDIUM, '均衡质量', '均衡', '480px · 12fps',
      AppConstants.DEFAULT_WIDTH, AppConstants.DEFAULT_FPS);
  }
}
