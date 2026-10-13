// 媒体能力端口：以纯接口提供本机图像解码、对象模型像素提交/回读、文件导出、
// 文档导入与屏幕录制等语义，使媒体服务/控制器无需 import fileIo / image / picker /
// media / photoAccessHelper 等设备能力模块。
// 按消费者实测调用拆分为 ImagePort / ObjectModelMediaPort / FileExportPort /
// DocumentImportPort / ScreenCapturePort 五个最小子接口，MediaPort 组合全部；
// 宿主在 aboutToAppear 注入单一实现 HostMediaPort（MainWindowNativeNode.ets）。
import { image } from '@kit.ImageKit'
import { ImageDecodeSize } from '../pages/MainWindowModels'

// 「另存为」结果：Saved = 用户已落盘；Cancelled = 用户取消选择；Failed = 写文件/弹选择器失败。
export enum MediaSaveResult {
  Saved = 0,
  Cancelled = 1,
  Failed = 2,
}

// 「导入文件」结果：cancelled = 用户取消选择；path = 已复制到应用目录的落盘路径（未取消时非空）。
export interface MediaImportResult {
  cancelled: boolean
  path: string
}

// 系统录屏状态（适配器把 media.AVScreenCaptureStateCode 映射到本枚举）。
export enum ScreenCaptureState {
  Started = 0,
  Canceled = 1,
  StoppedByUser = 2,
  Interrupted = 3,
}

// 本机图片解码 + 文件存在性检查（common/media/ImageDecoder 与详情/星空文化美术缩略图路径依赖）。
export interface ImagePort {
  // 文件是否存在（对应 fileIo.accessSync）。
  fileExists(path: string): boolean
  // 以只读方式打开文件并返回文件描述符 fd（对应 fileIo.openSync(path, READ_ONLY).fd）。
  openReadOnlyFile(path: string, label: string): number
  // 关闭文件描述符（对应 fileIo.closeSync(fd)，内部吞异常并记日志）。
  closeFile(fd: number, label: string): void
  // 由 fd 创建 image source（对应 image.createImageSource(fd)，内部记日志）。
  createImageSource(fd: number, label: string): image.ImageSource
  // 由 source 创建像素图（对应 source.createPixelMap()/createPixelMapUsingAllocator()）：
  // label === 'model' 时用 SHARE_MEMORY 分配器 + RGBA_8888/SDR。
  createPixelMap(source: image.ImageSource, label: string, desiredSize?: ImageDecodeSize): Promise<image.PixelMap>
  // 释放 image source（对应 source.release()，内部吞异常并记日志）。
  releaseImageSource(source: image.ImageSource, label: string): void
  // 释放像素图（对应 pixelMap.release()，内部吞异常并记日志；undefined 时静默返回）。
  releasePixelMap(pixelMap: image.PixelMap | undefined, label: string): void
}

// 对象模型渲染管线：光栅化结果提交 / 像素回读 / RGBA 侧车读取。
// **extends ImagePort 的理由**：模型纹理路径必然以「本机图像解码」开场（ObjectModelRenderer 经
// common/media/ImageDecoder 的 decodeLocalImage/releaseDecodedImage 消费端口），故本接口是其超集，
// 让 ObjectModelRenderer 只需持有一个字段类型。
export interface ObjectModelMediaPort extends ImagePort {
  // ── 对象模型渲染 ──
  // 由原始 RGBA 字节创建像素图（对应 image.createPixelMap(buffer, { size, RGBA_8888, UNPREMUL })）：
  // 三维模型 worker 光栅化结果的提交。
  createPixelMapFromRgba(pixels: ArrayBuffer, width: number, height: number, label: string): Promise<image.PixelMap>
  // 把像素图读回 RGBA 字节缓冲（对应 pixelMap.readPixelsToBufferSync(buffer)，失败抛 Error）：
  // PNG 回退路径（侧车缺失时）。
  readPixelMapPixels(pixelMap: image.PixelMap, buffer: ArrayBuffer, label: string): void
  // 读原始 RGBA 侧车（对应 fileIo.openSync/readSync/closeSync；尺寸不符或 IO 失败抛 Error）：
  // 供 state/ObjectMediaStore 的原始模型纹理加载器经端口回注（store/控制器不 import fileIo）。
  readRawSidecar(path: string, expectedBytes: number, label: string): ArrayBuffer
}

// 文件导出（「另存为」+ 临时文件清理）：AstroCalcController 的 CSV 另存与 common/platform/Screenshot 复用。
export interface FileExportPort {
  // 另存为：弹出 DocumentViewPicker.save 并把 sourcePath 拷到用户选择的位置（DocumentViewPicker.save +
  // fileIo.copy）。onDone(result) 区分落盘/取消/失败；由调用方决定提示与收尾。
  saveFileAs(sourcePath: string, fileName: string, suffixLabel: string, onDone: (result: MediaSaveResult) => void): void
  // 把文本写入缓存临时文件后弹「另存为」并把临时文件拷到用户选择的位置（fileIo.writeSync +
  // DocumentViewPicker.save + fileIo.copy + unlink）；onDone 区分落盘/取消/失败。
  saveTextFileAs(text: string, fileName: string, suffixLabel: string, onDone: (result: MediaSaveResult) => void): void
  // 删除文件（对应 fileIo.unlinkSync，用于截图导出后的临时文件清理）。
  deleteFile(path: string): void
}

// 文档导入（picker + fileIo）：星云纹理 / 脚本 / 地景 / 星文化制作器配图各自的导入段。
export interface DocumentImportPort {
  // 选择单个文档并复制到 <filesDir>/<dirName>，返回落盘路径；用户取消时 cancelled=true。
  // 后缀过滤 / 单文件 / 文件名清洗（picker + fileIo）。
  pickDocumentToDir(dirName: string, fileSuffixFilters: string[], fallbackFileName: string): Promise<MediaImportResult>
  // 选择单个文档并复制到 <filesDir>/<dirName>，文件名由 buildFileName 基于清洗后的源文件名生成
  //（源名清洗 `[^A-Za-z0-9._-]` → `_`，空白回退由 buildFileName 自行处理）；用户取消时 cancelled=true。
  // picker + fileIo.mkdirSync/copy。
  pickDocumentToDirNamed(dirName: string, fileSuffixFilters: string[], buildFileName: (sourceName: string) => string): Promise<MediaImportResult>
  // 选择单个 .ssc 脚本并复制到 <filesDir>/stellarium_userdir/scripts，返回落盘路径；用户取消时 cancelled=true。
  // 后缀过滤（'Stellarium 脚本|.ssc'）/ 单文件 / 名称清洗（scriptImportFileName 语义）/ 同名碰撞改名（picker + fileIo）。
  importScriptDocument(): Promise<MediaImportResult>
  // 选择单个 Stellarium 地景 ZIP 并复制到 <filesDir>/stellarium_userdir/landscape-imports，返回落盘路径；
  // 用户取消时 cancelled=true。后缀过滤（'Stellarium 地景 ZIP|.zip'）/ 单文件 / 名称清洗
  //（landscapeImportFileName 语义）/ 同名碰撞改名（picker + fileIo）。
  importLandscapeDocument(): Promise<MediaImportResult>
}

// 屏幕录制：录屏工作目录与文件、录屏对象生命周期、相册保存。
export interface ScreenCapturePort {
  // ── 屏幕录制 ──
  // 录屏工作目录（filesDir + '/recordings/videos'）。
  screenVideoDir(): string
  // 递归建目录（对应 fileIo.mkdirSync(path, true)）。
  makeDir(path: string): void
  // 文件字节数（对应 fileIo.statSync(path).size；异常返回 0）。
  fileSize(path: string): number
  // 当前是否持有活动的录屏对象。
  hasActiveScreenCapture(): boolean
  // 开始系统录屏：适配器负责 openSync / display / media.createAVScreenCaptureRecorder 与回调注册，
  // 状态变化经 onState 上报、错误经 onError 上报；init/start 失败时 Promise reject。
  beginScreenCapture(filePath: string, onState: (state: ScreenCaptureState) => void, onError: (message: string) => void): Promise<void>
  // 用户主动停止：off 回调 + stopRecording + release + 关文件。
  stopScreenCapture(): Promise<void>
  // 收尾释放（系统已停止/取消）：off 回调 + release + 关文件（不调 stopRecording）。
  releaseScreenCapture(): Promise<void>
  // 保存 MP4 到相册（对应 photoAccessHelper 的 createVideoAssetRequest + applyChanges）；成功返回 true。
  saveVideoToGallery(path: string): Promise<boolean>
}

// 组合端口：宿主适配器 HostMediaPort 单一实现该接口（不拆适配器）。
export interface MediaPort extends ImagePort, ObjectModelMediaPort, FileExportPort, DocumentImportPort, ScreenCapturePort {}
