import { HistoryItem } from './HistoryCodec';

export class StorageSummary {
  count: number = 0;
  totalBytes: number = 0;
}

export class ToolboxService {
  static summarize(history: HistoryItem[]): StorageSummary {
    let summary: StorageSummary = new StorageSummary();
    history.forEach((item: HistoryItem) => {
      summary.count++;
      if (Number.isFinite(item.size) && item.size > 0) {
        summary.totalBytes += item.size;
      }
    });
    return summary;
  }

  static isOwnedOutput(path: string, filesDir: string): boolean {
    if (path.length === 0 || filesDir.length === 0 || path.indexOf('..') >= 0) {
      return false;
    }
    let root: string = filesDir.endsWith('/') ? filesDir : filesDir + '/';
    let prefix: string = root + 'watertube_';
    if (!path.startsWith(prefix) || !path.endsWith('.gif')) {
      return false;
    }
    return path.substring(prefix.length).indexOf('/') < 0;
  }
}
