@Component
export struct SymbolBySymbolName {
  @Prop name: string = '';
  @Prop fontSize: number | string = 24;
  @Prop fontColor: ResourceColor = Color.Black;
  @Prop fontWeight: number | FontWeight | string = FontWeight.Normal;
  @Prop renderingStrategy: SymbolRenderingStrategy = SymbolRenderingStrategy.SINGLE;
  @Prop effectStrategy: SymbolEffectStrategy = SymbolEffectStrategy.NONE;

  private glyph(): Resource {
    if (this.name === 'plus') {
      return $r('sys.symbol.plus');
    }
    if (this.name === 'video.fill.badge.plus') {
      return $r('sys.symbol.video_fill');
    }
    if (this.name === 'photo.on.rectangle.angled') {
      return $r('sys.symbol.picture_on_square');
    }
    if (this.name === 'heart.fill') {
      return $r('sys.symbol.heart_fill');
    }
    if (this.name === 'checkmark.circle.fill') {
      return $r('sys.symbol.checkmark_circle_fill');
    }
    if (this.name === 'xmark.circle.fill') {
      return $r('sys.symbol.xmark_circle_fill');
    }
    if (this.name === 'chevron.left') {
      return $r('sys.symbol.chevron_left');
    }
    if (this.name === 'chevron.right') {
      return $r('sys.symbol.chevron_right');
    }
    if (this.name === 'gearshape.fill') {
      return $r('sys.symbol.gearshape_fill');
    }
    if (this.name === 'wrench.fill') {
      return $r('sys.symbol.wrench_and_screwdriver');
    }
    if (this.name === 'flask.fill' || this.name === 'sparkles') {
      return $r('sys.symbol.wand_and_stars_fill');
    }
    if (this.name === 'die.face.5.fill') {
      return $r('sys.symbol.circle_grid_2x2');
    }
    if (this.name === 'shuffle') {
      return $r('sys.symbol.shuffle');
    }
    if (this.name === 'trash.fill') {
      return $r('sys.symbol.trash_fill');
    }
    if (this.name === 'arrow.clockwise') {
      return $r('sys.symbol.arrow_clockwise');
    }
    if (this.name === 'play.fill') {
      return $r('sys.symbol.play_fill');
    }
    if (this.name === 'pause.fill') {
      return $r('sys.symbol.pause_fill');
    }
    if (this.name === 'stop.fill') {
      return $r('sys.symbol.stop_circle_fill');
    }
    if (this.name === 'square.and.arrow.down.fill') {
      return $r('sys.symbol.square_and_arrow_down');
    }
    if (this.name === 'house.fill') {
      return $r('sys.symbol.house_fill');
    }
    return $r('sys.symbol.circle');
  }

  build() {
    SymbolGlyph(this.glyph())
      .fontSize(this.fontSize)
      .fontColor([this.fontColor])
      .fontWeight(this.fontWeight)
      .renderingStrategy(this.renderingStrategy)
      .effectStrategy(this.effectStrategy)
  }
}
