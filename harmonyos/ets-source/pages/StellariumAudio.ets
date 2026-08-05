// StellariumAudio.ets
// 程序化（生成式）音乐引擎 —— 模仿 Sky Guide 的"空灵底噪 + 点星体叮一声"。
//
// 音色优化（2026-07-26 v3）：
//   性能：Drone数组→独立属性、展开内循环、pad 5→3
//   音色：drone sub-bass + 和弦层提供浑厚持续主音

//   1) 背景Pad：5个pad（比原来3个更丰满），每个用两个低频正弦叠加产生"温暖"
//      的beat频率（2Hz），加上7-12Hz的慢LFO呼吸感，比原来0.05Hz更可感知
//   2) 泛音大幅削减：ratio从{1,2,2.76,3,4.07,5.4}削减到{1,2,3}，去掉>3倍频
//      消除刺耳的金属高频
//   3) 选星"叮"声更柔和：attack从8ms增加到30ms（更圆润），gain整体降低0.6x
//   4) 混响加长加深：revLen 0.26s→0.4s, revLen2 0.33s→0.55s, feedback 0.36→0.45
//      让每个声音有更长的"尾巴"，营造空间感
//   5) Pad交叉淡化：切换和弦时目标gain缓慢过渡而非硬切，消除断裂感
//   6) 低通滤波模拟：pad输出通过简单一阶低通（cutoff ~800Hz），去掉>1kHz的毛刺感
//   7) twinkle（远处星星眨眼）改为更低频更轻柔，不再刺耳
//
// 性能优化（2026-07-25）：
//   正弦查找表 + 预计算衰减率/相位增量 + 缓存局部变量

import { audio } from '@kit.AudioKit'
import hilog from '@ohos.hilog'
import type { StellariumBridgeResponse } from './StellariumTypes'

const TAG: string = 'StellariumAudio'
const DOMAIN: number = 0xD003
const SR: number = 48000
const TWO_PI: number = 6.283185307
const TWO_PI_OVER_SR: number = TWO_PI / SR

// 五声音阶（大调，空灵/东方感，任意组合不刺耳）
const PENTA: number[] = [0, 2, 4, 7, 9]

// ── 正弦查找表 ──
const SINE_SIZE: number = 2048
const SINE_SCALE: number = SINE_SIZE / TWO_PI

interface Partial {
  ratio: number
  gain: number
}

interface ChimeSpec {
  freq: number
  gain: number
  decay: number
  partials: Partial[]
  pan: number
}

// 预计算的活跃泛音（带独立相位累加器，内循环无需乘法）
class ActivePartial {
  gain: number = 0
  phase: number = 0
  phaseInc: number = 0
}

class Pad {
  freq: number = 220
  targetFreq: number = 220
  freq2: number = 220.5        // 第二振荡器（微偏产生beat）
  targetFreq2: number = 220.5
  gain: number = 0
  targetGain: number = 0
  phase: number = 0
  phase2: number = 0           // 第二振荡器相位
  lfo: number = 0
  lfoRate: number = 0.08       // 呼吸感频率（0.08Hz ≈ 12秒一个周期，可感知但不快）
  lfoInc: number = 0
  // 简单一阶低通滤波器状态
  lpState: number = 0
  lpCoeff: number = 0.0002    // cutoff ≈ 800Hz @ 48kHz
}

// 浑厚主音 drone：持续低频 + 慢速和弦变化
// 优化：用独立属性替代数组，消除内循环数组访问
class Drone {
  freq: number = 55           // sub-bass 频率（A1=55Hz）
  targetFreq: number = 55
  phase: number = 0
  phase2: number = 0          // 第二振荡器（五度上方）
  freq2: number = 82.5        // E2=82.5Hz（纯五度）
  targetFreq2: number = 82.5
  gain: number = 0
  targetGain: number = 0.18   // drone 比 pads 更响
  // 和弦层：3个中频泛音（独立属性，避免数组访问开销）
  harmPhase0: number = 0
  harmPhase1: number = 0
  harmPhase2: number = 0
  harmFreq0: number = 220
  harmFreq1: number = 277
  harmFreq2: number = 330
  targetHarmFreq0: number = 220
  targetHarmFreq1: number = 277
  targetHarmFreq2: number = 330
  harmGain0: number = 0.06
  harmGain1: number = 0.05
  harmGain2: number = 0.04
  lpState: number = 0
  lpCoeff: number = 0.0008    // cutoff ~2kHz，保留中频
}

class Chime {
  active: boolean = false
  freq: number = 440
  gain: number = 0
  decayRate: number = 0
  attack: number = 0
  t: number = 0
  env: number = 0
  partials: ActivePartial[] = []
  numPartials: number = 0
}

export class AudioEngine {
  private static inst: AudioEngine | null = null
  static getInstance(): AudioEngine {
    if (!AudioEngine.inst) {
      AudioEngine.inst = new AudioEngine()
    }
    return AudioEngine.inst
  }

  private renderer: audio.AudioRenderer | undefined = undefined
  private running: boolean = false
  private muted: boolean = false
  private volume: number = 1.0

  private scale: number[] = []
  private pads: Pad[] = []
  private readonly NUM_PADS: number = 3
  private chimes: Chime[] = []
  private readonly MAX_CHIMES: number = 4
  private readonly MAX_PARTIALS: number = 4  // 最多4个泛音（削减到3个有效泛音）
  private drone: Drone = new Drone()

  // 和弦进行：5组和弦，每 8-12 秒切换一次
  // 每组 [root, third, fifth] 对应五声音阶中的音
  private readonly chordProgression: number[][] = [
    [0, 4, 7],    // Am: A-C-E
    [2, 5, 9],    // C: C-D-G
    [4, 7, 12],   // Em: E-G-B(高八度)
    [0, 5, 7],    // sus4: A-D-E
    [2, 4, 9],    // Cmaj7: C-E-G
  ]
  private chordIndex: number = 0
  private sinceChordChange: number = 0
  private nextChordChange: number = 0

  // 混响
  private revBuf1: Float32Array = new Float32Array(1)
  private revBuf2: Float32Array = new Float32Array(1)
  private revLp1: number = 0
  private revLp2: number = 0
  private revPos: number = 0
  private revLen: number = 1
  private revLen2: number = 1
  private readonly revFeedback: number = 0.45  // 更深的混响
  private readonly revWet: number = 0.55     // 更湿的混响比例

  // 调度
  private sincePadRotate: number = 0
  private nextPadRotate: number = SR * 6     // 6秒开始第一次切换
  private sinceTwinkle: number = 0
  private nextTwinkle: number = SR * 12      // 12秒一次眨眼

  private readonly padLevel: number = 0.18    // 提升 pad 音量，让背景更丰满
  private readonly chimeLevel: number = 0.55  // 大幅降低叮声音量（0.9→0.55），不刺耳

  // 正弦查找表
  private sineTable: Float32Array = new Float32Array(SINE_SIZE + 1)

  private constructor() {
    this.buildScale()
    this.buildSineTable()
    for (let i = 0; i < this.NUM_PADS; i++) {
      this.pads.push(new Pad())
    }
    for (let i = 0; i < this.MAX_CHIMES; i++) {
      const ch: Chime = new Chime()
      for (let p = 0; p < this.MAX_PARTIALS; p++) {
        ch.partials.push(new ActivePartial())
      }
      this.chimes.push(ch)
    }
    // 更长的混响缓冲
    this.revLen = Math.floor(0.40 * SR)    // 0.4s
    this.revLen2 = Math.floor(0.55 * SR)   // 0.55s
    this.revBuf1 = new Float32Array(this.revLen)
    this.revBuf2 = new Float32Array(this.revLen2)
    for (let i = 0; i < this.NUM_PADS; i++) {
      this.pads[i].lfoInc = this.pads[i].lfoRate * TWO_PI / SR
    }
    // 初始化 drone
    this.drone.lpCoeff = 0.0008
    this.nextChordChange = SR * 10  // 10秒后第一次换和弦
    this.applyChord(0)
  }

  // 应用和弦：更新 drone 的目标和弦频率
  private applyChord(idx: number): void {
    const chord = this.chordProgression[idx % this.chordProgression.length]
    const len = this.scale.length
    // sub-bass: 和弦根音的低两个八度
    this.drone.targetFreq = this.scale[Math.min(chord[0], len - 1)] * 0.25
    this.drone.targetFreq2 = this.scale[Math.min(chord[2], len - 1)] * 0.25
    // 和弦层：3个中频泛音（独立属性赋值）
    this.drone.targetHarmFreq0 = this.scale[Math.min(chord[0], len - 1)]
    this.drone.targetHarmFreq1 = this.scale[Math.min(chord[1], len - 1)]
    this.drone.targetHarmFreq2 = this.scale[Math.min(chord[2], len - 1)]
  }

  private buildSineTable(): void {
    for (let i = 0; i <= SINE_SIZE; i++) {
      this.sineTable[i] = Math.sin(i * TWO_PI / SINE_SIZE)
    }
  }

  private buildScale(): void {
    const root: number = 220.0
    const notes: number[] = []
    for (let oct = 0; oct < 4; oct++) {
      for (let k = 0; k < PENTA.length; k++) {
        notes.push(root * Math.pow(2, (PENTA[k] + oct * 12) / 12.0))
      }
    }
    this.scale = notes
  }

  // ───────────────────────── 生命周期 ─────────────────────────

  async start(): Promise<void> {
    if (this.running) { return }
    try {
      const streamInfo: audio.AudioStreamInfo = {
        samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_48000,
        channels: audio.AudioChannel.CHANNEL_1,
        sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
        encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
      }
      const rendererInfo: audio.AudioRendererInfo = {
        usage: audio.StreamUsage.STREAM_USAGE_MUSIC,
        rendererFlags: 0
      }
      const options: audio.AudioRendererOptions = {
        streamInfo: streamInfo,
        rendererInfo: rendererInfo,
      }
      this.renderer = await audio.createAudioRenderer(options)
      this.renderer.on('writeData', (buffer: ArrayBuffer) => {
        this.render(buffer)
      })
      await this.renderer.start()
      this.running = true
      // 起步和弦：Am9 空灵感（A-C-E-G-B，五声音阶近似）
      // 用前5个音的低八度和中八度
      this.pads[0].freq = this.pads[0].targetFreq = this.scale[0]    // A3=220
      this.pads[0].freq2 = this.pads[0].targetFreq2 = this.scale[0] + 0.8
      this.pads[1].freq = this.pads[1].targetFreq = this.scale[4]    // C4=261
      this.pads[1].freq2 = this.pads[1].targetFreq2 = this.scale[4] + 0.6
      this.pads[2].freq = this.pads[2].targetFreq = this.scale[7]    // E4=329
      this.pads[2].freq2 = this.pads[2].targetFreq2 = this.scale[7] + 0.5
      // 淡入：从0开始渐强（3个pad，音量略提升补偿数量减少）
      this.pads[0].gain = 0; this.pads[0].targetGain = 0.16
      this.pads[1].gain = 0; this.pads[1].targetGain = 0.14
      this.pads[2].gain = 0; this.pads[2].targetGain = 0.12
      // drone 淡入
      this.drone.gain = 0; this.drone.targetGain = 0.20
      hilog.info(DOMAIN, TAG, 'audio engine started (v2 ethereal)')
    } catch (e) {
      this.running = false
      hilog.error(DOMAIN, TAG, 'audio engine start failed: %{public}s', (e as Error).message ?? String(e))
    }
  }

  async stop(): Promise<void> {
    this.running = false
    try {
      if (this.renderer) {
        await this.renderer.stop()
        await this.renderer.release()
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'audio engine stop failed: %{public}s', (e as Error).message ?? String(e))
    }
    this.renderer = undefined
  }

  setMuted(m: boolean): void {
    this.muted = m
    hilog.info(DOMAIN, TAG, 'muted = %{public}s', m ? 'true' : 'false')
  }

  setVolume(v: number): void {
    this.volume = Math.max(0.0, Math.min(1.0, v))
    hilog.info(DOMAIN, TAG, 'volume = %{public}f', this.volume)
  }

  isRunning(): boolean {
    return this.running
  }

  // ───────────────────────── 实时合成 ─────────────────────────

  private render(buffer: ArrayBuffer): void {
    const n: number = (buffer.byteLength / 2) | 0
    if (this.muted || !this.running) {
      const z: Int16Array = new Int16Array(buffer)
      z.fill(0)
      return
    }
    const out: Int16Array = new Int16Array(buffer)

    const tbl: Float32Array = this.sineTable
    const ss: number = SINE_SCALE
    const tp: number = TWO_PI
    const tpos: number = TWO_PI_OVER_SR

    // 调度
    this.sincePadRotate += n
    if (this.sincePadRotate >= this.nextPadRotate) {
      this.rotatePad()
      this.nextPadRotate = (5 + Math.random() * 5) * SR  // 5-10秒随机间隔
      this.sincePadRotate = 0
    }
    this.sinceTwinkle += n
    if (this.sinceTwinkle >= this.nextTwinkle) {
      this.triggerTwinkle()
      this.nextTwinkle = (10 + Math.random() * 10) * SR  // 10-20秒
      this.sinceTwinkle = 0
    }
    // 和弦变化调度（8-12秒切换）
    this.sinceChordChange += n
    if (this.sinceChordChange >= this.nextChordChange) {
      this.chordIndex = (this.chordIndex + 1) % this.chordProgression.length
      this.applyChord(this.chordIndex)
      this.nextChordChange = (8 + Math.random() * 4) * SR  // 8-12秒
      this.sinceChordChange = 0
    }

    const pads: Pad[] = this.pads
    const numPads: number = this.NUM_PADS
    const chimes: Chime[] = this.chimes
    const numChimes: number = chimes.length
    const padLvl: number = this.padLevel
    const chimeLvl: number = this.chimeLevel

    const rb1: Float32Array = this.revBuf1
    const rb2: Float32Array = this.revBuf2
    let rlp1: number = this.revLp1
    let rlp2: number = this.revLp2
    let rpos: number = this.revPos
    const rlen: number = this.revLen
    const rfb: number = this.revFeedback
    const rwet: number = this.revWet

    for (let i = 0; i < n; i++) {
      let mix: number = 0

      // —— 氛围 pad（5个，每两个正弦叠加产生温暖beat）——
      for (let p = 0; p < numPads; p++) {
        const pad: Pad = pads[p]
        // 缓慢滑向目标频率（交叉淡化）
        pad.freq += (pad.targetFreq - pad.freq) * 0.0004     // 更慢的过渡
        pad.freq2 += (pad.targetFreq2 - pad.freq2) * 0.0004
        pad.gain += (pad.targetGain - pad.gain) * 0.0003     // 更慢的淡入淡出

        pad.phase += pad.freq * tpos
        pad.phase2 += pad.freq2 * tpos
        if (pad.phase >= tp) { pad.phase -= tp }
        if (pad.phase2 >= tp) { pad.phase2 -= tp }

        pad.lfo += pad.lfoInc
        if (pad.lfo >= tp) { pad.lfo -= tp }

        // LFO 调制幅度（呼吸感）
        let li: number = pad.lfo * ss
        let li0: number = li | 0
        let lf: number = li - li0
        let breath: number = 0.6 + 0.4 * (tbl[li0] + (tbl[li0 + 1] - tbl[li0]) * lf)

        // 两个正弦叠加 → beat频率 ≈ |freq-freq2| ≈ 0.5-1Hz，产生温暖的"嗡嗡"感
        let pi: number = pad.phase * ss
        let pi0: number = pi | 0
        let pf: number = pi - pi0
        let s: number = tbl[pi0] + (tbl[pi0 + 1] - tbl[pi0]) * pf

        let pi2: number = pad.phase2 * ss
        let pi20: number = pi2 | 0
        let pf2: number = pi2 - pi20
        s = s * 0.6 + (tbl[pi20] + (tbl[pi20 + 1] - tbl[pi20]) * pf2) * 0.4

        // 简单一阶低通滤波（去掉>800Hz的高频毛刺）
        let raw: number = s * pad.gain * breath * padLvl
        pad.lpState += pad.lpCoeff * (raw - pad.lpState)
        mix += pad.lpState
      }

      // —— 浑厚主音 drone（sub-bass + 和弦层，展开循环优化）——
      const dr: Drone = this.drone
      // 缓慢滑向目标和弦（独立属性，无数组访问）
      dr.freq += (dr.targetFreq - dr.freq) * 0.0003
      dr.freq2 += (dr.targetFreq2 - dr.freq2) * 0.0003
      dr.gain += (dr.targetGain - dr.gain) * 0.0002
      dr.harmFreq0 += (dr.targetHarmFreq0 - dr.harmFreq0) * 0.0003
      dr.harmFreq1 += (dr.targetHarmFreq1 - dr.harmFreq1) * 0.0003
      dr.harmFreq2 += (dr.targetHarmFreq2 - dr.harmFreq2) * 0.0003

      // sub-bass: 两个低频正弦叠加（根音 + 五度）
      dr.phase += dr.freq * tpos
      if (dr.phase >= tp) { dr.phase -= tp }
      dr.phase2 += dr.freq2 * tpos
      if (dr.phase2 >= tp) { dr.phase2 -= tp }
      let di: number = dr.phase * ss
      let di0: number = di | 0
      let df: number = di - di0
      let bass: number = tbl[di0] + (tbl[di0 + 1] - tbl[di0]) * df
      let di2: number = dr.phase2 * ss
      let di20: number = di2 | 0
      let df2: number = di2 - di20
      bass = bass * 0.7 + (tbl[di20] + (tbl[di20 + 1] - tbl[di20]) * df2) * 0.3

      // 和弦层：3个中频正弦（展开循环，独立属性）
      dr.harmPhase0 += dr.harmFreq0 * tpos
      if (dr.harmPhase0 >= tp) { dr.harmPhase0 -= tp }
      let ci0n: number = (dr.harmPhase0 * ss) | 0
      let cf0n: number = dr.harmPhase0 * ss - ci0n
      let chord: number = dr.harmGain0 * (tbl[ci0n] + (tbl[ci0n + 1] - tbl[ci0n]) * cf0n)

      dr.harmPhase1 += dr.harmFreq1 * tpos
      if (dr.harmPhase1 >= tp) { dr.harmPhase1 -= tp }
      let ci1n: number = (dr.harmPhase1 * ss) | 0
      let cf1n: number = dr.harmPhase1 * ss - ci1n
      chord += dr.harmGain1 * (tbl[ci1n] + (tbl[ci1n + 1] - tbl[ci1n]) * cf1n)

      dr.harmPhase2 += dr.harmFreq2 * tpos
      if (dr.harmPhase2 >= tp) { dr.harmPhase2 -= tp }
      let ci2n: number = (dr.harmPhase2 * ss) | 0
      let cf2n: number = dr.harmPhase2 * ss - ci2n
      chord += dr.harmGain2 * (tbl[ci2n] + (tbl[ci2n + 1] - tbl[ci2n]) * cf2n)

      // drone 总输出（低通滤波后混合）
      let droneOut: number = (bass * 0.6 + chord * 0.4) * dr.gain
      dr.lpState += dr.lpCoeff * (droneOut - dr.lpState)
      mix += dr.lpState

      // —— 星体"叮"（柔和钟声）——
      for (let c = 0; c < numChimes; c++) {
        const ch: Chime = chimes[c]
        if (!ch.active) { continue }
        ch.t++
        if (ch.t < ch.attack) {
          ch.env = ch.t / ch.attack
        } else {
          ch.env *= ch.decayRate
        }
        if (ch.env < 0.0004) { ch.active = false; continue }

        let s: number = 0
        for (let pp = 0; pp < ch.numPartials; pp++) {
          const par: ActivePartial = ch.partials[pp]
          par.phase += par.phaseInc
          if (par.phase >= tp) { par.phase -= tp }
          let qi: number = par.phase * ss
          let qi0: number = qi | 0
          let qf: number = qi - qi0
          s += par.gain * (tbl[qi0] + (tbl[qi0 + 1] - tbl[qi0]) * qf)
        }
        mix += s * ch.env * ch.gain * chimeLvl
      }

      // —— 混响（两条反馈延迟，更深更长）——
      const d1: number = rb1[rpos]
      const d2: number = rb2[rpos]
      rlp1 += (d1 - rlp1) * 0.5     // 更慢的LP（更暖）
      rlp2 += (d2 - rlp2) * 0.5
      const w1: number = rlp1 * rfb
      const w2: number = rlp2 * rfb
      rb1[rpos] = mix + w1
      rb2[rpos] = mix + w2
      rpos++
      if (rpos >= rlen) { rpos = 0 }
      const wet: number = ((w1 + w2) * 0.5) * rwet

      let o: number = mix * 0.45 + wet   // 干信号降低，湿信号比例提升
      if (o > 1.0) { o = 1.0 } else if (o < -1.0) { o = -1.0 }
      out[i] = ((o * this.volume) * 32767) | 0
    }

    this.revLp1 = rlp1
    this.revLp2 = rlp2
    this.revPos = rpos
  }

  // 缓慢切换某一个pad到新的五声音阶音（交叉淡化，不断裂）
  private rotatePad(): void {
    const idx: number = Math.floor(Math.random() * this.NUM_PADS)
    const pad: Pad = this.pads[idx]
    // 只在中低区（前14个音）选，保持温暖
    const noteIdx: number = Math.floor(Math.random() * 14)
    const note: number = this.scale[noteIdx]
    pad.targetFreq = note
    pad.targetFreq2 = note + 0.3 + Math.random() * 0.8  // 微偏产生beat
    // 柔和的音量波动
    pad.targetGain = 0.06 + Math.random() * 0.06  // 0.06-0.12（温和）
  }

  // 远处星星"眨眼"：低频、轻柔、短促
  private triggerTwinkle(): void {
    // 从音阶中低区选（不再选最高音，避免尖锐）
    const idx: number = 5 + Math.floor(Math.random() * 10)  // 中低区
    this.playChime({
      freq: this.scale[idx],
      gain: 0.06,       // 极轻（原来0.12）
      decay: 2.0,       // 稍长衰减
      partials: [
        { ratio: 1.0, gain: 1.0 },
        { ratio: 2.0, gain: 0.25 },    // 只保留2倍泛音，去掉高次
      ],
      pan: 0
    })
  }

  // ───────────────────────── 对外的"叮"接口 ─────────────────────────

  chimeForSelection(info: StellariumBridgeResponse): void {
    if (!this.running || this.muted) { return }
    const spec: ChimeSpec = this.specForObject(info)
    this.playChime(spec)
  }

  private specForObject(info: StellariumBridgeResponse): ChimeSpec {
    const len: number = this.scale.length
    const name: string = (info.englishName && info.englishName.length > 0) ? info.englishName
      : (info.name && info.name.length > 0 ? info.name : '')
    const hash: number = this.hashName(name)
    const otype: string = (info.objectType ? info.objectType : (info.type ? info.type : '')).toLowerCase()
    const mag: number = (typeof info.magnitude === 'number') ? info.magnitude as number : 99
    const tk: number = (typeof info.temperatureK === 'number') ? info.temperatureK as number : 0

    // ── 恒星：温度→音高，亮度→音量+衰减 ──
    // 蓝热恒星(>20000K)：高音、明亮、短衰减
    // 红冷恒星(<4000K)：低音、温暖、长衰减
    // 极暗恒星(>6mag)：极轻、极远、超长衰减+重混响
    if (otype.includes('star') && !otype.includes('cluster') && !otype.includes('nebula')) {
      const logMin: number = Math.log10(3000)
      const logMax: number = Math.log10(30000)
      let tNorm: number = (Math.log10(tk) - logMin) / (logMax - logMin)
      tNorm = Math.max(0, Math.min(1, tNorm))
      let idx: number = Math.round(tNorm * (len - 1) * 0.7) + Math.floor(len * 0.2)
      const brightLift: number = Math.max(-1, Math.min(2, Math.round((2.0 - mag) / 2.0)))
      idx = Math.max(Math.floor(len * 0.2), Math.min(len - 1, idx + brightLift))

      // 极暗恒星：更远、更轻、更长尾
      if (mag > 5.0) {
        return {
          freq: this.scale[idx],
          gain: 0.12,
          decay: 5.0,
          partials: [
            { ratio: 1.0, gain: 1.0 },
            { ratio: 2.0, gain: 0.15 }
          ],
          pan: 0
        }
      }
      // 普通恒星
      const vol: number = Math.max(0.15, Math.min(0.5, (6.5 - mag) / 8.0)) * 0.55
      const decay: number = tk > 15000 ? 1.8 : 3.5  // 热星短衰减，冷星长衰减
      return {
        freq: this.scale[idx],
        gain: vol,
        decay: decay,
        partials: [
          { ratio: 1.0, gain: 1.0 },
          { ratio: 2.0, gain: 0.3 },
          { ratio: 3.0, gain: tk > 10000 ? 0.12 : 0.05 }
        ],
        pan: 0
      }
    }

    // ── 行星：深沉、温暖、中长衰减 ──
    if (otype.includes('planet')) {
      return {
        freq: this.scale[2 + (hash % 5)],
        gain: 0.38,
        decay: 3.0,
        partials: [
          { ratio: 1.0, gain: 1.0 },
          { ratio: 2.0, gain: 0.28 },
          { ratio: 1.5, gain: 0.15 }
        ],
        pan: 0
      }
    }

    // ── 月球：最低音、纯音、超长衰减 ──
    if (otype.includes('moon')) {
      return {
        freq: this.scale[0 + (hash % 3)],
        gain: 0.32,
        decay: 4.0,
        partials: [
          { ratio: 1.0, gain: 1.0 },
          { ratio: 1.5, gain: 0.25 }
        ],
        pan: 0
      }
    }

    // ── 太阳：明亮、饱满、全泛音 ──
    if (otype === 'star' && name.toLowerCase().includes('sun')) {
      return {
        freq: this.scale[len - 3],
        gain: 0.48,
        decay: 2.5,
        partials: [
          { ratio: 1.0, gain: 1.0 },
          { ratio: 2.0, gain: 0.35 },
          { ratio: 3.0, gain: 0.18 }
        ],
        pan: 0
      }
    }

    // ── 星系：极深沉、嗡鸣感、超长衰减 ──
    if (otype.includes('galax') || otype.includes('quasar')) {
      const isQuasar: boolean = otype.includes('quasar')
      // 星系播两个音叠加（低音drone + 中音）
      this.playChime({
        freq: this.scale[1 + (hash % 3)],
        gain: 0.18,
        decay: 5.0,
        partials: [
          { ratio: 1.0, gain: 1.0 },
          { ratio: 2.0, gain: 0.12 }
        ],
        pan: 0
      })
      return {
        freq: this.scale[4 + (hash % 4)],
        gain: isQuasar ? 0.28 : 0.22,
        decay: 4.5,
        partials: [
          { ratio: 1.0, gain: 1.0 },
          { ratio: 2.0, gain: 0.15 },
          { ratio: 3.0, gain: isQuasar ? 0.2 : 0.08 }
        ],
        pan: 0
      }
    }

    // ── 发射星云（如玫瑰星云）：温暖流动感 + 高频微闪 ──
    if (otype.includes('emission nebula') || otype.includes('hii')) {
      // 先播一个低中音pad-like
      this.playChime({
        freq: this.scale[5 + (hash % 4)],
        gain: 0.15,
        decay: 4.0,
        partials: [
          { ratio: 1.0, gain: 1.0 },
          { ratio: 2.0, gain: 0.2 }
        ],
        pan: 0
      })
      return {
        freq: this.scale[10 + (hash % 4)],
        gain: 0.26,
        decay: 3.8,
        partials: [
          { ratio: 1.0, gain: 1.0 },
          { ratio: 2.0, gain: 0.3 },
          { ratio: 3.0, gain: 0.12 }
        ],
        pan: 0
      }
    }

    // ── 行星状星云：明亮、环状回响感 ──
    if (otype.includes('planetary nebula')) {
      return {
        freq: this.scale[12 + (hash % 4)],
        gain: 0.3,
        decay: 3.0,
        partials: [
          { ratio: 1.0, gain: 1.0 },
          { ratio: 2.0, gain: 0.35 },
          { ratio: 3.0, gain: 0.15 }
        ],
        pan: 0
      }
    }

    // ── 暗星云：低沉、闷、短衰减 ──
    if (otype.includes('dark nebula')) {
      return {
        freq: this.scale[0 + (hash % 3)],
        gain: 0.22,
        decay: 2.0,
        partials: [
          { ratio: 1.0, gain: 1.0 },
          { ratio: 2.0, gain: 0.08 }
        ],
        pan: 0
      }
    }

    // ── 反射星云：柔和、中高音、轻柔 ──
    if (otype.includes('reflection nebula')) {
      return {
        freq: this.scale[10 + (hash % 5)],
        gain: 0.24,
        decay: 3.5,
        partials: [
          { ratio: 1.0, gain: 1.0 },
          { ratio: 2.0, gain: 0.22 }
        ],
        pan: 0
      }
    }

    // ── 超新星遗迹：尖锐爆发 + 长尾 ──
    if (otype.includes('supernova')) {
      return {
        freq: this.scale[14 + (hash % 3)],
        gain: 0.35,
        decay: 1.5,
        partials: [
          { ratio: 1.0, gain: 1.0 },
          { ratio: 2.0, gain: 0.4 },
          { ratio: 3.0, gain: 0.2 }
        ],
        pan: 0
      }
    }

    // ── 一般星云（其他类型） ──
    if (otype.includes('nebula')) {
      return {
        freq: this.scale[6 + (hash % 6)],
        gain: 0.26,
        decay: 3.5,
        partials: [
          { ratio: 1.0, gain: 1.0 },
          { ratio: 2.0, gain: 0.22 }
        ],
        pan: 0
      }
    }

    // ── 疏散星团：多颗亮星闪烁感 ──
    if (otype.includes('open') || otype.includes('association')) {
      const base: number = 8 + (hash % 4)
      this.playChime({
        freq: this.scale[base + 2],
        gain: 0.15,
        decay: 2.0,
        partials: [{ ratio: 1.0, gain: 1.0 }, { ratio: 2.0, gain: 0.2 }],
        pan: 0
      })
      return {
        freq: this.scale[base],
        gain: 0.28,
        decay: 2.5,
        partials: [
          { ratio: 1.0, gain: 1.0 },
          { ratio: 2.0, gain: 0.25 }
        ],
        pan: 0
      }
    }

    // ── 球状星团：密集和弦 ──
    if (otype.includes('globular')) {
      const base: number = 5 + (hash % 3)
      const chord: number[] = [base, base + 2, base + 4]
      for (let k = 0; k < chord.length; k++) {
        if (chord[k] < len) {
          this.playChime({
            freq: this.scale[chord[k]],
            gain: 0.14,
            decay: 3.0,
            partials: [{ ratio: 1.0, gain: 1.0 }, { ratio: 2.0, gain: 0.15 }],
            pan: 0
          })
        }
      }
      return { freq: this.scale[base], gain: 0, decay: 0.01, partials: [], pan: 0 }
    }

    // ── 一般星团 ──
    if (otype.includes('cluster')) {
      return {
        freq: this.scale[8 + (hash % 5)],
        gain: 0.28,
        decay: 2.5,
        partials: [
          { ratio: 1.0, gain: 1.0 },
          { ratio: 2.0, gain: 0.25 },
          { ratio: 3.0, gain: 0.1 }
        ],
        pan: 0
      }
    }

    // ── 彗星：上升扫频感（高音+快衰减） ──
    if (otype.includes('comet')) {
      return {
        freq: this.scale[12 + (hash % 3)],
        gain: 0.26,
        decay: 2.0,
        partials: [
          { ratio: 1.0, gain: 1.0 },
          { ratio: 2.0, gain: 0.3 },
          { ratio: 3.0, gain: 0.15 }
        ],
        pan: 0
      }
    }

    // ── 小行星：短促、断奏、中低音 ──
    if (otype.includes('asteroid') || otype.includes('minor') || otype.includes('plut')) {
      return {
        freq: this.scale[3 + (hash % 5)],
        gain: 0.26,
        decay: 1.2,
        partials: [
          { ratio: 1.0, gain: 1.0 },
          { ratio: 2.0, gain: 0.18 }
        ],
        pan: 0
      }
    }

    // ── 星座：三音和弦 ──
    if (otype.includes('constellation')) {
      const base: number = 3 + (hash % 4)
      const chord: number[] = [base, base + 2, base + 4].filter((v) => v < len)
      for (let k = 0; k < chord.length; k++) {
        this.playChime({
          freq: this.scale[chord[k]],
          gain: 0.18,
          decay: 3.0,
          partials: [
            { ratio: 1.0, gain: 1.0 },
            { ratio: 2.0, gain: 0.22 }
          ],
          pan: 0
        })
      }
      return { freq: this.scale[base], gain: 0, decay: 0.01, partials: [], pan: 0 }
    }

    // ── 人造卫星（如 ISS）：电子金属ping声、高音、快衰减 ──
    if (otype.includes('artificial') || otype.includes('satellite')) {
      return {
        freq: this.scale[15 + (hash % 3)],
        gain: 0.3,
        decay: 1.0,
        partials: [
          { ratio: 1.0, gain: 1.0 },
          { ratio: 2.0, gain: 0.4 },
          { ratio: 3.0, gain: 0.2 },
          { ratio: 4.0, gain: 0.1 }
        ],
        pan: 0
      }
    }

    // ── 默认：温和中音 ──
    const lo: number = 4
    const hi: number = 12
    const span: number = Math.max(1, hi - lo)
    const idx: number = lo + (hash % span)
    return {
      freq: this.scale[Math.max(0, Math.min(len - 1, idx))],
      gain: 0.3,
      decay: 2.5,
      partials: [
        { ratio: 1.0, gain: 1.0 },
        { ratio: 2.0, gain: 0.25 }
      ],
      pan: 0
    }
  }

  private playChime(spec: ChimeSpec): void {
    if (spec.gain <= 0 || spec.partials.length === 0) { return }
    let slot: Chime | null = null
    for (let i = 0; i < this.chimes.length; i++) {
      if (!this.chimes[i].active) { slot = this.chimes[i]; break }
    }
    if (!slot) {
      slot = this.chimes[0]
      for (let i = 1; i < this.chimes.length; i++) {
        if (this.chimes[i].t > slot.t) { slot = this.chimes[i] }
      }
    }
    slot.active = true
    slot.freq = spec.freq
    slot.gain = spec.gain
    slot.decayRate = Math.exp(-1 / (SR * spec.decay))
    slot.attack = Math.floor(0.030 * SR)   // 30ms起音（原来8ms），更圆润
    slot.t = 0
    slot.env = 0
    slot.numPartials = Math.min(spec.partials.length, this.MAX_PARTIALS)
    for (let i = 0; i < slot.numPartials; i++) {
      const p: ActivePartial = slot.partials[i]
      p.gain = spec.partials[i].gain
      p.phase = 0
      p.phaseInc = spec.freq * spec.partials[i].ratio * TWO_PI_OVER_SR
    }
  }

  private hashName(s: string): number {
    let h: number = 0
    for (let i = 0; i < s.length; i++) {
      h = (h * 31 + s.charCodeAt(i)) | 0
    }
    return Math.abs(h)
  }
}

export default AudioEngine
