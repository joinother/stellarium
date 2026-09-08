export interface GuideStep {
  target: string;
  fov: number;
  title: string;
  text: string;
  seconds: number;
}

export interface AstronomyGuide {
  id: string;
  title: string;
  credit: string;
  steps: GuideStep[];
}

export interface GuideResult {
  ok: boolean;
  error?: string;
}

export interface GuideState {
  active: boolean;
  phase: string;
  guideId: string;
  index: number;
  count: number;
  automatic: boolean;
  remaining: number;
  error: string;
}

export const ASTRONOMY_GUIDES: AstronomyGuide[] = [
  {
    id: 'solar-neighbours', title: 'guide_solar', credit: 'guide_credit',
    steps: [
      { target: 'Moon', fov: 2, title: 'Moon', text: 'guide_moon', seconds: 25 },
      { target: 'Venus', fov: 0.15, title: 'Venus', text: 'guide_venus', seconds: 25 },
      { target: 'Mars', fov: 0.08, title: 'Mars', text: 'guide_mars', seconds: 25 },
      { target: 'Jupiter', fov: 0.25, title: 'Jupiter', text: 'guide_jupiter', seconds: 30 },
      { target: 'Saturn', fov: 0.15, title: 'Saturn', text: 'guide_saturn', seconds: 30 }
    ]
  },
  {
    id: 'deep-sky-discovery', title: 'guide_deep', credit: 'guide_credit',
    steps: [
      { target: 'M31', fov: 7, title: 'M31', text: 'guide_m31', seconds: 30 },
      { target: 'M42', fov: 3, title: 'M42', text: 'guide_m42', seconds: 30 },
      { target: 'M45', fov: 5, title: 'M45', text: 'guide_m45', seconds: 30 }
    ]
  }
];

export class GuidePlayer {
  private state: GuideState = {
    active: false, phase: 'idle', guideId: '', index: 0, count: 0,
    automatic: false, remaining: 0, error: ''
  };
  private guide: AstronomyGuide | undefined;
  private busy: boolean = false;
  private stopping: boolean = false;
  private pending: Promise<GuideResult> = Promise.resolve({ ok: true });
  private execute: (command: string, payload: string) => Promise<GuideResult>;
  private changed: (state: GuideState) => void;

  constructor(execute: (command: string, payload: string) => Promise<GuideResult>, changed: (state: GuideState) => void) {
    this.execute = execute;
    this.changed = changed;
  }

  snapshot(): GuideState { return { ...this.state }; }

  private publish(): void { this.changed(this.snapshot()); }

  private async send(command: string, payload: string = ''): Promise<GuideResult> {
    try { return await this.execute(command, payload); }
    catch { return { ok: false, error: 'bridge_failure' }; }
  }

  private fail(result: GuideResult): GuideResult {
    this.state.phase = 'error';
    this.state.error = result.error ?? 'command_failed';
    this.publish();
    return result;
  }

  async start(id: string): Promise<GuideResult> {
    if (this.state.active || this.busy) return { ok: false, error: 'session_busy' };
    const guide = ASTRONOMY_GUIDES.find((item: AstronomyGuide) => item.id === id);
    if (!guide) return { ok: false, error: 'unknown_guide' };
    this.guide = guide;
    this.state = { active: true, phase: 'preparing', guideId: id, index: 0,
      count: guide.steps.length, automatic: false, remaining: 0, error: '' };
    this.busy = true;
    this.publish();
    this.pending = this.send('beginGuidedSession');
    const result = await this.pending;
    this.busy = false;
    if (!result.ok) {
      this.state.active = false;
      return this.fail(result);
    }
    if (this.stopping) return { ok: false, error: 'stopping' };
    return this.go(0);
  }

  private async applyStep(step: GuideStep): Promise<GuideResult> {
    const commands: string[][] = [
      ['setTimeRate', '0'], ['setActionChecked', 'actionShow_MistHorizon|0'],
      ['setAtmosphereFlag', 'atmosphere|0'], ['setAtmosphereFlag', 'landscape|0'],
      ['searchObject', step.target + '|selectOnly'], ['moveToSelected', ''],
      ['setFOV', step.fov.toString()]
    ];
    for (const item of commands) {
      if (this.stopping) return { ok: false, error: 'stopping' };
      const result = await this.send(item[0], item[1]);
      if (!result.ok) return result;
    }
    return { ok: true };
  }

  async go(index: number): Promise<GuideResult> {
    if (!this.state.active || !this.guide || this.busy || this.stopping) return { ok: false, error: 'session_busy' };
    if (!Number.isInteger(index) || index < 0 || index >= this.guide.steps.length) return { ok: false, error: 'invalid_step' };
    this.busy = true;
    this.state.phase = 'preparing';
    this.state.index = index;
    this.state.error = '';
    this.publish();
    const step = this.guide.steps[index];
    this.pending = this.applyStep(step);
    const result = await this.pending;
    this.busy = false;
    if (this.stopping) return result;
    if (!result.ok) return this.fail(result);
    this.state.index = index;
    this.state.remaining = step.seconds;
    this.state.phase = 'observing';
    this.publish();
    return result;
  }

  async action(action: string): Promise<GuideResult> {
    if (action === 'stop') return this.stop();
    if (!this.state.active || !this.guide || this.busy || this.stopping) return { ok: false, error: 'session_busy' };
    if (action === 'next') {
      return this.state.index + 1 < this.state.count ? this.go(this.state.index + 1) : this.stop();
    }
    if (action === 'previous') return this.go(this.state.index - 1);
    if (action === 'return' || action === 'retry') return this.go(this.state.index);
    if (action === 'pause' || action === 'explore') {
      if (this.state.phase !== 'observing') return { ok: false, error: 'invalid_phase' };
      this.state.phase = action === 'pause' ? 'paused' : 'exploring';
    } else if (action === 'resume') {
      if (this.state.phase !== 'paused') return { ok: false, error: 'invalid_phase' };
      this.state.phase = 'observing';
    } else if (action === 'auto-on' || action === 'auto-off') {
      this.state.automatic = action === 'auto-on';
    } else if (action === 'closer' || action === 'wider' || action === 'center') {
      this.busy = true;
      const step = this.guide.steps[this.state.index];
      this.pending = this.send(action === 'center' ? 'moveToSelected' : 'setFOV',
        action === 'center' ? '' : (step.fov * (action === 'closer' ? 0.5 : 3)).toString());
      const result = await this.pending;
      this.busy = false;
      if (!this.stopping && !result.ok) return this.fail(result);
      return result;
    } else return { ok: false, error: 'unknown_action' };
    this.publish();
    return { ok: true };
  }

  tick(seconds: number): void {
    if (!this.state.active || !this.state.automatic || this.state.phase !== 'observing' ||
      this.busy || this.stopping || !Number.isFinite(seconds) || seconds <= 0) return;
    this.state.remaining = Math.max(0, this.state.remaining - Math.min(seconds, 1));
    this.publish();
    if (this.state.remaining === 0) this.action('next');
  }

  async stop(): Promise<GuideResult> {
    if (!this.state.active) return { ok: true };
    if (this.stopping) return { ok: false, error: 'stopping' };
    this.stopping = true;
    this.state.phase = 'restoring';
    this.publish();
    await this.pending;
    const result = await this.send('endGuidedSession');
    this.busy = false;
    this.stopping = false;
    if (!result.ok) return this.fail(result);
    this.state.active = false;
    this.state.phase = 'idle';
    this.state.error = '';
    this.publish();
    return result;
  }
}
