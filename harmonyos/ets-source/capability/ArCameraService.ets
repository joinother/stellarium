// AR 实景相机服务（Camera Kit → OH_NativeImage → OpenGL 外部纹理 GPU 单通融合）。
//
// 隐私与权限边界：
// 1. 仅在用户主动点击开启 AR 实景时才申请 ohos.permission.CAMERA（绝不在启动期静默申请）；
// 2. 相机预览帧只留在本地 GPU 纹理做实时合成，不拍照、不录像、不落盘、不上传；
// 3. 退后台、关闭 AR 或页面销毁时立即释放会话与 NativeImage 资源。
import { camera } from '@kit.CameraKit'
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit'
import { display } from '@kit.ArkUI'
import { BusinessError } from '@kit.BasicServicesKit'
import hilog from '@ohos.hilog'
import entry from 'libentry.so'

const LOG_DOMAIN = 0x0000
const LOG_TAG = 'StellariumArkUI'

interface NativeArProbeJson {
  nativeImage?: boolean
  arEngineLib?: boolean
  slam?: boolean
  depth?: boolean
  mesh?: boolean
  semantic?: boolean
}

export interface ArHardwareProbeResult {
  cameraCoreSupported: boolean
  arEngineSysCap: boolean
  nativeImageReady: boolean
  arEngineLibLoaded: boolean
  arEngineSlam: boolean
  arEngineDepth: boolean
  arEngineMesh: boolean
  arEngineSemantic: boolean
  backCameraCount: number
  summaryZh: string
}

export interface ArCameraStartResult {
  ok: boolean
  reason: string
  profileWidth: number
  profileHeight: number
  cameraAspect: number
}

export class ArCameraService {
  private static instance: ArCameraService | null = null

  private cameraManager: camera.CameraManager | undefined = undefined
  private cameraInput: camera.CameraInput | undefined = undefined
  private previewOutput: camera.PreviewOutput | undefined = undefined
  private photoSession: camera.PhotoSession | undefined = undefined
  private previewWidth: number = 1920
  private previewHeight: number = 1080
  private cameraAspect: number = 16 / 9
  private running: boolean = false
  private currentBlend: number = 0.55
  private baseFovDeg: number = 45.0

  static getInstance(): ArCameraService {
    if (ArCameraService.instance === null) {
      ArCameraService.instance = new ArCameraService()
    }
    return ArCameraService.instance
  }

  isRunning(): boolean {
    return this.running
  }

  probeHardware(context?: common.UIAbilityContext): ArHardwareProbeResult {
    let cameraCore = false
    let arEngineSysCap = false
    try {
      cameraCore = canIUse('SystemCapability.Multimedia.Camera.Core')
    } catch (_err) {
      cameraCore = false
    }
    try {
      arEngineSysCap = canIUse('SystemCapability.AREngine.Core')
    } catch (_err) {
      arEngineSysCap = false
    }

    let nativeParsed: NativeArProbeJson = {}
    try {
      const raw = entry.probeArHardware()
      if (typeof raw === 'string' && raw.length > 0) {
        nativeParsed = JSON.parse(raw) as NativeArProbeJson
      }
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[ar-probe] native probe failed: %{public}s', String(err))
    }

    let backCameraCount = 0
    if (cameraCore && context !== undefined) {
      try {
        const mgr = camera.getCameraManager(context)
        const cams = mgr.getSupportedCameras()
        for (const cam of cams) {
          if (cam.cameraPosition === camera.CameraPosition.CAMERA_POSITION_BACK) {
            backCameraCount += 1
          }
        }
      } catch (_err) {
        // Ignore camera query failure before permission/initialization
      }
    }

    const slam = nativeParsed.slam === true
    const depth = nativeParsed.depth === true
    const mesh = nativeParsed.mesh === true
    const semantic = nativeParsed.semantic === true
    const nativeImageReady = nativeParsed.nativeImage === true
    const arEngineLibLoaded = nativeParsed.arEngineLib === true

    const arCaps: string[] = []
    if (slam) arCaps.push('SLAM')
    if (depth) arCaps.push('深度')
    if (mesh) arCaps.push('Mesh')
    if (semantic) arCaps.push('语义')

    const camPart = cameraCore
      ? (backCameraCount > 0 ? `后置相机就绪（${backCameraCount} 颗）` : '相机框架就绪')
      : '设备不支持相机框架'
    const arPart = arCaps.length > 0
      ? `AR Engine：支持 ${arCaps.join(' / ')}`
      : (arEngineSysCap || arEngineLibLoaded ? 'AR Engine：系统存在但本机未开放 SLAM/深度' : 'AR Engine：本机不支持（已启用全机型 Camera+陀螺仪通道）')

    const summaryZh = `${camPart} · ${arPart}`
    hilog.info(LOG_DOMAIN, LOG_TAG, '[ar-probe] %{public}s', summaryZh)

    return {
      cameraCoreSupported: cameraCore,
      arEngineSysCap,
      nativeImageReady,
      arEngineLibLoaded,
      arEngineSlam: slam,
      arEngineDepth: depth,
      arEngineMesh: mesh,
      arEngineSemantic: semantic,
      backCameraCount,
      summaryZh
    }
  }

  private async requestCameraPermission(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const atManager = abilityAccessCtrl.createAtManager()
      const perms: Array<Permissions> = ['ohos.permission.CAMERA']
      const res = await atManager.requestPermissionsFromUser(context, perms)
      if (res.authResults !== undefined && res.authResults.length > 0 && res.authResults[0] === 0) {
        return true
      }
      return false
    } catch (err) {
      const bizErr = err as BusinessError
      hilog.error(LOG_DOMAIN, LOG_TAG, '[ar-camera] permission request error code=%{public}s msg=%{public}s',
        String(bizErr.code), String(bizErr.message))
      return false
    }
  }

  private pickBackCamera(cameras: Array<camera.CameraDevice>): camera.CameraDevice | undefined {
    let fallbackBack: camera.CameraDevice | undefined = undefined
    for (const dev of cameras) {
      if (dev.cameraPosition === camera.CameraPosition.CAMERA_POSITION_BACK) {
        if (dev.cameraType === camera.CameraType.CAMERA_TYPE_WIDE_ANGLE ||
          dev.cameraType === camera.CameraType.CAMERA_TYPE_DEFAULT) {
          return dev
        }
        if (fallbackBack === undefined) {
          fallbackBack = dev
        }
      }
    }
    return fallbackBack ?? (cameras.length > 0 ? cameras[0] : undefined)
  }

  private pickPreviewProfile(capability: camera.CameraOutputCapability): camera.Profile | undefined {
    const profiles = capability.previewProfiles
    if (profiles === undefined || profiles.length === 0) return undefined
    let best: camera.Profile | undefined = undefined
    let bestScore = -1
    for (const p of profiles) {
      if (p.format !== camera.CameraFormat.CAMERA_FORMAT_YUV_420_SP) continue
      const w = p.size.width
      const h = p.size.height
      if (w < 640 || h < 480) continue
      // 优先选择 1280×720（720p）低延迟高流畅度流：相比 1080p 减少 55% GPU 纹理带宽与 ISP 帧延迟
      const pixels = w * h
      const targetPixels = 1280 * 720
      const distancePenalty = Math.abs(pixels - targetPixels) / targetPixels
      const ratioBonus = (Math.abs((w / h) - (16 / 9)) < 0.08 || Math.abs((w / h) - (4 / 3)) < 0.08) ? 0.5 : 0
      const score = 10 - distancePenalty + ratioBonus
      if (score > bestScore) {
        bestScore = score
        best = p
      }
    }
    return best ?? profiles[0]
  }

  private applyPreviewRotation(previewOut: camera.PreviewOutput): void {
    try {
      const displayRot = display.getDefaultDisplaySync().rotation
      const imgRot = displayRot * camera.ImageRotation.ROTATION_90
      const previewRot = previewOut.getPreviewRotation(imgRot)
      previewOut.setPreviewRotation(previewRot, false)
      const swapped = previewRot === camera.ImageRotation.ROTATION_90 ||
        previewRot === camera.ImageRotation.ROTATION_270
      const dispW = swapped ? this.previewHeight : this.previewWidth
      const dispH = swapped ? this.previewWidth : this.previewHeight
      if (dispW > 0 && dispH > 0) {
        this.cameraAspect = dispW / dispH
      }
      hilog.info(LOG_DOMAIN, LOG_TAG, '[ar-camera] rotation displayRot=%{public}d previewRot=%{public}d aspect=%{public}s',
        displayRot, previewRot, this.cameraAspect.toFixed(3))
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[ar-camera] setPreviewRotation skipped: %{public}s', String(err))
      if (this.previewWidth > 0 && this.previewHeight > 0) {
        this.cameraAspect = this.previewWidth / this.previewHeight
      }
    }
  }

  async start(context: common.UIAbilityContext, blend: number, baseFovDeg: number = 45.0): Promise<ArCameraStartResult> {
    this.currentBlend = Math.max(0, Math.min(1, blend))
    if (Number.isFinite(baseFovDeg) && baseFovDeg >= 15 && baseFovDeg <= 100) {
      this.baseFovDeg = baseFovDeg
    }
    if (!canIUse('SystemCapability.Multimedia.Camera.Core')) {
      return { ok: false, reason: '当前设备不支持相机能力', profileWidth: 0, profileHeight: 0, cameraAspect: 1 }
    }

    const granted = await this.requestCameraPermission(context)
    if (!granted) {
      return { ok: false, reason: '未授予相机权限，已保持纯陀螺仪星图模式', profileWidth: 0, profileHeight: 0, cameraAspect: 1 }
    }

    await this.stop()

    try {
      const surfaceId = entry.createArCameraSurface()
      if (typeof surfaceId !== 'string' || surfaceId.length === 0) {
        return { ok: false, reason: '无法创建 GPU 相机纹理通道', profileWidth: 0, profileHeight: 0, cameraAspect: 1 }
      }

      const mgr = camera.getCameraManager(context)
      this.cameraManager = mgr
      const cameras = mgr.getSupportedCameras()
      const backCam = this.pickBackCamera(cameras)
      if (backCam === undefined) {
        await this.stop()
        return { ok: false, reason: '未检测到可用后置摄像头', profileWidth: 0, profileHeight: 0, cameraAspect: 1 }
      }

      const modes = mgr.getSupportedSceneModes(backCam)
      const sceneMode = modes.indexOf(camera.SceneMode.NORMAL_PHOTO) >= 0
        ? camera.SceneMode.NORMAL_PHOTO
        : (modes.length > 0 ? modes[0] : camera.SceneMode.NORMAL_PHOTO)

      const cap = mgr.getSupportedOutputCapability(backCam, sceneMode)
      const profile = this.pickPreviewProfile(cap)
      if (profile === undefined) {
        await this.stop()
        return { ok: false, reason: '未找到可用的相机预览规格', profileWidth: 0, profileHeight: 0, cameraAspect: 1 }
      }

      this.previewWidth = profile.size.width
      this.previewHeight = profile.size.height

      const camInput = mgr.createCameraInput(backCam)
      this.cameraInput = camInput
      await camInput.open()

      const previewOut = mgr.createPreviewOutput(profile, surfaceId)
      this.previewOutput = previewOut

      const session = mgr.createSession(sceneMode) as camera.PhotoSession
      this.photoSession = session

      session.beginConfig()
      session.addInput(camInput)
      session.addOutput(previewOut)
      await session.commitConfig()

      this.applyPreviewRotation(previewOut)

      // 优先锁定更高预览帧率区间，减少实景画面拖影与延迟
      try {
        const ranges = previewOut.getSupportedFrameRates()
        if (ranges !== undefined && ranges.length > 0) {
          let best = ranges[0]
          for (const r of ranges) {
            if (r.max > best.max || (r.max === best.max && r.min > best.min)) {
              best = r
            }
          }
          previewOut.setFrameRate(best.min, best.max)
          hilog.info(LOG_DOMAIN, LOG_TAG, '[ar-camera] frameRate range=%{public}d..%{public}d', best.min, best.max)
        }
      } catch (_fpsErr) {
        // Optional frame rate hint
      }

      try {
        if (session.isFocusModeSupported(camera.FocusMode.FOCUS_MODE_CONTINUOUS_AUTO)) {
          session.setFocusMode(camera.FocusMode.FOCUS_MODE_CONTINUOUS_AUTO)
        }
        const fl = session.getFocalLength()
        if (Number.isFinite(fl) && fl > 0) {
          hilog.info(LOG_DOMAIN, LOG_TAG, '[ar-camera] focalLength=%{public}smm', fl.toFixed(2))
        }
      } catch (_focusErr) {
        // Optional focus mode / focal length probe
      }

      // 锁定主摄 1.0x 固定光学焦段，避免缩放时触发摄像头硬件变焦 ISP 管道延迟（150-300ms）与物理镜头切换卡顿；
      // 变焦同步由 hello.cpp GPU 着色器依据 Stellarium 每帧渲染的实时 FOV（StellariumEntry_setRenderedFov）零延迟精确锁帧完成。
      try {
        const zRange = session.getZoomRatioRange()
        if (zRange !== undefined && zRange.length >= 2 &&
          Number.isFinite(zRange[0]) && Number.isFinite(zRange[1]) &&
          zRange[0] > 0 && zRange[1] >= zRange[0]) {
          const fixedZoom = (1.0 >= zRange[0] && 1.0 <= zRange[1]) ? 1.0 : zRange[0]
          session.setZoomRatio(fixedZoom)
          hilog.info(LOG_DOMAIN, LOG_TAG, '[ar-camera] zoomRange=%{public}s..%{public}s locked=%{public}s',
            zRange[0].toFixed(2), zRange[1].toFixed(2), fixedZoom.toFixed(2))
        }
      } catch (_zoomErr) {
        // Optional hardware zoom query
      }

      await session.start()
      this.running = true
      entry.setArCameraComposite(true, this.currentBlend, this.cameraAspect, this.baseFovDeg)

      hilog.info(LOG_DOMAIN, LOG_TAG, '[ar-camera] started %{public}dx%{public}d aspect=%{public}s blend=%{public}s',
        this.previewWidth, this.previewHeight, this.cameraAspect.toFixed(3), this.currentBlend.toFixed(2))

      return {
        ok: true,
        reason: `实景融合已开启（${this.previewWidth}×${this.previewHeight}）`,
        profileWidth: this.previewWidth,
        profileHeight: this.previewHeight,
        cameraAspect: this.cameraAspect
      }
    } catch (err) {
      const bizErr = err as BusinessError
      hilog.error(LOG_DOMAIN, LOG_TAG, '[ar-camera] start failed code=%{public}s msg=%{public}s',
        String(bizErr.code), String(bizErr.message))
      await this.stop()
      return {
        ok: false,
        reason: `相机启动失败（${String(bizErr.code ?? 'error')}），已安全回退纯星图`,
        profileWidth: 0,
        profileHeight: 0,
        cameraAspect: 1
      }
    }
  }

  updateBlend(blend: number): void {
    this.currentBlend = Math.max(0, Math.min(1, blend))
    if (this.running) {
      entry.setArCameraComposite(true, this.currentBlend, this.cameraAspect, this.baseFovDeg)
    }
  }

  updateBaseFov(baseFovDeg: number): void {
    if (!Number.isFinite(baseFovDeg)) return
    this.baseFovDeg = Math.max(15.0, Math.min(100.0, baseFovDeg))
    if (this.running) {
      entry.setArCameraComposite(true, this.currentBlend, this.cameraAspect, this.baseFovDeg)
    }
  }

  refreshRotation(): void {
    if (!this.running || this.previewOutput === undefined) return
    this.applyPreviewRotation(this.previewOutput)
    entry.setArCameraComposite(true, this.currentBlend, this.cameraAspect, this.baseFovDeg)
  }

  async stop(): Promise<void> {
    this.running = false
    try {
      entry.setArCameraComposite(false, this.currentBlend, this.cameraAspect, this.baseFovDeg)
    } catch (_err) {
    }
    const session = this.photoSession
    this.photoSession = undefined
    if (session !== undefined) {
      try { await session.stop() } catch (_err) {}
      try { await session.release() } catch (_err) {}
    }
    const previewOut = this.previewOutput
    this.previewOutput = undefined
    if (previewOut !== undefined) {
      try { await previewOut.release() } catch (_err) {}
    }
    const camInput = this.cameraInput
    this.cameraInput = undefined
    if (camInput !== undefined) {
      try { await camInput.close() } catch (_err) {}
    }
    this.cameraManager = undefined
    try {
      entry.destroyArCameraSurface()
    } catch (_err) {
    }
  }
}
