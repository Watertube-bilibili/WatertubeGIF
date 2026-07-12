import { common, WantAgent, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { liveViewManager } from '@kit.LiveViewKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'LongTaskService';
const DOMAIN: number = 0xFF02;
const LIVE_VIEW_ID: number = 1024;
const LIVE_VIEW_EVENT: string = 'PROGRESS';
const ACCENT_COLOR: string = '#FF0A59F7';
const TRACK_COLOR: string = '#FFE2ECFF';

export class LongTaskService {
  private static instance: LongTaskService;
  private isTaskRunning: boolean = false;
  private isBackgroundRunning: boolean = false;
  private isLiveViewRunning: boolean = false;
  private currentProgress: number = -1;
  private sequence: number = 0;
  private clickAgent: WantAgent | undefined = undefined;

  private constructor() {
  }

  static getInstance(): LongTaskService {
    if (!LongTaskService.instance) {
      LongTaskService.instance = new LongTaskService();
    }
    return LongTaskService.instance;
  }

  async startContinuousTask(context: common.UIAbilityContext, title: string, initialMessage: string,
    backgroundEnabled: boolean = true, liveViewEnabled: boolean = true): Promise<void> {
    if (this.isTaskRunning) {
      return;
    }
    this.isTaskRunning = true;
    this.currentProgress = 0;
    this.sequence = 1;
    this.clickAgent = await this.buildClickAgent(context);

    if (backgroundEnabled && this.clickAgent !== undefined) {
      try {
        await backgroundTaskManager.startBackgroundRunning(context, ['taskKeeping'], this.clickAgent);
        this.isBackgroundRunning = true;
        hilog.info(DOMAIN, TAG, 'Continuous task started');
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'Background task is unavailable');
      }
    }

    if (liveViewEnabled) {
      await this.startLiveView(title, initialMessage);
    }
  }

  async stopContinuousTask(context: common.UIAbilityContext, succeeded: boolean = true,
    message: string = '转换已结束'): Promise<void> {
    if (!this.isTaskRunning) {
      return;
    }

    await this.stopLiveView(succeeded, message);
    if (this.isBackgroundRunning) {
      try {
        await backgroundTaskManager.stopBackgroundRunning(context);
        hilog.info(DOMAIN, TAG, 'Continuous task stopped');
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'Failed to stop background task');
      }
    }

    this.isTaskRunning = false;
    this.isBackgroundRunning = false;
    this.isLiveViewRunning = false;
    this.currentProgress = -1;
    this.clickAgent = undefined;
  }

  async updateLiveViewProgress(progress: number, message: string): Promise<void> {
    let normalized: number = Math.max(0, Math.min(100, Math.round(progress)));
    if (!this.isTaskRunning || !this.isLiveViewRunning || this.currentProgress === normalized) {
      return;
    }

    this.currentProgress = normalized;
    this.sequence++;
    try {
      let result: liveViewManager.LiveViewResult = await liveViewManager.updateLiveView(
        this.buildLiveView('GIF 转换中', message, normalized, 0)
      );
      if (result.resultCode !== 0) {
        hilog.warn(DOMAIN, TAG, 'LiveView update rejected');
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Failed to update LiveView');
    }
  }

  private async buildClickAgent(context: common.UIAbilityContext): Promise<WantAgent | undefined> {
    let wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: context.applicationInfo.name,
          abilityName: context.abilityInfo.name,
          parameters: {
            fromLiveView: true
          }
        }
      ],
      operationType: wantAgent.OperationType.START_ABILITY,
      requestCode: LIVE_VIEW_ID,
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    try {
      return await wantAgent.getWantAgent(wantAgentInfo);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Failed to create click action');
      return undefined;
    }
  }

  private buildLiveView(title: string, message: string, progress: number,
    keepTime: number): liveViewManager.LiveView {
    let content: liveViewManager.RichText[] = [
      { text: message },
      { text: '  ' + progress.toString() + '%', textColor: ACCENT_COLOR }
    ];
    return {
      id: LIVE_VIEW_ID,
      event: LIVE_VIEW_EVENT,
      sequence: this.sequence,
      isMute: true,
      liveViewData: {
        primary: {
          title: title,
          content: content,
          keepTime: keepTime,
          clickAction: this.clickAgent,
          layoutData: {
            layoutType: liveViewManager.LayoutType.LAYOUT_TYPE_PROGRESS,
            progress: progress,
            color: ACCENT_COLOR,
            backgroundColor: TRACK_COLOR,
            indicatorType: liveViewManager.IndicatorType.INDICATOR_TYPE_UNDISPLAYED,
            lineType: liveViewManager.LineType.LINE_TYPE_THICK_SOLID_LINE
          }
        },
        capsule: {
          type: liveViewManager.CapsuleType.CAPSULE_TYPE_PROGRESS,
          status: 1,
          max: 100,
          progress: progress,
          content: progress.toString() + '%',
          backgroundColor: ACCENT_COLOR,
          indeterminate: false,
          isContentDisplayed: true
        }
      }
    };
  }

  private async startLiveView(title: string, message: string): Promise<void> {
    try {
      let enabled: boolean = await liveViewManager.isLiveViewEnabled();
      if (!enabled) {
        hilog.info(DOMAIN, TAG, 'LiveView is disabled by user or unavailable');
        return;
      }
      await this.clearStaleLiveView();
      let result: liveViewManager.LiveViewResult = await liveViewManager.startLiveView(
        this.buildLiveView(title, message, 0, 0)
      );
      this.isLiveViewRunning = result.resultCode === 0;
      if (this.isLiveViewRunning) {
        hilog.info(DOMAIN, TAG, 'LiveView started');
      } else {
        hilog.warn(DOMAIN, TAG, 'LiveView start rejected');
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'LiveView is unavailable or right is not enabled');
    }
  }

  private async clearStaleLiveView(): Promise<void> {
    try {
      let staleView: liveViewManager.LiveView = await liveViewManager.getActiveLiveView(LIVE_VIEW_ID);
      staleView.sequence = (staleView.sequence ?? 0) + 1;
      await liveViewManager.stopLiveView(staleView);
      hilog.info(DOMAIN, TAG, 'Stale LiveView cleared');
    } catch (error) {
      // No active LiveView with this id is the expected state for a new conversion.
    }
  }

  private async stopLiveView(succeeded: boolean, message: string): Promise<void> {
    if (!this.isLiveViewRunning) {
      return;
    }
    this.sequence++;
    let finalProgress: number = succeeded ? 100 : Math.max(0, this.currentProgress);
    let title: string = succeeded ? 'GIF 转换完成' : 'GIF 转换未完成';
    try {
      let result: liveViewManager.LiveViewResult = await liveViewManager.stopLiveView(
        this.buildLiveView(title, message, finalProgress, 15)
      );
      if (result.resultCode === 0) {
        hilog.info(DOMAIN, TAG, 'LiveView stopped');
      } else {
        hilog.warn(DOMAIN, TAG, 'LiveView stop rejected');
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Failed to stop LiveView');
    }
  }
}
