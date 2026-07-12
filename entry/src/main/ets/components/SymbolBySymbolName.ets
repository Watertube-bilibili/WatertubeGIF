@Component
export struct SymbolBySymbolName {
  @Prop name: string = '';
  @Prop fontSize: number | string = 24;
  @Prop fontColor: ResourceColor = Color.Black;
  @Prop fontWeight: number | FontWeight | string = FontWeight.Normal;
  @Prop renderingStrategy: SymbolRenderingStrategy = SymbolRenderingStrategy.SINGLE;
  @Prop effectStrategy: SymbolEffectStrategy = SymbolEffectStrategy.NONE;

  private glyph(): string {
    const map: Record<string, string> = {
      'plus': '+',
      'video.fill.badge.plus': '+',
      'photo.on.rectangle.angled': '□',
      'heart.fill': '♥',
      'checkmark.circle.fill': '✓',
      'xmark.circle.fill': '×',
      'chevron.left': '‹',
      'chevron.right': '›',
      'gearshape.fill': '⚙',
      'flask.fill': '⚗',
      'die.face.5.fill': '⚄',
      'shuffle': '⇄',
      'trash.fill': '×',
      'arrow.clockwise': '↻',
      'play.fill': '▶',
      'pause.fill': 'Ⅱ',
      'stop.fill': '■',
      'square.and.arrow.down.fill': '↓',
      'house.fill': '⌂'
    };
    return map[this.name] ?? '•';
  }

  build() {
    Text(this.glyph())
      .fontSize(this.fontSize)
      .fontColor(this.fontColor)
      .fontWeight(this.fontWeight)
  }
}
