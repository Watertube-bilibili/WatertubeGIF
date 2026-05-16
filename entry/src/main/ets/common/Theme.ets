export class Theme {
  static pageBg(dark: boolean): string {
    return dark ? '#05070D' : '#F7FAFF';
  }

  static panelBg(dark: boolean): string {
    return dark ? 'rgba(18,25,42,0.68)' : 'rgba(255,255,255,0.65)';
  }

  static panelStrong(dark: boolean): string {
    return dark ? 'rgba(24,34,56,0.85)' : 'rgba(255,255,255,0.88)';
  }

  static textPrimary(dark: boolean): string {
    return dark ? '#F7FAFF' : '#111827';
  }

  static textSecondary(dark: boolean): string {
    return dark ? 'rgba(235,242,255,0.68)' : '#5B6475';
  }

  static border(dark: boolean): string {
    return dark ? 'rgba(255,255,255,0.12)' : 'rgba(18,36,69,0.08)';
  }

  static accent(): string {
    return '#2F7DFF';
  }

  static cyan(): string {
    return '#21C7D9';
  }

  static rose(): string {
    return '#F06A8A';
  }

  static success(): string {
    return '#18A058';
  }

  static warning(): string {
    return '#D97706';
  }

  static blurStyle(dark: boolean): BlurStyle {
    return dark ? BlurStyle.COMPONENT_THICK : BlurStyle.COMPONENT_ULTRA_THIN;
  }
}
