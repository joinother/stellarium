// 图片解码服务（PLAN §15.3 P4-1 / §15.10 M1-4，本片 M1-A 子组②）。
//
// 原宿主 MainWindowNativeNode 的 decodeLocalImage(70) / releaseDecodedImage(11) 私有方法逐字下沉。
// 本模块**不 import NAPI/UI**（§15.7 规则 1）：文件与图片句柄的开合、像素图创建与释放全部经
// MediaPort（bridge/MediaPort.ets）；本文件只做「打开 → 创建 source → 创建像素图 → 回调 → 收口」
// 的编排，函数体逻辑与宿主逐字一致（仅 this.fileIo/image.* → port.*）。
//
// 保留项：decodeSkyCultureArtThumbnail(33) / decodeSkyCultureArtPreview(27) 未随本片下沉 ——
// 它们与 §15.6 第 3 条永久登记的 loadSkyCultureDetails 同属星空文化美术管线（跨序号
// skyCultureDetailsRequestId / skyCultureArtThumbnailGeneration、渐进写入 §2.7.1 保留的
// skyCultureArtStates/skyCultureArtThumbnailPixelMaps 逐帧字段、并经 setSkyCultureArtStatus 收口），
// 属「美术管线 + 逐帧字段」保留域，故登记保留（见 CHANGELOG / §15.11）。
import { image } from '@kit.ImageKit'
import { ImageDecodeSize } from '../../pages/MainWindowModels'
import { ImagePort } from '../../bridge/MediaPort'

// 从本地图片文件异步解码出像素图（原宿主 decodeLocalImage，逐字搬入）。
// 差异仅：fileIo.openSync/closeSync → port.openReadOnlyFile/closeFile、
// image.createImageSource → port.createImageSource、source.createPixelMap* → port.createPixelMap、
// source.release() → port.releaseImageSource、fileIo.File 句柄变成 port 返回的 fd。
export function decodeLocalImage(
  port: ImagePort,
  filePath: string,
  label: string,
  onSuccess: (pixelMap: image.PixelMap) => void,
  onFailure: (err: Error) => void,
  desiredSize?: ImageDecodeSize,
): void {
  let source: image.ImageSource | undefined = undefined
  let fd: number = -1
  const closeFile = (): void => {
    if (fd < 0) return
    port.closeFile(fd, label)
    fd = -1
  }
  try {
    fd = port.openReadOnlyFile(filePath, label)
    source = port.createImageSource(fd, label)
    port.createPixelMap(source, label, desiredSize).then((pixelMap: image.PixelMap) => {
      onSuccess(pixelMap)
      if (source !== undefined) {
        port.releaseImageSource(source, label)
      }
      closeFile()
    }).catch((err: Error) => {
      if (source !== undefined) {
        port.releaseImageSource(source, label)
      }
      closeFile()
      onFailure(err)
    })
  } catch (err) {
    if (source !== undefined) {
      port.releaseImageSource(source, label)
    }
    closeFile()
    onFailure(err as Error)
  }
}

// 释放已解码的像素图（原宿主 releaseDecodedImage，逐字搬入）。
export function releaseDecodedImage(port: ImagePort, pixelMap: image.PixelMap | undefined, label: string): void {
  port.releasePixelMap(pixelMap, label)
}
