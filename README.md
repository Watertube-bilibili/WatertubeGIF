# WatertubeGIF

WatertubeGIF 是一个基于 HarmonyOS ArkTS 的视频转 GIF 工具，面向手机和平板设备。项目当前包含首页、转换参数页、转换进度页、结果预览页、历史记录、相册保存、后台任务/实况窗进度尝试等功能。

> 当前项目仍在快速迭代中，下面的“未修复问题”不是装饰项，而是基于现有代码状态整理出来的真实风险清单。

## 主要功能

- 从系统相册选择单个视频。
- 在转换前调整 GIF 参数：输出宽度、帧率、截取时长、循环播放、倒放。
- 自动按源视频比例计算输出高度，避免固定比例导致画面被压扁或只显示一条。
- 生成 GIF 后进入预览页，可保存到系统相册。
- 首页显示最近转换历史，并支持清空历史记录。
- 支持“七天内不再提醒”的发电支持弹窗。
- 尝试通过后台任务与 LiveViewKit 更新转换进度，方便长任务场景下继续展示状态。
- 构建产物包含 `.hap` 和 `.app`，Release 中 `.app` 以 zip 形式上传。

## 项目优点

### 1. 转换流程清晰

应用不是一选视频就立刻转换，而是先进入参数页。用户可以确认输出宽度、帧率、截取时长、循环和倒放后再开始转换，降低误操作成本。

相关代码：

- `entry/src/main/ets/pages/Index.ets`
- `entry/src/main/ets/pages/ConvertPage.ets`

### 2. 输出画面按比例缩放

`GifEncoder.fitWidth()` 根据源视频宽高比计算输出尺寸，并把宽高限制在合理范围内：

- 宽度范围：160 到 960
- 高度范围：120 到 960
- 宽高会修正为偶数

这比固定裁剪更稳定，能减少画面变形、黑边异常和“只剩一条”的问题。

### 3. 支持长视频输入

常量里保留了最长 2 小时的时长上限：

```ts
static readonly MAX_DURATION_SECONDS: number = 2 * 60 * 60;
```

实际转换时会根据源视频时长、用户设置、内存预算和最大帧数综合计算抽帧数量，避免长视频直接把内存打爆。

相关代码：

- `entry/src/main/ets/common/Constants.ets`
- `entry/src/main/ets/services/GifEncoder.ets`

### 4. 内存有保护

转换器不会无限制保存所有帧。当前通过两个限制控制内存：

- `MAX_FRAMES = 360`
- `MAX_PIXELS_IN_MEMORY = 120 MB`

这对移动设备比较重要，能降低大视频转换时崩溃的概率。

### 5. GIF 编码器是项目内自实现

项目内置 `GifBinaryEncoder`，会完成：

- 全局调色板构建
- RGB 颜色映射
- GIF 头、逻辑屏幕、循环扩展块、图像块写入
- LZW 数据块输出

这让项目不依赖外部 GIF 编码库，移植和排查问题更直接。

相关代码：

- `entry/src/main/ets/services/GifBinaryEncoder.ets`

### 6. 对 PixelMap 颜色格式做了兼容处理

读取帧数据时会优先转换到 `RGBA_8888`，并对 `BGRA_8888` 做红蓝通道兜底交换，减少 GIF 输出偏色问题。

相关代码：

- `readPixelMapRgba()`

### 7. UI 已从单页工具升级为完整流程

当前 UI 包含：

- 首页
- 最近记录
- 清空历史
- 转换参数页
- 转换进度页
- 预览页
- 保存到相册
- 支持弹窗

整体已经不是简单 demo，而是一个可继续上架打磨的应用骨架。

### 8. AppGallery 目录隔离

开发目录和应用市场签名目录分开：

- 开发与 Git 推送：`D:\watertubeGIF2`
- AppGallery 签名准备：`D:\watertubegif-AppGallery`

这样可以避免把签名版目录、构建缓存或本地配置误推到 GitHub。

## 未修复问题和已知风险

### 1. 部分中文文案仍存在编码污染风险

历史改动中有文件出现过乱码文案。当前代码里仍能看到部分中文字符串显示为异常编码，例如转换状态、默认标题、部分提示文本。

影响：

- 用户界面可能出现乱码。
- README 和 Release 文案之外，应用内实际显示仍需要逐页清理。

建议：

- 统一检查所有 `.ets` 和资源文件的 UTF-8 编码。
- 把 UI 文案集中到资源文件，减少散落在代码里的中文字符串。

### 2. “2 小时视频可生成”不等于 2 小时全帧率 GIF

代码允许最长 2 小时输入，但 `MAX_FRAMES` 当前是 360。也就是说，长视频会被稀疏抽帧，而不是完整按 12fps 或 30fps 生成所有帧。

影响：

- 2 小时视频可以尝试生成，但动画会明显跳帧。
- 用户设置高帧率时，实际输出帧数仍会被最大帧数和内存预算限制。

这是为了避免手机内存和 GIF 文件体积失控。

### 3. GIF 色彩质量仍有限

GIF 本身只有 256 色。当前编码器使用全局调色板和简单颜色映射，没有实现高质量抖动算法。

影响：

- 渐变、暗部、肤色、游戏画面可能出现色带或色差。
- 不同场景混在一个全局调色板中时，局部颜色可能损失明显。

建议后续加入：

- Floyd-Steinberg dithering
- 更好的调色板量化算法
- 可选局部调色板

### 4. 编码体积和速度还有优化空间

当前 LZW 写法偏保守，主要追求结构简单和可靠，并没有做完整字典压缩优化。

影响：

- GIF 文件可能比成熟编码器生成的更大。
- 长视频或高分辨率转换耗时仍会偏高。

### 5. 后台任务和实况窗能力存在设备兼容风险

项目已接入 `BackgroundTasksKit` 和 `LiveViewKit`，但构建日志提示后台任务能力并非所有设备都支持。

影响：

- 某些设备或系统版本上，后台进度/实况窗可能无法启动。
- 当前代码捕获失败后会继续转换，但用户可能看不到预期的后台进度。

相关代码：

- `entry/src/main/ets/services/LongTaskService.ets`

### 6. 取消转换不是完整强制中断

当前取消逻辑主要在抽帧循环中检查 `cancelled`。如果已经进入 taskpool 编码阶段，取消不一定能立即终止编码任务。

影响：

- 点击取消后可能需要等待当前阶段结束。
- 大文件编码时用户会感觉取消不够及时。

### 7. 历史记录只保存本地路径

历史记录保存的是应用沙箱内 GIF 文件路径。如果文件被系统清理、应用数据被清理，历史项可能还在，但预览文件已经不存在。

影响：

- 历史列表可能出现无法预览的旧记录。

建议：

- 打开历史项前检查文件是否存在。
- 对失效记录提供自动清理。

### 8. 保存到相册仍依赖系统权限和媒体库行为

保存 GIF 需要 `ohos.permission.WRITE_IMAGEVIDEO`，并通过 `PhotoAccessHelper.createAsset()` 创建图片资产。

影响：

- 用户拒绝权限会保存失败。
- 不同系统版本对 GIF 媒体资产的处理可能不同。

### 9. 图标组件目前是兼容版

`SymbolBySymbolName` 为了适配当前 SDK，部分系统 Symbol 被降级为文本符号显示。

影响：

- 图标视觉效果不如原生 Symbol 完整。
- 后续可以按目标 SDK 支持情况重新接回系统 Symbol 资源。

### 10. 构建包仍是未签名产物

当前自动构建产物为 unsigned：

- `WaterTubeGIF2-default-unsigned.app`
- `entry-default-unsigned.hap`

上架 AppGallery 前仍需要在签名目录中配置正式签名、包名、证书和上架资料。

## 构建方式

在 DevEco Studio 环境可用时，可以通过 hvigor 构建：

```powershell
$env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'
$env:JAVA_HOME='C:\Program Files\Huawei\DevEco Studio\jbr'
$env:Path='C:\Program Files\Huawei\DevEco Studio\jbr\bin;' + $env:Path
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' assembleApp --analyze=false --parallel --incremental
```

常见产物路径：

- `.app`：`build/outputs/default/WaterTubeGIF2-default-unsigned.app`
- `.hap`：`entry/build/default/outputs/default/entry-default-unsigned.hap`

## 当前开发流程约定

- 代码修改、构建、提交、推送都在 `D:\watertubeGIF2` 完成。
- `D:\watertubegif-AppGallery` 只作为应用市场签名准备目录。
- AppGallery 目录不作为 Git 仓库推送。
- 每次代码改版后，应同步一份源码到 AppGallery 目录。
