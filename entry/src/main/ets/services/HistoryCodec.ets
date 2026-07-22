export class HistoryItem {
  id: string = '';
  title: string = '';
  path: string = '';
  width: number = 0;
  height: number = 0;
  fps: number = 0;
  frames: number = 0;
  size: number = 0;
  createdAt: number = 0;
  protectedName: boolean = false;
}

export class HistoryCodec {
  static decode(raw: string): HistoryItem[] {
    let history: HistoryItem[] = [];
    let usedIds: Set<string> = new Set<string>();
    try {
      let savedItems: Array<Record<string, Object>> =
        JSON.parse(raw) as Array<Record<string, Object>>;
      savedItems.slice(0, 20).forEach((saved: Record<string, Object>, index: number) => {
        try {
          let path: string = HistoryCodec.text(saved['path']);
          if (path.length === 0) {
            return;
          }

          let item: HistoryItem = new HistoryItem();
          let savedId: string = HistoryCodec.text(saved['id']);
          let baseId: string = savedId.length > 0 ? savedId : path;
          let candidateId: string = baseId;
          let suffix: number = index;
          while (usedIds.has(candidateId)) {
            candidateId = baseId + ':' + suffix.toString();
            suffix++;
          }
          usedIds.add(candidateId);
          item.id = candidateId;
          item.title = HistoryCodec.text(saved['title']);
          if (item.title.length === 0) {
            item.title = '未命名动图';
          }
          item.path = path;
          item.width = HistoryCodec.nonNegativeInteger(saved['width']);
          item.height = HistoryCodec.nonNegativeInteger(saved['height']);
          item.fps = HistoryCodec.nonNegativeInteger(saved['fps']);
          item.frames = HistoryCodec.nonNegativeInteger(saved['frames']);
          item.size = HistoryCodec.nonNegativeInteger(saved['size']);
          item.createdAt = HistoryCodec.nonNegativeInteger(saved['createdAt']);
          item.protectedName = saved['protectedName'] === true;
          history.push(item);
        } catch (e) {
        }
      });
    } catch (e) {
      return [];
    }
    return history;
  }

  private static text(value: Object | undefined): string {
    return typeof value === 'string' ? value : '';
  }

  private static nonNegativeInteger(value: Object | undefined): number {
    let parsed: number = Number(value ?? 0);
    if (!Number.isFinite(parsed)) {
      return 0;
    }
    return Math.max(0, Math.floor(parsed));
  }
}
