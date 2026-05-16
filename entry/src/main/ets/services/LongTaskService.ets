import { common, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { liveViewManager } from '@kit.LiveViewKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'LongTaskService';
const DOMAIN: number = 0xFF02;
const LIVE_VIEW_ID: number = 1024;

export class LongTaskService {
  private static instance: LongTaskService;
  private isTaskRunning: boolean = false;
  private currentProgress: number = 0;

  private constructor() {
  }

  static getInstance(): LongTaskService {
    if (!LongTaskService.instance) {
      LongTaskService.instance = new LongTaskService();
    }
    return LongTaskService.instance;
  }

  async startContinuousTask(context: common.UIAbilityContext, title: string, initialMessage: string): Promise<void> {
    if (this.isTaskRunning) {
      return;
    }

    let wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: context.applicationInfo.name,
          abilityName: context.abilityInfo.name
        }
      ],
      operationType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };

    try {
      let agent = await wantAgent.getWantAgent(wantAgentInfo);
      await backgroundTaskManager.startBackgroundRunning(context, ['taskKeeping'], agent);
      this.isTaskRunning = true;
      await this.startLiveView(title, initialMessage);
      hilog.info(DOMAIN, TAG, 'Continuous task started');
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to start background task');
    }
  }

  async stopContinuousTask(context: common.UIAbilityContext): Promise<void> {
    if (!this.isTaskRunning) {
      return;
    }

    try {
      await backgroundTaskManager.stopBackgroundRunning(context);
      await this.stopLiveView();
      hilog.info(DOMAIN, TAG, 'Continuous task stopped');
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to stop background task');
    } finally {
      this.isTaskRunning = false;
    }
  }

  private buildLiveView(title: string, message: string, progress: number): liveViewManager.LiveView {
    return {
      id: LIVE_VIEW_ID,
      event: 'PROCESS',
      liveViewData: {
        primary: {
          title: title,
          content: [{ text: message }],
          layoutData: {
            layoutType: liveViewManager.LayoutType.LAYOUT_TYPE_PROGRESS,
            progress: progress,
            color: '#2F7DFF',
            backgroundColor: '#D6E6FF'
          }
        },
        capsule: {
          type: liveViewManager.CapsuleType.CAPSULE_TYPE_PROGRESS,
          status: 1,
          max: 100,
          progress: progress,
          content: progress + '%',
          backgroundColor: '#2F7DFF',
          indeterminate: false
        }
      }
    };
  }

  private async startLiveView(title: string, message: string): Promise<void> {
    try {
      this.currentProgress = 0;
      await liveViewManager.startLiveView(this.buildLiveView(title, message, 0));
      hilog.info(DOMAIN, TAG, 'LiveView started');
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to start LiveView');
    }
  }

  async updateLiveViewProgress(progress: number, message: string): Promise<void> {
    if (!this.isTaskRunning || this.currentProgress === progress) {
      return;
    }

    this.currentProgress = progress;
    try {
      await liveViewManager.updateLiveView(this.buildLiveView('GIF 转换中', message, progress));
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to update LiveView');
    }
  }

  private async stopLiveView(): Promise<void> {
    try {
      await liveViewManager.stopLiveView(this.buildLiveView('GIF 转换', '转换已结束', 100));
      hilog.info(DOMAIN, TAG, 'LiveView stopped');
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to stop LiveView');
    }
  }
}
