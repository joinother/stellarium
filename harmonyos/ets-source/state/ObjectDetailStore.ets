import { StellariumBridgeResponse, ObjectDetailField, ObjectDetailModel, SatellitePass, SkyCultureDescriptionBlock } from '../pages/StellariumTypes'
import { I18n } from '../pages/I18n'
import { catalogIconForObjectType } from '../common/derive/catalog'
import { modelIdentity, modelMultiply } from '../common/derive/DetailModelGeometry'
import { CommandPort } from '../bridge/CommandPort'

// 宿主注入的卫星过境助手：loadSelectedSatellitePasses 复用宿主 requestSatellitePasses
//（走交互桥）；selectedObjectIsArtificialSatellite 为本 store 方法，不属 hook。
export interface ObjectDetailHostHooks {
  requestSatellitePasses(expectedName: string): void
}

// 选中天体的详情数据（selected*/objectInfo 字段簇）：详情卡片、信息行与平板检查器
// 均读这份数据，故独立成一个 store。
@Observed
export class ObjectDetailStore {
  selectedName: string = ''
  selectedEnglishName: string = ''
  selectedCatalogId: string = ''
  selectedDetailMediaPath: string = ''
  selectedDetailMediaKind: string = ''
  selectedDetailMediaLabel: string = ''
  selectedDetailModel: ObjectDetailModel | undefined = undefined
  selectedConstellationCultureId: string = ''
  selectedConstellationCultureName: string = ''
  selectedConstellationCultureDescription: string = ''
  selectedConstellationCultureDescriptionBlocks: Array<SkyCultureDescriptionBlock> = []
  selectedConstellationCultureDescriptionSource: string = ''
  selectedConstellationCultureDescriptionExpanded: boolean = false
  selectedObjectType: string = ''
  selectedTemperatureK: number = 0
  selectedType: string = ''
  selectedStatus: string = ''
  selectedInfo: string = ''
  selectedMagnitude: string = ''
  selectedApparentMagnitude: string = ''
  selectedAirmass: string = ''
  selectedExtinction: string = ''
  selectedDetailFields: Array<ObjectDetailField> = []
  selectedDetailLoaded: boolean = false
  selectedSatellitePasses: Array<SatellitePass> = []
  selectedSatellitePassesLoaded: boolean = false
  selectedSatellitePassesRequested: boolean = false
  selectedCoordEq: string = ''
  selectedCoordEqJ2000: string = ''
  selectedCoordApparentAltAz: string = ''
  selectedCoordGeometricAltAz: string = ''
  selectedCoordEcliptic: string = ''
  selectedCoordEclipticJ2000: string = ''
  selectedCoordGalactic: string = ''
  selectedCoordSupergalactic: string = ''
  selectedCoordParallactic: string = ''
  selectedCoordAlt: string = ''
  selectedHourAngle: string = ''
  selectedMeanSiderealTime: string = ''
  selectedApparentSiderealTime: string = ''
  selectedConstellation: string = ''
  selectedDistance: string = ''
  selectedDistanceCompact: string = ''
  selectedDistanceStatus: string = ''
  selectedTleOutdated: boolean = false
  selectedSize: string = ''
  selectedRise: string = ''
  selectedSet: string = ''
  selectedTransit: string = ''
  selectedPhase: string = ''
  selectedElongation: string = ''
  objectInfo: Map<string, string> = new Map()
  selectedLandscapeName: string = ''
  selectedDetailTimer: number = 0
  selectedDetailRequestPending: boolean = false
  selectedUiLayoutTimer: number = 0

  // 详情主卡片当前页索引（0/1/2/3；2 = 资料页）。被三个壳层以 @Prop activeIndex 消费
  //（宿主读 store 后下发）。
  bottomCardIndex: number = 0

  // —— 桥注入 ——
  private port: CommandPort | null = null
  // 本加载器不使用请求序号（无并发抑制需求）；保留字段以统一各 store 的加载器约定。
  private seq: number = 0
  private onChanged: (() => void) | null = null
  // 宿主卫星过境助手注入（供 loadSelectedSatellitePasses 使用）。
  private hooks: ObjectDetailHostHooks | null = null

  // 宿主在 aboutToAppear 注入端口与发布回调；重复注入会覆盖旧值（幂等）。
  attachPort(port: CommandPort, onChanged: () => void): void {
    this.port = port
    this.onChanged = onChanged
  }

  attachHooks(hooks: ObjectDetailHostHooks): void {
    this.hooks = hooks
  }

  // 加载器统一守卫：未注入端口时静默跳过（不 crash，也不 import 桥）。
  private ensurePort(): CommandPort | null {
    return this.port
  }

  private notifyChanged(): void {
    if (this.onChanged !== null) {
      this.onChanged()
    }
  }

  // 选中天体资料（getObjectInfo）：桥回包解析为 name/坐标/星等字段映射。
  // 本域无 publish* 发布点，onChanged 为空实现。
  loadObjectInfo(): void {
    const port = this.ensurePort()
    if (port === null) {
      return
    }
    port.requestInteractive('getObjectInfo', '', (r: StellariumBridgeResponse) => {
      if (r.ok === true && r.objectInfoData !== undefined) {
        const obj = r.objectInfoData as Record<string, Object>;
        const m = new Map<string, string>();
        if (obj['name'] !== undefined) m.set('name', obj['name'] as string);
        if (obj['nameI18'] !== undefined) m.set('nameI18', obj['nameI18'] as string);
        if (obj['englishName'] !== undefined) m.set('englishName', obj['englishName'] as string);
        if (obj['type'] !== undefined) m.set('type', obj['type'] as string);
        if (obj['ra'] !== undefined) m.set('ra', (obj['ra'] as number).toFixed(4));
        if (obj['dec'] !== undefined) m.set('dec', (obj['dec'] as number).toFixed(4));
        if (obj['alt'] !== undefined) m.set('alt', (obj['alt'] as number).toFixed(2));
        if (obj['az'] !== undefined) m.set('az', (obj['az'] as number).toFixed(2));
        if (obj['magnitude'] !== undefined) m.set('magnitude', (obj['magnitude'] as number).toFixed(2));
        this.objectInfo = m;
        this.notifyChanged()
      }
    })
  }

  // 选中天体为人工卫星且尚未请求过时触发过境查询；否则跳过。
  loadSelectedSatellitePasses(): void {
    const hooks = this.hooks
    if (hooks === null) {
      return
    }
    if (!this.selectedObjectIsArtificialSatellite() || this.selectedName.length === 0 || this.selectedSatellitePassesRequested) return
    this.selectedSatellitePassesRequested = true
    hooks.requestSatellitePasses(this.selectedName)
  }

  // 自定义信息模式下按位掩码清空明细字段：被清的字段全在本 store；信息模式 / 掩码
  // 判定由调用方以谓词传入，避免 store 相互 import 与新增 hooks。
  applyCustomInformationMask(informationMode: string, informationMaskHas: (key: string) => boolean): void {
    if (informationMode !== 'custom') return
    if (!informationMaskHas('magnitude')) {
      this.selectedMagnitude = ''
      this.selectedApparentMagnitude = ''
      this.selectedAirmass = ''
      this.selectedExtinction = ''
    }
    if (!informationMaskHas('raOfDate')) this.selectedCoordEq = ''
    if (!informationMaskHas('raJ2000')) this.selectedCoordEqJ2000 = ''
    if (!informationMaskHas('altAz')) {
      this.selectedCoordAlt = ''
      this.selectedCoordApparentAltAz = ''
      this.selectedCoordGeometricAltAz = ''
    }
    if (!informationMaskHas('eclipticOfDate')) this.selectedCoordEcliptic = ''
    if (!informationMaskHas('eclipticJ2000')) this.selectedCoordEclipticJ2000 = ''
    if (!informationMaskHas('galactic')) this.selectedCoordGalactic = ''
    if (!informationMaskHas('supergalactic')) this.selectedCoordSupergalactic = ''
    if (!informationMaskHas('otherCoordinates')) this.selectedCoordParallactic = ''
    if (!informationMaskHas('hourAngle')) this.selectedHourAngle = ''
    if (!informationMaskHas('constellation')) this.selectedConstellation = ''
    if (!informationMaskHas('distance')) this.selectedDistance = ''
    if (!informationMaskHas('size')) this.selectedSize = ''
    if (!informationMaskHas('siderealTime')) {
      this.selectedMeanSiderealTime = ''
      this.selectedApparentSiderealTime = ''
    }
    if (!informationMaskHas('riseTransitSet')) {
      this.selectedRise = ''
      this.selectedSet = ''
      this.selectedTransit = ''
    }
    if (!informationMaskHas('elongation')) {
      this.selectedPhase = ''
      this.selectedElongation = ''
    }
    const groups = new Map<string, string>([
      ['designations', 'catalog'], ['designation', 'catalog'], ['catalogNumber', 'catalog'], ['internationalDesignator', 'catalog'], ['culturalNames', 'name'],
      ['hourAngle', 'hourAngle'], ['meanSiderealTime', 'siderealTime'], ['apparentSiderealTime', 'siderealTime'],
      ['equatorialOfDate', 'raOfDate'], ['equatorialJ2000', 'raJ2000'], ['apparentAltAz', 'altAz'], ['geometricAltAz', 'altAz'],
      ['eclipticCurrent', 'eclipticOfDate'], ['eclipticJ2000', 'eclipticJ2000'], ['galactic', 'galactic'], ['supergalactic', 'supergalactic'],
      ['parallacticAngle', 'otherCoordinates'], ['blueMagnitude', 'magnitude'], ['surfaceBrightness', 'magnitude'], ['colorIndex', 'magnitude'],
      ['angularAxes', 'size'], ['positionAngle', 'size']
    ])
    this.selectedDetailFields = this.selectedDetailFields.filter((field: ObjectDetailField) =>
      informationMaskHas(groups.get(field.key) ?? 'extra'))
  }

  // ==== 选中天体的「取值/标签」助手 ====
  //
  // 均读本 store 的 selected* 字段；objectDistanceSummary / objectDistanceNoticeText 另需
  // InfoWindowStore 的距离显示开关，故以显式入参 distanceVisible 传入，避免 store 相互 import。

  // 大气观测摘要。
  expandedAtmosphereSummary(): string {
    const apparent = this.selectedApparentMagnitude.length > 0 ? '大气后 ' + this.selectedApparentMagnitude + ' 等' : ''
    const airmass = this.selectedAirmass.length > 0 ? '气团 ' + this.selectedAirmass : ''
    return (apparent + '  ' + airmass).trim()
  }

  // 距离摘要。
  objectDistanceSummary(distanceVisible: boolean): string {
    if (!distanceVisible) return '--'
    return this.selectedDistance.length > 0 ? (this.selectedDistanceCompact || this.selectedDistance) : I18n.t('distance_missing')
  }

  // 距离提示条文案。
  objectDistanceNoticeText(distanceVisible: boolean): string {
    if (!distanceVisible) return ''
    const status = this.selectedDistanceStatus
    if (status === 'invalid_orbit') return I18n.t('satellite_propagation_invalid')
    if (this.selectedTleOutdated) return I18n.t('satellite_tle_stale')
    if (status === 'catalog' || status === 'computed' || status.length === 0) return ''
    const key = ['low_confidence', 'redshift_only', 'invalid_orbit', 'unsupported_unit', 'estimated'].includes(status)
      ? status : 'unavailable'
    return I18n.t('distance_' + key)
  }

  // 选中天体是否为星座。
  selectedObjectIsConstellation(): boolean {
    const type = (this.selectedType + ' ' + this.selectedObjectType).toLowerCase()
    return type.indexOf('constellation') >= 0 || type.indexOf('星座') >= 0
  }

  // 选中天体是否为人工卫星。
  selectedObjectIsArtificialSatellite(): boolean {
    if (this.selectedSatellitePassesLoaded) return true
    for (let index = 0; index < this.selectedDetailFields.length; index++) {
      if (this.selectedDetailFields[index].key === 'tleEpoch') return true
    }
    const type = (this.selectedType + ' ' + this.selectedObjectType).toLowerCase()
    return type.indexOf('artificial satellite') >= 0 || type.indexOf('人造卫星') >= 0
  }

  // 首个过境数据的 TLE 历元。
  selectedSatelliteTleEpoch(): string {
    if (this.selectedSatellitePasses.length === 0) return ''
    return this.selectedSatellitePasses[0].tleEpoch ?? ''
  }

  // 详情卡图标。
  objectInspectorIcon(): string {
    return catalogIconForObjectType(this.selectedType + ' ' + this.selectedObjectType, 'catalog_star')
  }

  // 详情卡模型检索文本。
  objectInspectorSearchText(): string {
    return (this.selectedCatalogId + ' ' + this.selectedEnglishName + ' ' + this.selectedName).toLowerCase()
  }

  // 是否已选中天体且状态为 Selected。
  hasSelectedObject(): boolean {
    return this.selectedStatus === 'Selected' && this.selectedName.length > 0
  }

  // 详情卡是否已渲染：读本 store 的 selectedName + 信息窗可见性，
  // 后者跨 store 故以显式入参传入。
  isObjectDetailCardRendered(infoWinVisible: boolean): boolean {
    return infoWinVisible && this.selectedName.length > 0
  }

  // 模型视图变换：读本 store 的 selectedDetailModel.lighting.viewToBody 与传入的旋转矩阵，
  // 纯计算（modelMultiply/modelIdentity 来自纯几何模块 DetailModelGeometry，非 NAPI/UI）。
  objectInspectorModelTransform(rotation: number[]): number[] {
    return modelMultiply(this.selectedDetailModel?.lighting?.viewToBody ?? modelIdentity(), rotation)
  }
}
