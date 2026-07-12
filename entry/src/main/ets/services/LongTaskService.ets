import { common, WantAgent, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { liveViewManager } from '@kit.LiveViewKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG: string = 'LongTaskService';
const DOMAIN: number = 0xFF02;
const LIVE_VIEW_ID: number = 1024;
const LIVE_VIEW_EVENT: string = 'PROGRESS';
const ACCENT_COLOR: string = '#FF0A59F7';
const TRACK_COLOR: string = '#FFE2ECFF';

export class CapabilityResult {
  available: boolean = false;
  code: number = 0;
  message: string = '';
}

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
      await this.startMediaProcessingTask(context, this.clickAgent);
    }

    if (liveViewEnabled) {
      await this.startLiveView(title, initialMessage);
    }
  }

  async checkBackgroundCapability(context: common.UIAbilityContext): Promise<CapabilityResult> {
    return await this.resolveBackgroundCapability(context, false);
  }

  async requestBackgroundAuthorization(context: common.UIAbilityContext): Promise<CapabilityResult> {
    return await this.resolveBackgroundCapability(context, true);
  }

  async checkLiveViewCapability(): Promise<CapabilityResult> {
    let result: CapabilityResult = new CapabilityResult();
    try {
      result.available = await liveViewManager.isLiveViewEnabled();
      result.code = result.available ? 0 : 1003500004;
      result.message = result.available ? '系统实况窗开关已开启' :
        '系统未允许实况窗；若列表中无本应用，需先开通 AppGallery Connect 权益';
    } catch (error) {
      result.code = this.businessErrorCode(error);
      result.message = '设备暂不支持实况窗';
    }
    return result;
  }

  async testLiveView(context: common.UIAbilityContext): Promise<CapabilityResult> {
    let result: CapabilityResult = new CapabilityResult();
    if (this.isTaskRunning) {
      result.message = '转换任务运行中，无需重复测试';
      return result;
    }
    try {
      this.clickAgent = await this.buildClickAgent(context);
      this.sequence = 1;
      await this.clearStaleLiveView();
      let startResult: liveViewManager.LiveViewResult = await liveViewManager.startLiveView(
        this.buildLiveView('实况窗测试', '水管 GIF 已连接系统实况窗', 50, 0)
      );
      if (startResult.resultCode !== 0) {
        result.code = startResult.resultCode;
        result.message = '实况窗测试被系统拒绝，错误码 ' + startResult.resultCode.toString();
        return result;
      }
      this.sequence++;
      await liveViewManager.stopLiveView(
        this.buildLiveView('实况窗测试成功', '连接正常', 100, 5)
      );
      result.available = true;
      result.message = '实况窗测试成功，转换时会显示进度';
      return result;
    } catch (error) {
      result.code = this.businessErrorCode(error);
      if (result.code === 1003500005) {
        result.message = '当前包名尚未开通 AppGallery Connect 实况窗权益';
      } else if (result.code === 1003500004) {
        result.message = '请先在系统设置中开启本应用的实况窗';
      } else {
        result.message = '实况窗测试失败，错误码 ' + result.code.toString();
      }
      return result;
    } finally {
      this.clickAgent = undefined;
      this.sequence = 0;
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

  private buildMediaProcessingRequest(clickAgent: WantAgent): backgroundTaskManager.ContinuousTaskRequest {
    let request: backgroundTaskManager.ContinuousTaskRequest = new backgroundTaskManager.ContinuousTaskRequest();
    request.backgroundTaskModes = [
      backgroundTaskManager.BackgroundTaskMode.MODE_SPECIAL_SCENARIO_PROCESSING
    ];
    request.backgroundTaskSubmodes = [
      backgroundTaskManager.BackgroundTaskSubmode.SUBMODE_MEDIA_PROCESS_NORMAL_NOTIFICATION
    ];
    request.wantAgent = clickAgent;
    request.combinedTaskNotification = false;
    return request;
  }

  private isGranted(result: backgroundTaskManager.UserAuthResult): boolean {
    return result === backgroundTaskManager.UserAuthResult.GRANTED_ONCE ||
      result === backgroundTaskManager.UserAuthResult.GRANTED_ALWAYS;
  }

  private async askBackgroundAuthorization(context: common.UIAbilityContext,
    request: backgroundTaskManager.ContinuousTaskRequest): Promise<backgroundTaskManager.UserAuthResult> {
    return await new Promise<backgroundTaskManager.UserAuthResult>((resolve) => {
      request.requestAuthFromUser(context, (result: backgroundTaskManager.UserAuthResult) => {
        resolve(result);
      });
    });
  }

  private async resolveBackgroundCapability(context: common.UIAbilityContext,
    requestAuthorization: boolean): Promise<CapabilityResult> {
    let result: CapabilityResult = new CapabilityResult();
    try {
      let clickAgent: WantAgent | undefined = await this.buildClickAgent(context);
      if (clickAgent === undefined) {
        result.message = '无法创建后台通知点击动作';
        return result;
      }
      let request: backgroundTaskManager.ContinuousTaskRequest = this.buildMediaProcessingRequest(clickAgent);
      if (!request.isModeSupported()) {
        result.code = backgroundTaskManager.UserAuthResult.NOT_SUPPORTED;
        result.message = '当前设备不支持媒体处理后台长任务';
        return result;
      }
      let authResult: backgroundTaskManager.UserAuthResult = await request.checkSpecialScenarioAuth(context);
      if (authResult === backgroundTaskManager.UserAuthResult.NOT_DETERMINED && requestAuthorization) {
        authResult = await this.askBackgroundAuthorization(context, request);
      }
      result.code = authResult;
      result.available = this.isGranted(authResult);
      if (result.available) {
        result.message = authResult === backgroundTaskManager.UserAuthResult.GRANTED_ALWAYS ?
          '媒体处理后台权限已永久允许' : '媒体处理后台权限已允许一次';
      } else if (authResult === backgroundTaskManager.UserAuthResult.DENIED) {
        result.message = '后台权限已被拒绝，需在系统设置中重新允许';
      } else if (authResult === backgroundTaskManager.UserAuthResult.NOT_DETERMINED) {
        result.message = '后台权限尚未授权';
      } else {
        result.message = '当前设备不支持媒体处理后台长任务';
      }
    } catch (error) {
      result.code = this.businessErrorCode(error);
      result.message = '后台能力检查失败，错误码 ' + result.code.toString();
    }
    return result;
  }

  private async startMediaProcessingTask(context: common.UIAbilityContext, clickAgent: WantAgent): Promise<void> {
    try {
      let capability: CapabilityResult = await this.resolveBackgroundCapability(context, true);
      if (capability.available) {
        let request: backgroundTaskManager.ContinuousTaskRequest = this.buildMediaProcessingRequest(clickAgent);
        await backgroundTaskManager.startBackgroundRunning(context, request);
        this.isBackgroundRunning = true;
        hilog.info(DOMAIN, TAG, 'Media processing background task started');
        return;
      }
      if (capability.code === backgroundTaskManager.UserAuthResult.NOT_SUPPORTED) {
        await backgroundTaskManager.startBackgroundRunning(context, ['taskKeeping'], clickAgent);
        this.isBackgroundRunning = true;
        hilog.info(DOMAIN, TAG, 'Legacy taskKeeping background task started');
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Background task start failed, code: %{public}d', this.businessErrorCode(error));
    }
  }

  private businessErrorCode(error: Object): number {
    let businessError: BusinessError = error as BusinessError;
    return businessError.code ?? -1;
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
      hilog.warn(DOMAIN, TAG, 'LiveView start failed, code: %{public}d', this.businessErrorCode(error));
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
