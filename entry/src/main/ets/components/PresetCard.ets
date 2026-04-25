import { Theme } from '../common/Theme';

@Component
export struct PresetCard {
  @StorageProp('currentColorMode') colorMode: number = 1;
  @Prop label: string = '';
  @Prop detail: string = '';
  @Prop selected: boolean = false;
  onTap: () => void = () => {};

  build() {
    Row() {
      Column() {
        Text(this.label)
          .fontSize(15)
          .fontWeight(700)
          .fontColor(this.selected ? Color.White : Theme.textPrimary(this.colorMode === 0))
        Text(this.detail)
          .fontSize(11)
          .fontColor(this.selected ? 'rgba(255,255,255,0.74)' : Theme.textSecondary(this.colorMode === 0))
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(70)
    .padding({ left: 14, right: 14 })
    .borderRadius(18)
    .backgroundColor(this.selected ? Theme.accent() : Theme.panelBg(this.colorMode === 0))
    .border({ width: 1, color: this.selected ? Theme.accent() : Theme.border(this.colorMode === 0) })
    .shadow(this.selected ? { radius: 20, color: 'rgba(47,125,255,0.32)', offsetX: 0, offsetY: 10 } : { radius: 10, color: 'rgba(0,0,0,0.06)', offsetX: 0, offsetY: 4 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => { this.onTap(); })
  }
}
