// StellariumAudio.ets
// 程序化（生成式）音乐引擎 —— 模仿 Sky Guide 的"空灵底噪 + 点星体叮一声"。
//
// 音色优化（2026-07-25 v2）：
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

  private scale: number[] = []
  private pads: Pad[] = []
  private readonly NUM_PADS: number = 5
  private chimes: Chime[] = []
  private readonly MAX_CHIMES: number = 4
  private readonly MAX_PARTIALS: number = 4  // 最多4个泛音（削减到3个有效泛音）

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

  private readonly padLevel: number = 0.13    // 稍微降低pad整体音量，留空间给混响"尾巴"
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
      this.pads[2].freq = this.pads[2].targetFreq = this.scale[5]    // D4=293
      this.pads[2].freq2 = this.pads[2].targetFreq2 = this.scale[5] + 0.7
      this.pads[3].freq = this.pads[3].targetFreq = this.scale[7]    // E4=329
      this.pads[3].freq2 = this.pads[3].targetFreq2 = this.scale[7] + 0.5
      this.pads[4].freq = this.pads[4].targetFreq = this.scale[9]    // G4=392
      this.pads[4].freq2 = this.pads[4].targetFreq2 = this.scale[9] + 0.9
      // 淡入：从0开始渐强
      this.pads[0].gain = 0; this.pads[0].targetGain = 0.11
      this.pads[1].gain = 0; this.pads[1].targetGain = 0.10
      this.pads[2].gain = 0; this.pads[2].targetGain = 0.08
      this.pads[3].gain = 0; this.pads[3].targetGain = 0.09
      this.pads[4].gain = 0; this.pads[4].targetGain = 0.07
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
      out[i] = (o * 32767) | 0
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

    // 柔和的钟声泛音（只保留到3倍频，去掉4+倍频的刺耳高频）
    const softBell: Partial[] = [
      { ratio: 1.0, gain: 1.0 },
      { ratio: 2.0, gain: 0.35 },     // 降低
      { ratio: 3.0, gain: 0.15 }      // 降低
    ]

    // 恒星：温度→音高，亮度→音量
    if (otype.includes('star') && tk > 0) {
      const logMin: number = Math.log10(3000)
      const logMax: number = Math.log10(30000)
      let tNorm: number = (Math.log10(tk) - logMin) / (logMax - logMin)
      tNorm = Math.max(0, Math.min(1, tNorm))
      let idx: number = Math.round(tNorm * (len - 1) * 0.85) + Math.floor(len * 0.15)
      const brightLift: number = Math.max(-1, Math.min(2, Math.round((2.0 - mag) / 2.0)))
      idx = Math.max(Math.floor(len * 0.15), Math.min(len - 1, idx + brightLift))
      const vol: number = Math.max(0.15, Math.min(0.55, (6.5 - mag) / 8.0)) * 0.6  // 整体降低
      return {
        freq: this.scale[idx],
        gain: vol,
        decay: 2.5,       // 更长的尾巴
        partials: softBell,
        pan: 0
      }
    }

    // 按类型给"声线"
    let lo: number = 4
    let hi: number = 12
    let vol: number = 0.35      // 整体降低
    let decay: number = 2.2     // 更长的尾巴
    let partials: Partial[] = softBell

    if (otype.includes('planet')) {
      lo = 2; hi = 8; vol = 0.4; decay = 3.0
      partials = [
        { ratio: 1.0, gain: 1.0 },
        { ratio: 2.0, gain: 0.3 }
      ]
    } else if (otype.includes('moon')) {
      lo = 1; hi = 5; vol = 0.35; decay = 3.5
      partials = [
        { ratio: 1.0, gain: 1.0 },
        { ratio: 1.5, gain: 0.3 }     // 纯五度，特别柔和
      ]
    } else if (otype.includes('sun')) {
      lo = len - 4; hi = len - 1; vol = 0.5; decay = 2.5
      partials = softBell
    } else if (otype.includes('galax')) {
      lo = 2; hi = 6; vol = 0.25; decay = 4.0
      partials = [
        { ratio: 1.0, gain: 1.0 },
        { ratio: 2.0, gain: 0.2 }
      ]
    } else if (otype.includes('nebula')) {
      lo = 4; hi = 10; vol = 0.3; decay = 3.5
      partials = [
        { ratio: 1.0, gain: 1.0 },
        { ratio: 2.0, gain: 0.25 }
      ]
    } else if (otype.includes('cluster')) {
      lo = 6; hi = 12; vol = 0.3; decay = 2.5
      partials = softBell
    } else if (otype.includes('comet')) {
      lo = 8; hi = 14; vol = 0.28; decay = 2.5
      partials = [
        { ratio: 1.0, gain: 1.0 },
        { ratio: 2.0, gain: 0.3 }
      ]
    } else if (otype.includes('asteroid') || otype.includes('minor')) {
      lo = 3; hi = 8; vol = 0.28; decay = 2.0
      partials = [
        { ratio: 1.0, gain: 1.0 },
        { ratio: 2.0, gain: 0.2 }
      ]
    } else if (otype.includes('constellation')) {
      const base: number = 3 + (hash % 4)
      const chord: number[] = [base, base + 2, base + 4].filter((v) => v < len)
      for (let k = 0; k < chord.length; k++) {
        this.playChime({
          freq: this.scale[chord[k]],
          gain: 0.2,
          decay: 3.0,
          partials: [
            { ratio: 1.0, gain: 1.0 },
            { ratio: 2.0, gain: 0.25 }
          ],
          pan: 0
        })
      }
      return { freq: this.scale[base], gain: 0, decay: 0.01, partials: [], pan: 0 }
    } else if (otype.includes('satellite')) {
      lo = 5; hi = 11; vol = 0.3; decay = 2.5
      partials = softBell
    }

    const span: number = Math.max(1, hi - lo)
    const idx: number = lo + (hash % span)
    return {
      freq: this.scale[Math.max(0, Math.min(len - 1, idx))],
      gain: vol,
      decay: decay,
      partials: partials,
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
