import { ObjectDetailStore } from '../../state/ObjectDetailStore'
import { ObjectDetailField } from '../../pages/StellariumTypes'
import { StructuredDetailRow, DetailSectionTitle } from './DetailRows'

// 结构化资料区：按段落分组展示 `ObjectDetailStore.selectedDetailFields`。
//
// 以 `@ObjectLink` 观察 store，`tablet` 由宿主以 `@Prop` 传入；段落与字段的整理逻辑
// 用文件作用域函数实现（ArkTS 规则：辅助逻辑不用嵌套函数）。

function detailSectionIds(): string[] {
  return ['identity', 'observation', 'coordinates', 'physical', 'stellar', 'orbit', 'surface', 'lunar', 'comet', 'satellite', 'plugin']
}

function detailSectionTitle(section: string): string {
  switch (section) {
    case 'identity': return '编号与名称'
    case 'observation': return '观测数据'
    case 'coordinates': return '坐标参考'
    case 'physical': return '物理性质'
    case 'stellar': return '恒星与双星'
    case 'orbit': return '轨道与光照'
    case 'surface': return '行星表面与遮掩'
    case 'lunar': return '月面与月相'
    case 'comet': return '彗发与彗尾'
    case 'satellite': return '人造卫星'
    case 'plugin': return '扩展资料'
    default: return ''
  }
}

function detailFieldLabel(key: string): string {
  switch (key) {
    case 'designations': return '目录编号'
    case 'culturalNames': return '文化名称'
    case 'designation': return '正式编号'
    case 'catalogNumber': return '目录编号'
    case 'internationalDesignator': return '国际标识符'
    case 'hourAngle': return '时角'
    case 'meanSiderealTime': return '平恒星时'
    case 'apparentSiderealTime': return '视恒星时'
    case 'equatorialOfDate': return '当日赤经 / 赤纬'
    case 'apparentAltAz': return '视高度 / 方位'
    case 'equatorialJ2000': return 'J2000 赤经 / 赤纬'
    case 'geometricAltAz': return '几何高度 / 方位'
    case 'eclipticCurrent': return '当日黄经 / 黄纬'
    case 'eclipticJ2000': return 'J2000 黄经 / 黄纬'
    case 'galactic': return '银经 / 银纬'
    case 'supergalactic': return '超银经 / 超银纬'
    case 'parallacticAngle': return '视差角'
    case 'blueMagnitude': return 'B 波段星等'
    case 'surfaceBrightness': return '表面亮度'
    case 'colorIndex': return 'B−V 色指数'
    case 'spectralClass': return '光谱型'
    case 'starType': return '恒星类别'
    case 'morphology': return '形态分类'
    case 'redshift': return '红移'
    case 'angularAxes': return '视长轴 × 短轴'
    case 'positionAngle': return '位置角'
    case 'albedo': return '反照率'
    case 'variabilityType': return '变星类型'
    case 'stellarParallax': return '周年视差'
    case 'stellarAbsoluteMagnitude': return '绝对星等'
    case 'stellarDistance': return '距离'
    case 'variabilityPeriod': return '变光周期'
    case 'doubleStarObservationYear': return '双星测量年份'
    case 'doubleStarPositionAngle': return '伴星位置角'
    case 'doubleStarSeparation': return '双星角距离'
    case 'heliocentricDistance': return '日心距离'
    case 'phaseAngle': return '相位角'
    case 'illuminationTrend': return '亮面趋势'
    case 'orbitalSpeed': return '轨道速度'
    case 'heliocentricSpeed': return '日心速度'
    case 'centralLongitude': return '中央经度'
    case 'centralLatitude': return '中央纬度'
    case 'rotationAxisAngle': return '自转轴位置角'
    case 'subsolarLongitude': return '日下点经度'
    case 'subsolarLatitude': return '日下点纬度'
    case 'eclipseObscuration': return '遮掩面积'
    case 'eclipseMagnitude': return '食分'
    case 'eclipseCrescentAngle': return '日牙角'
    case 'moonPhaseName': return '月相'
    case 'moonAge': return '月龄'
    case 'librationLongitude': return '经度天平动'
    case 'librationLatitude': return '纬度天平动'
    case 'colongitude': return '月面余经'
    case 'penumbralMagnitude': return '半影食分'
    case 'umbralMagnitude': return '本影食分'
    case 'tailLength': return '彗尾长度'
    case 'comaDiameter': return '彗发直径'
    case 'description': return '说明'
    case 'launchDate': return '发射日期 / 年份'
    case 'launchOperator': return '运营方'
    case 'launchVehicle': return '运载火箭'
    case 'mission': return '任务'
    case 'payloadType': return '载荷类型'
    case 'tleEpoch': return '轨道根数历元'
    case 'tleLine1': return 'TLE 第一行'
    case 'tleLine2': return 'TLE 第二行'
    case 'range': return '斜距'
    case 'rangeRate': return '距离变化率'
    case 'height': return '当前高度'
    case 'subpoint': return '星下点纬度 / 经度'
    case 'inclination': return '轨道倾角'
    case 'orbitalPeriod': return '轨道周期'
    case 'perigeeAltitude': return '近地点高度'
    case 'apogeeAltitude': return '远地点高度'
    case 'sunReflectionAngle': return '太阳反射角'
    case 'operationalStatus': return '运行状态'
    case 'visibility': return '可见状态'
    case 'hostStarName': return '主恒星名称'
    case 'hostStarAliases': return '主恒星别名'
    case 'hostSpectralType': return '主恒星光谱型'
    case 'hostDistance': return '主恒星距离'
    case 'hostMass': return '主恒星质量'
    case 'hostMetallicity': return '主恒星金属丰度'
    case 'hostRadius': return '主恒星半径'
    case 'effectiveTemperature': return '有效温度'
    case 'hasHabitablePlanets': return '含宜居候选行星'
    case 'novaType': return '新星类型'
    case 'supernovaType': return '超新星类型'
    case 'maximumMagnitude': return '最亮星等'
    case 'minimumMagnitude': return '最暗星等'
    case 'peakJulianDay': return '峰值儒略日'
    case 'declineTwoMagnitudes': return '衰减 2 星等用时'
    case 'declineThreeMagnitudes': return '衰减 3 星等用时'
    case 'declineSixMagnitudes': return '衰减 6 星等用时'
    case 'declineNineMagnitudes': return '衰减 9 星等用时'
    case 'transientDistance': return '距离'
    case 'notes': return '备注'
    case 'note': return '备注'
    case 'absoluteMagnitude': return '绝对星等'
    case 'radioFlux6cm': return '6 cm 射电流量'
    case 'radioFlux20cm': return '20 cm 射电流量'
    case 'sourceClass': return '源分类'
    case 'annualParallax': return '周年视差'
    case 'binaryPeriod': return '双星轨道周期'
    case 'pulseFrequency': return '脉冲频率'
    case 'frequencyDerivative': return '频率变化率'
    case 'periodDerivative': return '周期变化率'
    case 'pulsePeriod': return '脉冲周期'
    case 'dispersionMeasure': return '色散量'
    case 'eccentricity': return '轨道离心率'
    case 'distanceEstimate': return '估算距离'
    case 'electronDensityDistance': return '电子密度模型距离'
    case 'profileWidth50': return '半峰脉宽'
    case 'glitchCount': return '自转突变记录'
    case 'flux400': return '400 MHz 流量密度'
    case 'flux600': return '600 MHz 流量密度'
    case 'flux1400': return '1400 MHz 流量密度'
    case 'meteorStatus': return '活动状态'
    case 'meteorCode': return '流星雨代码'
    case 'meteorVelocity': return '入射速度'
    case 'populationIndex': return '数量指数'
    case 'parentBody': return '母体'
    case 'maximumZhr': return '峰值天顶每时出现率'
    default: return ''
  }
}

function detailFieldValue(store: ObjectDetailStore, key: string): string {
  const field = store.selectedDetailFields.find((item: ObjectDetailField) => item.key === key)
  if (field === undefined) return '--'
  switch (field.value) {
    case 'waning': return '亮面渐亏'
    case 'waxing': return '亮面渐盈'
    case 'yes': return '是'
    case 'no': return '否'
    case 'double-star': return '双星'
    case 'star': return '恒星'
    case 'generic-data': return '常规活动数据'
    case 'confirmed-data': return '已确认活动'
    case 'inactive': return '当前不活跃'
    case 'variable': return '可变'
    case 'no': return '无已知变光'
    case 'eruptive': return '爆发型变星'
    case 'pulsating': return '脉动变星'
    case 'rotating': return '自转变星'
    case 'cataclysmic': return '激变变星'
    case 'eclipsing-binary': return '食双星'
    default: return field.value
  }
}

function detailFieldsForSection(store: ObjectDetailStore, section: string): Array<ObjectDetailField> {
  if (section === 'coordinates') return []
  const fields: Array<ObjectDetailField> = []
  for (let index = 0; index < store.selectedDetailFields.length; index++) {
    const field = store.selectedDetailFields[index]
    if (field.section === section && field.value.length > 0 && detailFieldLabel(field.key).length > 0) {
      fields.push(field)
    }
  }
  return fields
}

@Component
export struct StructuredDetailRows {
  @ObjectLink store: ObjectDetailStore
  @Prop tablet: boolean

  build() {
    if (!this.store.selectedDetailLoaded) {
      Row({ space: 8 }) {
        LoadingProgress().width(18).height(18).color("#8FD3FF")
        Text("正在整理补充资料").fontSize(11).fontColor("#8FBBD6")
      }
        .width("100%").justifyContent(FlexAlign.Center).padding({ top: 12, bottom: 12 })
    } else if (this.store.selectedDetailFields.length === 0) {
      Text("暂无更多结构化资料").fontSize(11).fontColor("#7FA6BB").width("100%")
        .textAlign(TextAlign.Center).padding({ top: 10, bottom: 10 })
    } else {
      ForEach(detailSectionIds(), (section: string) => {
        if (detailFieldsForSection(this.store, section).length > 0) {
          DetailSectionTitle({ title: detailSectionTitle(section), tablet: this.tablet })
          Column() {
            ForEach(detailFieldsForSection(this.store, section), (field: ObjectDetailField) => {
              StructuredDetailRow({ label: detailFieldLabel(field.key), value: detailFieldValue(this.store, field.key), tablet: this.tablet })
            }, (field: ObjectDetailField) => field.section + ":" + field.key)
          }
            .width("100%")
        }
      }, (section: string) => section)
    }
  }
}
