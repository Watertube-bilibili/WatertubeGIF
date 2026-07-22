import { common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { ComposeListItem, SegmentButton, SegmentButtonOptions, promptAction, router } from '@kit.ArkUI';
import { AppConstants } from '../common/Constants';
import { Theme } from '../common/Theme';
import { SymbolBySymbolName } from '../components/SymbolBySymbolName';
import { AppSettings, AppStateService } from '../services/AppStateService';
import { CapabilityResult, LongTaskService } from '../services/LongTaskService';
import { MaterialCapability, MaterialService } from '../services/MaterialService';
import { OutputPreset, OutputPresetService } from '../common/OutputPresets';

@Component
export struct SettingsPage {
  @Prop embedded: boolean = false;
  openToolbox: () => void = () => {};
  @StorageProp('currentColorMode') colorMode: number = 1;
  @State defaultQuality: number = AppConstants.DEFAULT_QUALITY;
  @State defaultWidth: number = AppConstants.DEFAULT_WIDTH;
  @State defaultFps: number = AppConstants.DEFAULT_FPS;
  @State backgroundEnabled: boolean = true;
  @State liveViewEnabled: boolean = true;
  @State systemLiveViewEnabled: boolean = false;
  @State checkingLiveView: boolean = false;
  @State stealthNames: boolean = false;
  @State smartSizeEnabled: boolean = true;
  @State protectedHistoryCount: number = 0;
  @State backgroundStatus: string = '正在检查系统授权';
  @State liveViewStatus: string = '正在检查系统状态';
  @State saveStatus: string = '设置已加载';
  @State testingLiveView: boolean = false;
  @State requestingBackground: boolean = false;
  @StorageLink('lightSenseEnabled') lightSenseEnabled: boolean = true;
  @State materialCapability: MaterialCapability = new MaterialCapability();
  @State qualityIndexes: number[] = [2];
  @State widthIndexes: number[] = [2];
  @State fpsIndexes: number[] = [2];
  @State qualityOptions: SegmentButtonOptions = SegmentButtonOptions.tab({
    buttons: [{ text: '省流' }, { text: '微信' }, { text: '均衡' }, { text: '超高' }]
  });
  @State widthOptions: SegmentButtonOptions = SegmentButtonOptions.tab({
    buttons: [{ text: '240 px' }, { text: '360 px' }, { text: '480 px' }, { text: '720 px' }]
  });
  @State fpsOptions: SegmentButtonOptions = SegmentButtonOptions.tab({
    buttons: [{ text: '6 fps' }, { text: '10 fps' }, { text: '12 fps' }, { text: '20 fps' }]
  });

  private ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private sdkApiVersion: number = deviceInfo.sdkApiVersion;

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    let settings: AppSettings = await AppStateService.loadSettings(this.ctx);
    this.defaultQuality = settings.defaultQuality;
    this.defaultWidth = settings.defaultWidth;
    this.defaultFps = settings.defaultFps;
    this.backgroundEnabled = settings.backgroundEnabled;
    this.liveViewEnabled = settings.liveViewEnabled;
    this.lightSenseEnabled = settings.lightSenseEnabled;
    this.materialCapability = MaterialService.checkCapability();
    this.stealthNames = settings.stealthNames;
    this.smartSizeEnabled = settings.smartSizeEnabled;
    this.syncSegmentSelections();
    this.protectedHistoryCount = await AppStateService.countProtectedHistory(this.ctx);
    let backgroundResult: CapabilityResult = await LongTaskService.getInstance().checkBackgroundCapability(this.ctx);
    this.backgroundStatus = backgroundResult.message;
    if (!backgroundResult.available) {
      this.backgroundEnabled = false;
    }
    await this.refreshLiveViewStatus();
  }

  private async save(): Promise<void> {
    try {
      let settings: AppSettings = new AppSettings();
      settings.defaultQuality = this.defaultQuality;
      settings.defaultWidth = this.defaultWidth;
      settings.defaultFps = this.defaultFps;
      settings.backgroundEnabled = this.backgroundEnabled;
      settings.liveViewEnabled = this.liveViewEnabled;
      settings.lightSenseEnabled = this.lightSenseEnabled;
      settings.lightSensePreferenceVersion = 3;
      settings.stealthNames = this.stealthNames;
      settings.smartSizeEnabled = this.smartSizeEnabled;
      await AppStateService.saveSettings(this.ctx, settings);
      this.saveStatus = '已保存 · ' + new Date().toLocaleTimeString();
    } catch (error) {
      this.saveStatus = '保存失败，请重试';
      promptAction.showToast({ message: '设置保存失败', duration: 1800 });
    }
  }

  private async refreshLiveViewStatus(): Promise<void> {
    if (this.checkingLiveView) {
      return;
    }
    this.checkingLiveView = true;
    try {
      let result: CapabilityResult = await LongTaskService.getInstance().checkLiveViewCapability();
      this.systemLiveViewEnabled = result.available;
      this.liveViewStatus = result.message;
    } catch (e) {
      this.systemLiveViewEnabled = false;
      this.liveViewStatus = '实况窗状态检查失败';
    }
    this.checkingLiveView = false;
  }

  private chooseQuality(value: number): void {
    let preset: OutputPreset = OutputPresetService.resolve(value);
    this.defaultQuality = preset.quality;
    this.defaultWidth = preset.width;
    this.defaultFps = preset.fps;
    this.syncSegmentSelections();
    this.save();
  }

  private async chooseWidth(value: number): Promise<void> {
    this.defaultWidth = value;
    this.widthIndexes = [value === 240 ? 0 : value === 360 ? 1 : value === 720 ? 3 : 2];
    await this.save();
  }

  private async chooseFps(value: number): Promise<void> {
    this.defaultFps = value;
    this.fpsIndexes = [value === 6 ? 0 : value === 10 ? 1 : value === 20 ? 3 : 2];
    await this.save();
  }

  private syncSegmentSelections(): void {
    this.qualityIndexes = [this.defaultQuality === AppConstants.QUALITY_ECONOMY ? 0 :
      this.defaultQuality === AppConstants.QUALITY_WECHAT ? 1 :
        this.defaultQuality === AppConstants.QUALITY_ULTRA ? 3 : 2];
    this.widthIndexes = [this.defaultWidth === 240 ? 0 : this.defaultWidth === 360 ? 1 :
      this.defaultWidth === 720 ? 3 : 2];
    this.fpsIndexes = [this.defaultFps === 6 ? 0 : this.defaultFps === 10 ? 1 :
      this.defaultFps === 20 ? 3 : 2];
  }

  private async changeSmartSize(checked: boolean): Promise<void> {
    this.smartSizeEnabled = checked;
    await this.save();
    promptAction.showToast({ message: checked ? '已开启横竖屏智能尺寸' : '已改为固定输出宽度', duration: 1500 });
  }

  private async changeBackground(checked: boolean): Promise<void> {
    if (!checked) {
      this.backgroundEnabled = false;
      await this.save();
      this.saveStatus = '已关闭后台长任务';
      return;
    }
    if (this.requestingBackground) {
      return;
    }
    this.requestingBackground = true;
    let result: CapabilityResult = await LongTaskService.getInstance().requestBackgroundAuthorization(this.ctx);
    this.backgroundStatus = result.message;
    this.backgroundEnabled = result.available;
    this.requestingBackground = false;
    await this.save();
    promptAction.showToast({ message: result.message, duration: 2200 });
  }

  private async changeLiveView(checked: boolean): Promise<void> {
    this.liveViewEnabled = checked;
    await this.save();
    if (checked) {
      await this.refreshLiveViewStatus();
    }
    promptAction.showToast({
      message: checked ? '已设为转换时尝试创建实况窗' : '已关闭转换实况窗',
      duration: 1600
    });
  }

  private async changeLightSense(checked: boolean): Promise<void> {
    this.lightSenseEnabled = checked;
    await this.save();
    promptAction.showToast({
      message: checked ? '沉浸光感已开启' : '沉浸光感已关闭',
      duration: 1500
    });
  }

  private async testLiveView(): Promise<void> {
    if (this.testingLiveView) {
      return;
    }
    this.testingLiveView = true;
    let result: CapabilityResult = await LongTaskService.getInstance().testLiveView(this.ctx);
    this.liveViewStatus = result.message;
    this.systemLiveViewEnabled = result.available;
    this.testingLiveView = false;
    promptAction.showToast({ message: result.message, duration: 2600 });
  }

  private async changeStealthNames(checked: boolean): Promise<void> {
    this.stealthNames = checked;
    let changed: number = 0;
    if (checked) {
      changed = await AppStateService.anonymizeHistory(this.ctx);
      this.protectedHistoryCount = await AppStateService.countProtectedHistory(this.ctx);
    }
    await this.save();
    let message: string = checked ? '社死保护已开启，已隐藏 ' + changed.toString() + ' 条历史名称' :
      '社死保护已关闭，已隐藏的旧名称不会自动恢复';
    promptAction.showToast({ message: message, duration: 2400 });
  }

  @Builder
  private sectionTitle(title: string) {
    Text(title)
      .width('100%')
      .fontSize(13)
      .fontWeight(700)
      .fontColor(Theme.textSecondary(this.colorMode === 0))
      .margin({ top: 24, bottom: 10 })
  }

  @Builder
  private switchRow(title: string, subtitle: string, value: boolean, onChange: (checked: boolean) => void) {
    ComposeListItem({
      contentItem: {
        primaryText: title,
        secondaryText: subtitle
      },
      operateItem: {
        switch: {
          isCheck: value,
          onChange: (checked: boolean) => { onChange(checked); }
        }
      }
    })
    .width('100%')
    .border({ width: { bottom: 1 }, color: Theme.border(this.colorMode === 0) })
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Theme.pageBg(this.colorMode === 0))

      Column() {
        Row() {
          if (!this.embedded) {
            Button() {
              SymbolBySymbolName({
                name: 'chevron.left',
                fontSize: 25,
                fontColor: Theme.textPrimary(this.colorMode === 0)
              })
            }
            .width(44)
            .height(44)
            .borderRadius(22)
            .backgroundColor(Theme.panelBg(this.colorMode === 0))
            .onClick(() => { router.back(); })
          }

          Text('设置')
            .fontSize(26)
            .fontWeight(850)
            .fontColor(Theme.textPrimary(this.colorMode === 0))
            .margin({ left: this.embedded ? 0 : 14 })
          Blank()
          Text('API ' + this.sdkApiVersion.toString())
            .fontSize(12)
            .fontWeight(650)
            .fontColor(Theme.textSecondary(this.colorMode === 0))
        }
        .width('100%')
        .height(72)
        .padding({ left: 20, right: 20, top: 12 })

        Scroll() {
          Column() {
            ComposeListItem({
              contentItem: {
                primaryText: '水管 GIF',
                secondaryText: '转换偏好与系统能力'
              },
              operateItem: {
                text: 'API ' + this.sdkApiVersion.toString()
              }
            })
            .width('100%')
            .border({ width: { bottom: 1 }, color: Theme.border(this.colorMode === 0) })

            Row() {
              SymbolBySymbolName({ name: 'checkmark.circle.fill', fontSize: 16, fontColor: Theme.success() })
              Text(this.saveStatus)
                .fontSize(12)
                .fontColor(Theme.textSecondary(this.colorMode === 0))
                .margin({ left: 8 })
            }
            .width('100%')
            .height(36)

            this.sectionTitle('默认质量')
            SegmentButton({
              options: this.qualityOptions,
              selectedIndexes: $qualityIndexes,
              enableStateAnimation: true,
              onItemClicked: (index: number) => {
                this.chooseQuality(index === 0 ? AppConstants.QUALITY_ECONOMY :
                  index === 1 ? AppConstants.QUALITY_WECHAT :
                    index === 3 ? AppConstants.QUALITY_ULTRA : AppConstants.QUALITY_MEDIUM);
              }
            })
            .width('100%')
            .height(48)

            this.sectionTitle('默认宽度')
            SegmentButton({
              options: this.widthOptions,
              selectedIndexes: $widthIndexes,
              enableStateAnimation: true,
              onItemClicked: (index: number) => { this.chooseWidth([240, 360, 480, 720][index]); }
            })
            .width('100%')
            .height(48)

            this.switchRow('智能尺寸', '识别横竖屏，选定数值作为画面最长边', this.smartSizeEnabled,
              (checked: boolean) => { this.changeSmartSize(checked); })

            this.sectionTitle('默认帧率')
            SegmentButton({
              options: this.fpsOptions,
              selectedIndexes: $fpsIndexes,
              enableStateAnimation: true,
              onItemClicked: (index: number) => { this.chooseFps([6, 10, 12, 20][index]); }
            })
            .width('100%')
            .height(48)

            this.sectionTitle('后台与通知')
            this.switchRow(this.requestingBackground ? '正在请求授权' : '后台媒体处理', this.backgroundStatus,
              this.backgroundEnabled, (checked: boolean) => { this.changeBackground(checked); })
            this.switchRow('转换时尝试实况窗', this.liveViewStatus,
              this.liveViewEnabled, (checked: boolean) => { this.changeLiveView(checked); })

            ComposeListItem({
              contentItem: {
                primaryText: '实况窗连接测试',
                secondaryText: '发送一次短时测试状态，确认系统入口可用'
              },
              operateItem: {
                button: {
                  text: this.checkingLiveView || this.testingLiveView ? '测试中' : '测试'
                }
              }
            })
            .width('100%')
            .border({ width: { bottom: 1 }, color: Theme.border(this.colorMode === 0) })
            .enabled(!this.checkingLiveView && !this.testingLiveView)
            .onClick(() => { this.testLiveView(); })

            this.sectionTitle('界面材质')
            this.switchRow('沉浸光感', this.materialCapability.message, this.lightSenseEnabled,
              (checked: boolean) => { this.changeLightSense(checked); })

            Text('由 HarmonyOS 官方沉浸材质、双边缘流光场景与温控降级共同驱动；设备不支持沉浸材质时会自动使用系统自适应材质。')
              .width('100%')
              .fontSize(12)
              .lineHeight(18)
              .fontColor(Theme.textSecondary(this.colorMode === 0))
              .margin({ top: 12, bottom: 12 })

            this.sectionTitle('工具与隐私')
            this.switchRow('社死保护', '已保护 ' + this.protectedHistoryCount.toString() + ' 条历史，新记录也会自动隐藏名称',
              this.stealthNames, (checked: boolean) => { this.changeStealthNames(checked); })

            ComposeListItem({
              contentItem: {
                primaryText: 'GIF 工具箱',
                secondaryText: '素材体检、体积预算、空间清理和灵感工具'
              },
              operateItem: {
                button: {
                  text: '打开'
                }
              }
            })
            .width('100%')
            .margin({ bottom: 40 })
            .border({ width: { bottom: 1 }, color: Theme.border(this.colorMode === 0) })
            .onClick(() => { this.openToolbox(); })
          }
          .width('100%')
          .padding({ left: 20, right: 20, bottom: this.embedded ? 116 : 32 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}
