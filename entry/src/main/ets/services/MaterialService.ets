import { deviceInfo } from '@kit.BasicServicesKit';
import { hdsMaterial, SystemMaterialParams, TitleBarStyleOptions } from '@kit.UIDesignKit';

export class MaterialCapability {
  apiAvailable: boolean = false;
  immersiveSupported: boolean = false;
  message: string = '正在检查系统材质能力';
}

export class MaterialService {
  static checkCapability(): MaterialCapability {
    let result: MaterialCapability = new MaterialCapability();
    if (deviceInfo.sdkApiVersion < 23) {
      result.message = '当前系统版本不支持，需要 API 23 或更高';
      return result;
    }

    result.apiAvailable = true;
    try {
      let types: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes();
      result.immersiveSupported = types.indexOf(hdsMaterial.MaterialType.IMMERSIVE) >= 0;
      result.message = result.immersiveSupported ?
        '系统沉浸材质可用，已由光线与背景内容实时驱动' :
        '设备暂未提供沉浸材质，将使用系统自适应材质';
    } catch (e) {
      result.message = '材质能力读取失败，将使用系统自适应材质';
    }
    return result;
  }

  static titleBarStyle(enabled: boolean, capability: MaterialCapability): TitleBarStyleOptions {
    if (!capability.apiAvailable) {
      return {};
    }
    let material: SystemMaterialParams = {
      materialType: enabled && capability.immersiveSupported ?
        hdsMaterial.MaterialType.IMMERSIVE : hdsMaterial.MaterialType.ADAPTIVE,
      materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
    };
    return {
      systemMaterialEffect: material,
      thermoCtrl: true
    };
  }
}
