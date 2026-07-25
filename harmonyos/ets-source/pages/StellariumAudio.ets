// StellariumAudio.ets
// 程序化（生成式）音乐引擎 —— 模仿 Sky Guide 的"空灵底噪 + 点星体叮一声"。
//
// 设计要点（大白话）：
//   1) 背景是一层"会自己慢慢飘"的氛围音乐：几个持续音（pad）缓慢地换和弦音，
//      每隔几秒还有一个极轻的"远处星星眨眼"声，所以听着空灵但不单调。
//   2) 点选一个新天体就"叮"一声。这声不是随便响的：
//      - 恒星：越热（温度高）音越高，越亮（星等小）音量越大（和 Sky Guide 一致）。
//      - 行星 / 月亮 / 太阳 / 星云 / 星系 / 星团 / 彗星 / 星座：各有自己的"声线"
//        （音区、音色、长短都不同），但都落在同一个五声音阶里，所以永远不刺耳。
//   3) 用 OpenHarmony 的 AudioRenderer 回调模式，实时合成 PCM，不依赖任何音频文件。
//
// 注意：合成在音频回调线程里跑，不要在回调里碰任何 UI。

import { audio } from '@kit.AudioKit'
import hilog from '@ohos.hilog'
import type { StellariumBridgeResponse } from './StellariumTypes'

const TAG: string = 'StellariumAudio'
const DOMAIN: number = 0xD003
const SR: number = 48000                 // 采样率
const TWO_PI_OVER_SR: number = (2.0 * Math.PI) / SR

// 大调五声音阶的半音偏移（听着"东方/空灵"的味道，且任意两个音都不打架）
const PENTA: number[] = [0, 2, 4, 7, 9]

interface Partial {
  ratio: number   // 相对基频的倍数（非整数=钟声般的不和谐泛音，更"叮"）
  gain: number    // 该泛音相对音量
}

interface ChimeSpec {
  freq: number    // 基频 Hz
  gain: number    // 峰值音量 0..1
  decay: number   // 衰减时间（秒）
  partials: Partial[]
  pan: number     // 声像 -1..1（这里单声道，仅留作扩展）
}

class Pad {
  freq: number = 220
  targetFreq: number = 220
  gain: number = 0
  targetGain: number = 0
  phase: number = 0
  phase2: number = 0
  detune: number = 1.005
  lfo: number = 0
  lfoRate: number = 0.05  // Hz，呼吸感
}

class Chime {
  active: boolean = false
  freq: number = 440
  gain: number = 0
  decay: number = 2.0
  attack: number = 0           // 起音样本数
  t: number = 0
  phase: number = 0
  partials: Partial[] = []
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

  // 五声音阶频率表（20 个音，A3=220 起，跨 4 个八度）
  private scale: number[] = []

  // 氛围 pad（缓慢飘动的持续音）
  private pads: Pad[] = [new Pad(), new Pad(), new Pad()]

  // 星体"叮"声（钟状泛音）
  private chimes: Chime[] = []
  private readonly MAX_CHIMES: number = 6

  // 简单混响：两条反馈延迟（combfilter），制造"空灵空间感"
  private revBuf1: Float32Array = new Float32Array(1)
  private revBuf2: Float32Array = new Float32Array(1)
  private revLp1: number = 0
  private revLp2: number = 0
  private revPos: number = 0
  private revLen: number = 1
  private revLen2: number = 1
  private readonly revFeedback: number = 0.36
  private readonly revWet: number = 0.5

  // 调度（样本计数）
  private sincePadRotate: number = 0
  private nextPadRotate: number = SR * 4
  private sinceTwinkle: number = 0
  private nextTwinkle: number = SR * 10

  // 复用的临时缓冲，避免每块分配
  private scratch: Float32Array = new Float32Array(0)

  // 主音量（pad 与 chime 之间的平衡）
  private readonly padLevel: number = 0.16
  private readonly chimeLevel: number = 0.9

  private constructor() {
    this.buildScale()
    for (let i = 0; i < this.MAX_CHIMES; i++) {
      this.chimes.push(new Chime())
    }
    // 混响缓冲：约 0.26s / 0.33s 两条
    this.revLen = Math.floor(0.26 * SR)
    this.revLen2 = Math.floor(0.33 * SR)
    this.revBuf1 = new Float32Array(this.revLen)
    this.revBuf2 = new Float32Array(this.revLen2)
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
      // 起步给一个柔和的和弦，免得一开始太素
      this.pads[0].freq = this.pads[0].targetFreq = this.scale[0]
      this.pads[1].freq = this.pads[1].targetFreq = this.scale[4]
      this.pads[2].freq = this.pads[2].targetFreq = this.scale[8]
      this.pads[0].gain = this.pads[0].targetGain = 0.16
      this.pads[1].gain = this.pads[1].targetGain = 0.14
      this.pads[2].gain = this.pads[2].targetGain = 0.12
      hilog.info(DOMAIN, TAG, 'audio engine started')
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
      // 静音：直接填 0（省 CPU），但保持 running 以便随时恢复
      const z = new Int16Array(buffer)
      z.fill(0)
      return
    }
    if (this.scratch.length < n) {
      this.scratch = new Float32Array(n)
    }
    const out: Int16Array = new Int16Array(buffer)

    // 调度：缓慢换和弦 + 偶尔远处星星眨眼
    this.sincePadRotate += n
    if (this.sincePadRotate >= this.nextPadRotate) {
      this.rotatePad()
      this.nextPadRotate = (3 + Math.random() * 4) * SR
      this.sincePadRotate = 0
    }
    this.sinceTwinkle += n
    if (this.sinceTwinkle >= this.nextTwinkle) {
      this.triggerTwinkle()
      this.nextTwinkle = (7 + Math.random() * 9) * SR
      this.sinceTwinkle = 0
    }

    for (let i = 0; i < n; i++) {
      let mix: number = 0

      // —— 氛围 pad ——
      for (let p = 0; p < this.pads.length; p++) {
        const pad: Pad = this.pads[p]
        pad.freq += (pad.targetFreq - pad.freq) * 0.0006
        pad.gain += (pad.targetGain - pad.gain) * 0.0008
        pad.phase += pad.freq * TWO_PI_OVER_SR
        pad.phase2 += pad.freq * pad.detune * TWO_PI_OVER_SR
        if (pad.phase > 6.283185307) { pad.phase -= 6.283185307 }
        if (pad.phase2 > 6.283185307) { pad.phase2 -= 6.283185307 }
        pad.lfo += this.pads[p].lfoRate * (1.0 / SR) * 6.283185307
        if (pad.lfo > 6.283185307) { pad.lfo -= 6.283185307 }
        const breath: number = 0.5 + 0.5 * Math.sin(pad.lfo)
        const amp: number = pad.gain * (0.45 + 0.55 * breath)
        const s: number = Math.sin(pad.phase) + 0.5 * Math.sin(pad.phase2)
        mix += s * amp * this.padLevel
      }

      // —— 星体"叮" ——
      for (let c = 0; c < this.chimes.length; c++) {
        const ch: Chime = this.chimes[c]
        if (!ch.active) { continue }
        ch.t += 1
        const tsec: number = ch.t / SR
        let env: number
        if (ch.t < ch.attack) {
          env = ch.t / ch.attack
        } else {
          env = Math.exp(-(tsec - ch.attack / SR) / ch.decay)
        }
        if (env < 0.0004) { ch.active = false; continue }
        ch.phase += ch.freq * TWO_PI_OVER_SR
        if (ch.phase > 6.283185307) { ch.phase -= 6.283185307 }
        let s: number = 0
        for (let pp = 0; pp < ch.partials.length; pp++) {
          const par: Partial = ch.partials[pp]
          s += par.gain * Math.sin(ch.phase * par.ratio)
        }
        mix += s * env * ch.gain * this.chimeLevel
      }

      // —— 混响（两条反馈延迟）——
      const d1: number = this.revBuf1[this.revPos]
      const d2: number = this.revBuf2[this.revPos]
      this.revLp1 += (d1 - this.revLp1) * 0.6
      this.revLp2 += (d2 - this.revLp2) * 0.6
      const w1: number = this.revLp1 * this.revFeedback
      const w2: number = this.revLp2 * this.revFeedback
      this.revBuf1[this.revPos] = mix + w1
      this.revBuf2[this.revPos] = mix + w2
      this.revPos++
      if (this.revPos >= this.revLen) { this.revPos = 0 }
      const wet: number = ((w1 + w2) * 0.5) * this.revWet

      let o: number = mix * 0.5 + wet
      if (o > 1.0) { o = 1.0 } else if (o < -1.0) { o = -1.0 }
      out[i] = (o * 32767) | 0
    }
  }

  // 让某一个 pad 缓慢滑向一个新的五声音，制造"和弦在飘"的感觉
  private rotatePad(): void {
    const idx: number = Math.floor(Math.random() * this.pads.length)
    const pad: Pad = this.pads[idx]
    // 只在前 14 个音（中低区）里挑，氛围更稳
    const note: number = this.scale[Math.floor(Math.random() * 14)]
    pad.targetFreq = note
    pad.targetGain = 0.10 + Math.random() * 0.08
  }

  // 远处星星"眨眼"：极轻、偏高、短促的一声，增加层次不单调
  private triggerTwinkle(): void {
    const hi: number = this.scale.length - 4 + Math.floor(Math.random() * 4)
    this.playChime({
      freq: this.scale[Math.max(0, Math.min(this.scale.length - 1, hi))],
      gain: 0.12,
      decay: 1.4,
      partials: [
        { ratio: 1.0, gain: 1.0 },
        { ratio: 2.76, gain: 0.4 },
        { ratio: 5.4, gain: 0.18 }
      ],
      pan: 0
    })
  }

  // ───────────────────────── 对外的"叮"接口 ─────────────────────────

  // 根据选中天体的属性算出"叮"的参数并触发
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

    // 通用钟状泛音（更"叮"）
    const bell: Partial[] = [
      { ratio: 1.0, gain: 1.0 },
      { ratio: 2.0, gain: 0.5 },
      { ratio: 2.76, gain: 0.34 },
      { ratio: 3.0, gain: 0.24 },
      { ratio: 4.07, gain: 0.14 },
      { ratio: 5.4, gain: 0.09 }
    ]

    // —— 恒星：温度→音高，亮度→音量（Sky Guide 同款逻辑）——
    if (otype.includes('star') && tk > 0) {
      const logMin: number = Math.log10(3000)
      const logMax: number = Math.log10(30000)
      let tNorm: number = (Math.log10(tk) - logMin) / (logMax - logMin)
      tNorm = Math.max(0, Math.min(1, tNorm))
      // 越热音越高：映射到音阶中高区
      let idx: number = Math.round(tNorm * (len - 1) * 0.85) + Math.floor(len * 0.15)
      // 越亮（星等越小）略升一点点、也更响
      const brightLift: number = Math.max(-1, Math.min(2, Math.round((2.0 - mag) / 2.0)))
      idx = Math.max(Math.floor(len * 0.15), Math.min(len - 1, idx + brightLift))
      const vol: number = Math.max(0.25, Math.min(1.0, (6.5 - mag) / 8.0)) * 0.95
      return {
        freq: this.scale[idx],
        gain: vol,
        decay: 2.2,
        partials: bell,
        pan: 0
      }
    }

    // —— 按类型给"声线" ——
    // 每个类型给定音区范围（用 hash 在其中取一个确定音，保证同一天体声音一致）
    let lo: number = 4
    let hi: number = 12
    let vol: number = 0.6
    let decay: number = 2.0
    let partials: Partial[] = bell

    if (otype.includes('planet')) {
      lo = 2; hi = 8; vol = 0.7; decay = 2.6
      partials = [
        { ratio: 1.0, gain: 1.0 },
        { ratio: 2.0, gain: 0.42 },
        { ratio: 3.0, gain: 0.25 }
      ]
    } else if (otype.includes('moon')) {
      lo = 1; hi = 5; vol = 0.65; decay = 3.2
      partials = [
        { ratio: 1.0, gain: 1.0 },
        { ratio: 2.0, gain: 0.3 }
      ]
    } else if (otype.includes('sun')) {
      lo = len - 4; hi = len - 1; vol = 0.85; decay = 1.8
    } else if (otype.includes('galax')) {
      lo = 2; hi = 6; vol = 0.45; decay = 3.6
      partials = [
        { ratio: 1.0, gain: 1.0 },
        { ratio: 2.76, gain: 0.4 },
        { ratio: 5.4, gain: 0.2 },
        { ratio: 8.1, gain: 0.12 }
      ]
    } else if (otype.includes('nebula')) {
      lo = 4; hi = 10; vol = 0.5; decay = 3.2
      partials = [
        { ratio: 1.0, gain: 1.0 },
        { ratio: 2.76, gain: 0.5 },
        { ratio: 5.4, gain: 0.22 }
      ]
    } else if (otype.includes('cluster')) {
      lo = 6; hi = 12; vol = 0.55; decay = 1.8
    } else if (otype.includes('comet')) {
      lo = 8; hi = 14; vol = 0.5; decay = 2.0
      partials = [
        { ratio: 1.0, gain: 1.0 },
        { ratio: 2.0, gain: 0.4 },
        { ratio: 3.83, gain: 0.3 },
        { ratio: 5.4, gain: 0.18 }
      ]
    } else if (otype.includes('asteroid') || otype.includes('minor')) {
      lo = 3; hi = 8; vol = 0.5; decay = 1.6
      partials = [
        { ratio: 1.0, gain: 1.0 },
        { ratio: 2.0, gain: 0.3 }
      ]
    } else if (otype.includes('constellation')) {
      // 星座：叠 2~3 个音做成柔和和弦
      const base: number = 3 + (hash % 4)
      const chord: number[] = [base, base + 2, base + 4].filter((v) => v < len)
      for (let k = 0; k < chord.length; k++) {
        this.playChime({
          freq: this.scale[chord[k]],
          gain: 0.42,
          decay: 2.4,
          partials: [
            { ratio: 1.0, gain: 1.0 },
            { ratio: 2.0, gain: 0.35 },
            { ratio: 3.0, gain: 0.2 }
          ],
          pan: 0
        })
      }
      // 返回一个占位（不会再单独 play，避免重复）
      return { freq: this.scale[base], gain: 0, decay: 0.01, partials: [], pan: 0 }
    } else if (otype.includes('satellite')) {
      lo = 5; hi = 11; vol = 0.6; decay = 2.0
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
    // 找空槽；没有就覆盖最"老"的
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
    slot.decay = spec.decay
    slot.attack = Math.floor(0.008 * SR)   // 8ms 起音，钟声要干净
    slot.t = 0
    slot.phase = 0
    slot.partials = spec.partials
  }

  // 名字 → 稳定小整数（让同一个天体的"叮"每次都一样）
  private hashName(s: string): number {
    let h: number = 0
    for (let i = 0; i < s.length; i++) {
      h = (h * 31 + s.charCodeAt(i)) | 0
    }
    return Math.abs(h)
  }
}

// 兼容默认导出（部分 ArkTS 导入习惯）
export default AudioEngine
