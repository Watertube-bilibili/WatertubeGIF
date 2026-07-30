import { common, scriptManager, wantConstant } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { AppStateService, HistoryItem } from '../../../src/main/ets/services/AppStateService';

export default class RecentGifSkill {
  public async getRecentGif(info: scriptManager.ArkTSScriptInfo, ...argv: string[]): Promise<void> {
    try {
      let context: common.UIAbilityContext = info.context as common.UIAbilityContext;
      let history: HistoryItem[] = await AppStateService.loadHistory(context);
      let latest: HistoryItem | undefined = undefined;
      for (let item of history) {
        if (item.path.length > 0 && fileIo.accessSync(item.path)) {
          latest = item;
          break;
        }
      }
      if (latest === undefined) {
        await this.report(info, this.failure('ERR_NOT_FOUND', '还没有可用的 GIF',
          '请先在水管 GIF 中完成一次转换'));
        return;
      }

      let data: Record<string, Object> = {
        'title': latest.title,
        'width': latest.width,
        'height': latest.height,
        'frames': latest.frames,
        'size': latest.size,
        'createdAt': latest.createdAt
      };
      let payload: Record<string, Object> = {
        'type': 'result',
        'status': 'success',
        'data': data
      };
      let result: scriptManager.ExecuteResult = {
        code: 0,
        result: payload,
        uris: [fileUri.getUriFromPath(latest.path)],
        flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION
      };
      await this.report(info, result);
    } catch (e) {
      let error: BusinessError = e as BusinessError;
      await this.report(info, this.failure('ERR_INTERNAL',
        error.message.length > 0 ? error.message : '读取最近 GIF 失败',
        '请稍后再试'));
    }
  }

  private failure(code: string, message: string, suggestion: string): scriptManager.ExecuteResult {
    let payload: Record<string, Object> = {
      'type': 'result',
      'status': 'failed',
      'errCode': code,
      'errMsg': message,
      'suggestion': suggestion
    };
    return { code: -1, result: payload };
  }

  private async report(info: scriptManager.ArkTSScriptInfo,
    result: scriptManager.ExecuteResult): Promise<void> {
    try {
      await scriptManager.completeArkTSScriptInApp(info.context, info.requestCode, result);
    } catch (e) {
      let error: BusinessError = e as BusinessError;
      console.error('completeArkTSScriptInApp failed, code: ' + error.code.toString());
    }
  }
}
