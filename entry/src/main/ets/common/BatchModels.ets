import { AppConstants } from './Constants';

export class BatchSource {
  uri: string = '';
  name: string = '';
}

export class BatchSourceCodec {
  static encode(sources: BatchSource[]): string {
    return JSON.stringify(sources.slice(0, AppConstants.MAX_BATCH_ITEMS));
  }

  static decode(raw: string): BatchSource[] {
    let sources: BatchSource[] = [];
    let usedUris: Set<string> = new Set<string>();
    try {
      let savedItems: Array<Record<string, Object>> = JSON.parse(raw) as Array<Record<string, Object>>;
      for (let index: number = 0;
        index < savedItems.length && sources.length < AppConstants.MAX_BATCH_ITEMS; index++) {
        try {
          let saved: Record<string, Object> = savedItems[index];
          let uri: string = BatchSourceCodec.text(saved['uri']);
          if (uri.length === 0 || usedUris.has(uri)) {
            continue;
          }
          let source: BatchSource = new BatchSource();
          source.uri = uri;
          source.name = BatchSourceCodec.text(saved['name']);
          if (source.name.length === 0) {
            source.name = '视频 ' + (sources.length + 1).toString();
          }
          usedUris.add(uri);
          sources.push(source);
        } catch (e) {
        }
      }
    } catch (e) {
      return [];
    }
    return sources;
  }

  private static text(value: Object | undefined): string {
    return typeof value === 'string' ? value : '';
  }
}
