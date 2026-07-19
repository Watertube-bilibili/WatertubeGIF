export class AppConstants {
  static readonly APP_NAME: string = '水管 GIF';
  static readonly DEFAULT_WIDTH: number = 480;
  static readonly DEFAULT_FPS: number = 12;
  static readonly DEFAULT_DURATION_SECONDS: number = 0;
  static readonly QUALITY_WECHAT: number = 0;
  static readonly QUALITY_MEDIUM: number = 1;
  static readonly QUALITY_ULTRA: number = 2;
  static readonly QUALITY_ECONOMY: number = 3;
  static readonly DEFAULT_QUALITY: number = AppConstants.QUALITY_MEDIUM;
  static readonly MAX_DURATION_SECONDS: number = 2 * 60 * 60;
  static readonly MAX_FRAMES: number = 360;
  static readonly MAX_FRAMES_WECHAT: number = 180;
  static readonly MAX_FRAMES_ULTRA: number = 720;
  static readonly MAX_PIXELS_IN_MEMORY: number = 120 * 1024 * 1024;
  static readonly MAX_PIXELS_IN_MEMORY_WECHAT: number = 72 * 1024 * 1024;
  static readonly MAX_PIXELS_IN_MEMORY_ULTRA: number = 180 * 1024 * 1024;
}
