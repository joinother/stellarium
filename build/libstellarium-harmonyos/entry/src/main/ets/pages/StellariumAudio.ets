// StellariumAudio.ets
// 交响乐式宇宙背景音引擎 (v4 — Interstellar)
//
// 音色设计理念：Hans Zimmer Interstellar 风格的空灵宇宙配乐
//   - 5层叠加架构：Deep Bass Drone → String Pad → Melody → High Shimmer → Chime
//   - 持续浑厚的低音弦乐底色，3个略微失谐正弦产生温暖chorus
//   - 7组和弦进行（七和弦/挂留和弦），16-20秒缓慢切换
//   - 无beat频率效应，无节拍，纯持续和声
//   - 双延迟线混响营造宏大空间感
//
// 性能约束：
//   采样率 48000Hz, 单声道, S16LE
//   每帧 ~960 samples (20ms), render 必须在 20ms 内完成
//   正弦查找表 (SINE_SIZE=2048), 内循环只做查表+乘法+加法
//   drone 3 voice 展开为独立属性, shimmer 2 voice 展开为独立属性

import { audio } from '@kit.AudioKit'
import hilog from '@ohos.hilog'
import type { StellariumBridgeResponse } from './StellariumTypes'

const TAG: string = 'StellariumAudio'
const DOMAIN: number = 0xD003
const SR: number = 48000
const TWO_PI: number = 6.283185307
const TWO_PI_OVER_SR: number = TWO_PI / SR

// ── 正弦查找表 ──
const SINE_SIZE: number = 2048
const SINE_SCALE: number = SINE_SIZE / TWO_PI

// ── 类型定义 ──

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

// 预计算的活跃泛音（带独立相位累加器）
class ActivePartial {
  gain: number = 0
  phase: number = 0
  phaseInc: number = 0
}

// ── Deep Bass Drone：3个略微失谐正弦，产生温暖弦乐chorus ──

class DroneVoice {
  freq: number = 55
  targetFreq: number = 55
  phase: number = 0
  gain: number = 0
}

class DeepDrone {
  // 3个失谐振荡器（展开为独立属性，避免数组访问）
  v0: DroneVoice = new DroneVoice()   // 基频
  v1: DroneVoice = new DroneVoice()   // +0.25Hz
  v2: DroneVoice = new DroneVoice()   // -0.25Hz
  gain: number = 0
  targetGain: number = 0.25
  // 一阶低通滤波 (cutoff ~100Hz)
  lpState: number = 0
  lpCoeff: number = 0.00008
}

// ── String Pad：单一正弦 + 超慢LFO调制 ──

class Pad {
  freq: number = 220
  targetFreq: number = 220
  gain: number = 0
  targetGain: number = 0
  phase: number = 0
  // 超慢 LFO (0.02-0.04Hz, 30-50秒呼吸周期)
  lfo: number = 0
  lfoRate: number = 0.03
  lfoInc: number = 0
  // 一阶低通滤波 (cutoff ~600Hz)
  lpState: number = 0
  lpCoeff: number = 0.00015
}

// ── High Shimmer：极轻高频，若有若无 ──

class ShimmerVoice {
  freq: number = 880
  targetFreq: number = 880
  phase: number = 0
  gain: number = 0
  targetGain: number = 0.02
  // 慢 LFO (0.01-0.03Hz)
  lfo: number = 0
  lfoRate: number = 0.02
  lfoInc: number = 0
}

// ── Chime（选星叮声，保留原有逻辑）──

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

// ── 五声音阶（用于chime音高映射）──

const PENTA: number[] = [0, 2, 4, 7, 9]

// 预计算的MIDI音符→频率
function midiFreq(note: number): number {
  return 440.0 * Math.pow(2.0, (note - 69) / 12.0)
}

// ── AudioEngine ──

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
  private masterVol: number = 0.7

  // 第1层：Deep Bass Drone
  private drone: DeepDrone = new DeepDrone()

  // 第2层：String Pad（5个pad振荡器）
  private pads: Pad[] = []
  private readonly NUM_PADS: number = 5

  // 第3层：High Shimmer（2个高频振荡器，展开为独立属性）
  private shimmer0: ShimmerVoice = new ShimmerVoice()
  private shimmer1: ShimmerVoice = new ShimmerVoice()

  // 第4层：Chimes
  private chimes: Chime[] = []
  private readonly MAX_CHIMES: number = 6
  private readonly MAX_PARTIALS: number = 4

  // 五声音阶（用于chime选音）
  private scale: number[] = []

  // 和弦进行（每组包含3-4个音符频率，用于pad分配）
  private readonly chords: number[][] = [
    [midiFreq(57), midiFreq(60), midiFreq(64), midiFreq(67)],   // Am7:  A3 C4 E4 G4
    [midiFreq(53), midiFreq(57), midiFreq(60), midiFreq(64)],   // Fmaj7: F3 A3 C4 E4
    [midiFreq(50), midiFreq(53), midiFreq(57), midiFreq(60)],   // Dm7:  D3 F3 A3 C4
    [midiFreq(48), midiFreq(52), midiFreq(55), midiFreq(59)],   // Cmaj7: C3 E3 G3 B3
    [midiFreq(52), midiFreq(55), midiFreq(59), midiFreq(62)],   // Em7:  E3 G3 B3 D4
    [midiFreq(43), midiFreq(48), midiFreq(50)],                  // Gsus4: G2 C3 D3
    [midiFreq(58), midiFreq(62), midiFreq(65), midiFreq(69)],   // Bbmaj7: Bb3 D4 F4 A4
  ]
  private chordIndex: number = 0
  private sinceChordChange: number = 0
  private nextChordChange: number = 0

  // ── 第2.5层：Melody 旋律线 ──
  private melPhase: number = 0
  private melFreq: number = 440
  private melTargetFreq: number = 440
  private melLpState: number = 0
  private readonly melLpCoeff: number = 0.0003   // cutoff ~1200Hz
  private readonly melLevel: number = 0.10
  private melNoteAge: number = 0       // current note age (samples)
  private melNoteDur: number = 0       // current note total duration
  private melActive: boolean = false
  private melNoteIdx: number = 0
  private melSeq: number[][] = []

  // 混响
  private revBuf1: Float32Array = new Float32Array(1)
  private revBuf2: Float32Array = new Float32Array(1)
  private revLp1: number = 0
  private revLp2: number = 0
  private revPos: number = 0
  private revLen: number = 1
  private revLen2: number = 1
  private readonly revFeedback: number = 0.35
  private readonly revWet: number = 0.40

  // 音量级别
  private readonly chimeLevel: number = 0.22  // 选星叮声整体增益（降低刺耳感）

  // 正弦查找表
  private sineTable: Float32Array = new Float32Array(SINE_SIZE + 1)

  private constructor() {
    this.buildScale()
    this.buildSineTable()

    // 初始化 pads
    for (let i = 0; i < this.NUM_PADS; i++) {
      this.pads.push(new Pad())
    }

    // 初始化 chimes
    for (let i = 0; i < this.MAX_CHIMES; i++) {
      const ch: Chime = new Chime()
      for (let p = 0; p < this.MAX_PARTIALS; p++) {
        ch.partials.push(new ActivePartial())
      }
      this.chimes.push(ch)
    }

    // 初始化混响缓冲
    this.revLen = Math.floor(0.6 * SR)     // 0.6s
    this.revLen2 = Math.floor(0.8 * SR)    // 0.8s
    this.revBuf1 = new Float32Array(this.revLen)
    this.revBuf2 = new Float32Array(this.revLen2)

    // 初始化 pad LFO 增量（每个pad略微不同的LFO速率，避免同步）
    this.pads[0].lfoRate = 0.025;  this.pads[0].lfoInc = this.pads[0].lfoRate * TWO_PI / SR
    this.pads[1].lfoRate = 0.032;  this.pads[1].lfoInc = this.pads[1].lfoRate * TWO_PI / SR
    this.pads[2].lfoRate = 0.038;  this.pads[2].lfoInc = this.pads[2].lfoRate * TWO_PI / SR
    this.pads[3].lfoRate = 0.028;  this.pads[3].lfoInc = this.pads[3].lfoRate * TWO_PI / SR
    this.pads[4].lfoRate = 0.035;  this.pads[4].lfoInc = this.pads[4].lfoRate * TWO_PI / SR

    // 初始化 shimmer LFO
    this.shimmer0.lfoRate = 0.015;  this.shimmer0.lfoInc = this.shimmer0.lfoRate * TWO_PI / SR
    this.shimmer1.lfoRate = 0.022;  this.shimmer1.lfoInc = this.shimmer1.lfoRate * TWO_PI / SR

    // 初始化 drone 失谐偏移
    this.drone.v1.freq = this.drone.v1.targetFreq = 55.25   // +0.25Hz
    this.drone.v2.freq = this.drone.v2.targetFreq = 54.75   // -0.25Hz

    // 应用起始和弦
    this.nextChordChange = SR * 16  // 16秒后第一次换和弦
    this.applyChord(0)

    // 初始化旋律序列：为每个和弦计算旋律音候选
    for (const ch of this.chords) {
      const seq: number[] = []
      for (const f of ch) {
        seq.push(f)         // 原始音
        seq.push(f * 2)     // 高八度
      }
      this.melSeq.push(seq)
    }
    this.melNoteDur = SR * 4
  }

  // ── 和弦应用：分配pad频率和drone低音 ──

  private applyChord(idx: number): void {
    const chord = this.chords[idx % this.chords.length]
    const len = chord.length  // 3或4

    // 第1层：Drone低音 = 和弦根音低两个八度 (30-55Hz)
    const rootHz = chord[0] * 0.25
    this.drone.v0.targetFreq = rootHz
    this.drone.v1.targetFreq = rootHz + 0.25   // +0.25Hz失谐
    this.drone.v2.targetFreq = rootHz - 0.25   // -0.25Hz失谐

    // 第2层：5个pad → 取和弦中3-4个音 + 倍频填充
    const padFreqs: number[] = []
    for (let i = 0; i < len; i++) {
      padFreqs.push(chord[i])           // 原始和弦音 (110-440Hz)
    }
    // 用高八度填充到5个pad
    if (padFreqs.length < 5) {
      padFreqs.push(chord[0] * 2)       // 根音高八度
    }
    if (padFreqs.length < 5 && len >= 2) {
      padFreqs.push(chord[1] * 2)       // 三音高八度
    }
    // 确保正好5个
    while (padFreqs.length > 5) {
      padFreqs.pop()
    }
    while (padFreqs.length < 5) {
      padFreqs.push(chord[0] * 2)
    }

    for (let i = 0; i < this.NUM_PADS; i++) {
      this.pads[i].targetFreq = padFreqs[i]
      // pad增益：和弦内音略响，高八度填充稍轻
      if (i < len) {
        this.pads[i].targetGain = 0.10 + (i === 0 ? 0.02 : 0)  // 0.10-0.12
      } else {
        this.pads[i].targetGain = 0.08
      }
    }

    // 第3层：Shimmer = 和弦最高音的高八度 (880-1760Hz)
    const topNote = chord[chord.length - 1]
    this.shimmer0.targetFreq = topNote * 2       // 高八度
    this.shimmer0.targetGain = 0.020
    this.shimmer1.targetFreq = topNote * 2.5     // 再高一点（纯五度上方）
    this.shimmer1.targetGain = 0.015
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

      // 背景音已移除，仅保留选星叮声
      hilog.info(DOMAIN, TAG, 'audio engine started (chime-only mode)')
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

  setVolume(v: number): void {
    this.masterVol = v
    hilog.info(DOMAIN, TAG, 'volume = %{public}f', v)
  }

  setMuted(m: boolean): void {
    this.muted = m
    hilog.info(DOMAIN, TAG, 'muted = %{public}s', m ? 'true' : 'false')
  }

  isRunning(): boolean {
    return this.running
  }

  // ───────────────────────── 实时合成（核心render循环）─────────────────────────

  // 背景音已移除（drone/pad/shimmer/melody 全部禁用），仅保留选星叮声。
  // 这极大降低了 CPU 占用，避免与星图渲染线程争抢资源导致卡顿。
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

    const chimes: Chime[] = this.chimes
    const numChimes: number = chimes.length
    const chimeLvl: number = this.chimeLevel

    // 轻量混响（单延迟线，仅用于 chime 尾音）
    const rb1: Float32Array = this.revBuf1
    let rpos: number = this.revPos
    const rlen: number = this.revLen
    const rfb: number = 0.25

    for (let i = 0; i < n; i++) {
      let mix: number = 0

      // ── 仅处理 Chimes（选星叮声）──
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

      // 轻量混响
      const d1: number = rb1[rpos]
      rb1[rpos] = mix + d1 * rfb
      rpos++
      if (rpos >= rlen) { rpos = 0 }
      const wet: number = d1 * 0.15

      let o: number = (mix * 0.6 + wet) * this.masterVol
      if (o > 1.0) { o = 1.0 } else if (o < -1.0) { o = -1.0 }
      out[i] = (o * 32767) | 0
    }

    this.revPos = rpos
  }

  // ───────────────────────── 对外接口：选星叮声 ─────────────────────────

  chimeForSelection(info: StellariumBridgeResponse): void {
    if (!this.running || this.muted) { return }
    const spec: ChimeSpec = this.specForObject(info)
    this.playChime(spec)
  }

  // ───────────────────────── 选星音效映射（保持原有逻辑）─────────────────────────

  private specForObject(info: StellariumBridgeResponse): ChimeSpec {
    const len: number = this.scale.length
    const name: string = (info.englishName && info.englishName.length > 0) ? info.englishName
      : (info.name && info.name.length > 0 ? info.name : '')
    const hash: number = this.hashName(name)
    const otype: string = (info.objectType ? info.objectType : (info.type ? info.type : '')).toLowerCase()
    const mag: number = (typeof info.magnitude === 'number') ? info.magnitude as number : 99
    const tk: number = (typeof info.temperatureK === 'number') ? info.temperatureK as number : 0
    const distStr: string = (info.distance ? info.distance : '')
    let distLY: number = 0
    if (distStr.length > 0) {
      const dm: RegExpMatchArray | null = distStr.match(/([\d.]+)/)
      if (dm) { distLY = parseFloat(dm[1]) }
    }

    // ── 太阳 ──
    if (otype === 'star' && name.toLowerCase().includes('sun')) {
      return {
        freq: this.scale[3],
        gain: 0.20,
        decay: 4.0,
        partials: [
          { ratio: 1.0, gain: 1.0 },
          { ratio: 2.0, gain: 0.12 },
          { ratio: 3.0, gain: 0.05 }
        ],
        pan: 0
      }
    }

    // ── 恒星 ──
    if (otype.includes('star') && !otype.includes('cluster') && !otype.includes('nebula')) {
      const logMin: number = Math.log10(3000)
      const logMax: number = Math.log10(30000)
      let tNorm: number = (Math.log10(tk) - logMin) / (logMax - logMin)
      tNorm = Math.max(0, Math.min(1, tNorm))
      let idx: number = Math.round(tNorm * (len - 1) * 0.7) + Math.floor(len * 0.2)
      const brightLift: number = Math.max(-1, Math.min(2, Math.round((2.0 - mag) / 2.0)))
      idx = Math.max(Math.floor(len * 0.2), Math.min(len - 1, idx + brightLift))

      // 极远恒星（数百/数千光年）：空灵、超长衰减、泛音极简
      if (distLY > 500) {
        const farGain: number = distLY > 5000 ? 0.06 : 0.08
        const farDecay: number = distLY > 5000 ? 10.0 : 7.0
        return {
          freq: this.scale[idx],
          gain: farGain,
          decay: farDecay,
          partials: [
            { ratio: 1.0, gain: 1.0 },
            { ratio: 2.0, gain: 0.05 }
          ],
          pan: 0
        }
      }
      // 中等距离恒星（50-500光年）：温暖略带延迟感
      if (distLY > 50) {
        return {
          freq: this.scale[Math.max(0, idx - 2)],
          gain: 0.10,
          decay: 6.0,
          partials: [
            { ratio: 1.0, gain: 1.0 },
            { ratio: 2.0, gain: 0.10 },
            { ratio: 3.0, gain: 0.04 }
          ],
          pan: 0
        }
      }

      if (mag > 5.0) {
        return {
          freq: this.scale[idx],
          gain: 0.10,   // 极轻（光走了很久才到达）
          decay: 8.0,    // 超长衰减
          partials: [
            { ratio: 1.0, gain: 1.0 },
            { ratio: 2.0, gain: 0.08 }
          ],
          pan: 0
        }
      }
      const vol: number = Math.max(0.10, Math.min(0.28, (6.5 - mag) / 8.0)) * 0.45
      const decay: number = tk > 15000 ? 3.0 : 5.0
      return {
        freq: this.scale[Math.max(0, idx - 3)],
        gain: vol,
        decay: decay,
        partials: [
          { ratio: 1.0, gain: 1.0 },
          { ratio: 2.0, gain: 0.12 },
          { ratio: 3.0, gain: tk > 10000 ? 0.05 : 0.02 }
        ],
        pan: 0
      }
    }

    // ── 行星 ──
    if (otype.includes('planet')) {
      const innerPlanets: string[] = ['mercury', 'venus', 'earth', 'mars']
      const isInner: boolean = innerPlanets.some((p: string) => name.toLowerCase().includes(p))
      if (isInner) {
        // 内行星：明亮、短促（快速公转）
        return {
          freq: this.scale[2 + (hash % 5)],
          gain: 0.35,
          decay: 2.0,
          partials: [
            { ratio: 1.0, gain: 1.0 },
            { ratio: 2.0, gain: 0.3 },
            { ratio: 3.0, gain: 0.12 }
          ],
          pan: 0
        }
      } else {
        // 外行星：深沉、长尾、丰富泛音（缓慢公转）
        this.playChime({
          freq: this.scale[2 + (hash % 3)] * 0.5,
          gain: 0.12, decay: 5.0,
          partials: [{ ratio: 1.0, gain: 1.0 }, { ratio: 2.0, gain: 0.15 }],
          pan: 0
        })
        return {
          freq: this.scale[2 + (hash % 5)],
          gain: 0.32,
          decay: 4.5,
          partials: [
            { ratio: 1.0, gain: 1.0 },
            { ratio: 2.0, gain: 0.3 },
            { ratio: 3.0, gain: 0.18 },
            { ratio: 4.0, gain: 0.08 }
          ],
          pan: 0
        }
      }
    }

    // ── 月球 ──
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

    // ── 星系 ──
    if (otype.includes('galax') || otype.includes('quasar')) {
      const isQuasar: boolean = otype.includes('quasar')
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

    // ── 发射星云 ──
    if (otype.includes('emission nebula') || otype.includes('hii')) {
      // 3音递进"膨胀/扩散"效果
      this.playChime({
        freq: this.scale[5 + (hash % 4)],
        gain: 0.15, decay: 5.0,
        partials: [
          { ratio: 1.0, gain: 1.0 },
          { ratio: 2.0, gain: 0.2 }
        ],
        pan: 0
      })
      this.playChime({
        freq: this.scale[8 + (hash % 4)],
        gain: 0.12, decay: 6.0,
        partials: [
          { ratio: 1.0, gain: 1.0 },
          { ratio: 2.0, gain: 0.15 }
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

    // ── 行星状星云 ──
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

    // ── 暗星云 ──
    if (otype.includes('dark nebula')) {
      // 低沉3音递进
      this.playChime({
        freq: this.scale[0 + (hash % 3)] * 0.5,
        gain: 0.14, decay: 5.0,
        partials: [{ ratio: 1.0, gain: 1.0 }, { ratio: 2.0, gain: 0.08 }],
        pan: 0
      })
      this.playChime({
        freq: this.scale[1 + (hash % 3)] * 0.5,
        gain: 0.10, decay: 6.0,
        partials: [{ ratio: 1.0, gain: 1.0 }],
        pan: 0
      })
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

    // ── 反射星云 ──
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

    // ── 超新星遗迹 ──
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

    // ── 一般星云 ──
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

    // ── 疏散星团 ──
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

    // ── 球状星团 ──
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

    // ── 彗星 ──
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

    // ── 小行星 ──
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

    // ── 星座 ──
    if (otype.includes('constellation')) {
      const zodiacNames: string = 'aries|taurus|gemini|cancer|leo|virgo|libra|scorpius|sagittarius|capricornus|aquarius|pisces'
      const isZodiac: boolean = new RegExp(zodiacNames, 'i').test(name)
      if (isZodiac) {
        // 黄道面星座：温暖、饱满、偏中低频
        const base: number = 3 + (hash % 4)
        this.playChime({
          freq: this.scale[base], gain: 0.15, decay: 3.5,
          partials: [{ ratio: 1.0, gain: 1.0 }, { ratio: 2.0, gain: 0.25 }],
          pan: 0
        })
        this.playChime({
          freq: this.scale[base + 2], gain: 0.12, decay: 3.0,
          partials: [{ ratio: 1.0, gain: 1.0 }, { ratio: 1.5, gain: 0.2 }],
          pan: 0
        })
        this.playChime({
          freq: this.scale[base + 4], gain: 0.10, decay: 2.5,
          partials: [{ ratio: 1.0, gain: 1.0 }],
          pan: 0
        })
        return { freq: this.scale[base], gain: 0, decay: 0.01, partials: [], pan: 0 }
      }
      // 一般星座：5音"风铃音阶"（五声音阶递进），同时触发
      const base: number = 5 + (hash % 5)
      this.playChime({
        freq: this.scale[base], gain: 0.12, decay: 3.5,
        partials: [{ ratio: 1.0, gain: 1.0 }, { ratio: 2.0, gain: 0.2 }],
        pan: 0
      })
      this.playChime({
        freq: this.scale[base + 2], gain: 0.10, decay: 3.0,
        partials: [{ ratio: 1.0, gain: 1.0 }, { ratio: 2.0, gain: 0.15 }],
        pan: 0
      })
      this.playChime({
        freq: this.scale[base + 4], gain: 0.10, decay: 2.5,
        partials: [{ ratio: 1.0, gain: 1.0 }, { ratio: 2.0, gain: 0.12 }],
        pan: 0
      })
      this.playChime({
        freq: this.scale[base + 6], gain: 0.08, decay: 2.0,
        partials: [{ ratio: 1.0, gain: 1.0 }],
        pan: 0
      })
      this.playChime({
        freq: this.scale[Math.min(base + 8, this.scale.length - 1)], gain: 0.06, decay: 1.5,
        partials: [{ ratio: 1.0, gain: 1.0 }],
        pan: 0
      })
      return { freq: this.scale[base], gain: 0, decay: 0.01, partials: [], pan: 0 }
    }

    // ── 人造卫星 / 空间站 ──
    if (otype.includes('artificial') || otype.includes('satellite')) {
      const isStation: boolean = name.toLowerCase().includes('iss') ||
        name.toLowerCase().includes('station') ||
        name.toLowerCase().includes('tiangong')
      if (isStation) {
        // 空间站：低沉脉冲 + 高频信号，"机械心跳"
        this.playChime({
          freq: this.scale[2], gain: 0.20, decay: 2.5,
          partials: [{ ratio: 1.0, gain: 1.0 }, { ratio: 2.0, gain: 0.15 }],
          pan: 0
        })
        this.playChime({
          freq: this.scale[2] * 1.5, gain: 0.15, decay: 1.5,
          partials: [{ ratio: 1.0, gain: 1.0 }, { ratio: 2.0, gain: 0.2 }],
          pan: 0
        })
        this.playChime({
          freq: this.scale[14], gain: 0.18, decay: 0.8,
          partials: [{ ratio: 1.0, gain: 1.0 }, { ratio: 3.0, gain: 0.15 }],
          pan: 0
        })
        this.playChime({
          freq: this.scale[14] * 2, gain: 0.10, decay: 0.4,
          partials: [{ ratio: 1.0, gain: 1.0 }],
          pan: 0
        })
        return { freq: this.scale[0], gain: 0, decay: 0.01, partials: [], pan: 0 }
      }
      // 一般卫星：2个递进高频短促beep（电子信号感）
      // 降低增益和泛音强度，减少刺耳感但保持尖锐特色
      this.playChime({
        freq: this.scale[14 + (hash % 3)],
        gain: 0.16, decay: 1.0,
        partials: [{ ratio: 1.0, gain: 1.0 }, { ratio: 2.0, gain: 0.12 }],
        pan: 0
      })
      this.playChime({
        freq: this.scale[14 + (hash % 3)] * 1.5,
        gain: 0.09, decay: 0.5,
        partials: [{ ratio: 1.0, gain: 1.0 }],
        pan: 0
      })
      return { freq: this.scale[0], gain: 0, decay: 0.01, partials: [], pan: 0 }
    }

    // ── 默认 ──
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
    slot.attack = Math.floor(0.030 * SR)   // 30ms attack
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
