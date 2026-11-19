export type GuideCategory = 'stargazing' | 'solar_system' | 'deep_sky' | 'events' | 'sky_culture';

export interface GuideLocation {
  name: string;
  lat: number;
  lon: number;
  alt: number;
}

export interface GuideActionToggle {
  id: string;
  enabled: boolean;
}

export interface GuideScenePatch {
  atmosphere?: boolean;
  landscape?: boolean;
  jd?: number;
  timeRate?: number;
  location?: GuideLocation;
  observerPlanet?: string;
  skyCulture?: string;
  actions?: GuideActionToggle[];
}

export interface GuideStep {
  target: string;
  fov: number;
  title: string;
  text: string;
  seconds: number;
  scene?: GuideScenePatch;
  guideLines?: string[][];
}

export interface AstronomyGuide {
  id: string;
  category: GuideCategory;
  title: string;
  summary: string;
  credit: string;
  replacesScripts?: string[];
  initState?: GuideScenePatch;
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
    id: 'solar-neighbours',
    category: 'solar_system',
    title: 'guide_solar',
    summary: 'guide_solar_summary',
    credit: 'guide_credit',
    replacesScripts: ['planets_tour.ssc'],
    steps: [
      { target: 'Moon', fov: 2, title: 'Moon', text: 'guide_moon', seconds: 25 },
      { target: 'Venus', fov: 0.15, title: 'Venus', text: 'guide_venus', seconds: 25 },
      { target: 'Mars', fov: 0.08, title: 'Mars', text: 'guide_mars', seconds: 25 },
      { target: 'Jupiter', fov: 0.25, title: 'Jupiter', text: 'guide_jupiter', seconds: 30 },
      { target: 'Saturn', fov: 0.15, title: 'Saturn', text: 'guide_saturn', seconds: 30 }
    ]
  },
  {
    id: 'deep-sky-discovery',
    category: 'deep_sky',
    title: 'guide_deep',
    summary: 'guide_deep_summary',
    credit: 'guide_credit',
    replacesScripts: ['binocular_highlights.ssc'],
    steps: [
      { target: 'M31', fov: 7, title: 'M31', text: 'guide_m31', seconds: 30 },
      { target: 'M42', fov: 3, title: 'M42', text: 'guide_m42', seconds: 30 },
      { target: 'M45', fov: 5, title: 'M45', text: 'guide_m45', seconds: 30 }
    ]
  },
  {
    id: 'summer-star-hopping',
    category: 'stargazing',
    title: 'guide_summer_sky',
    summary: 'guide_summer_sky_summary',
    credit: 'guide_credit',
    replacesScripts: ['constellations_tour.ssc', 'modern_constellations_tour.ssc'],
    initState: {
      atmosphere: true,
      landscape: true,
      jd: 2461248.041667,
      timeRate: 0,
      location: { name: 'Taipei', lat: 25.0375, lon: 121.5625, alt: 10 },
      skyCulture: 'modern',
      actions: [
        { id: 'actionShow_Constellation_Lines', enabled: true },
        { id: 'actionShow_Constellation_Labels', enabled: true },
        { id: 'actionShow_Constellation_Art', enabled: false },
        { id: 'actionShow_Nebulas', enabled: false },
        { id: 'actionShow_Cardinal_Points', enabled: true },
        { id: 'actionShow_MilkyWay', enabled: true }
      ]
    },
    steps: [
      { target: 'Ursa Major', fov: 55, title: 'guide_step_big_dipper', text: 'guide_summer_1', seconds: 25 },
      {
        target: 'Polaris', fov: 58, title: 'guide_step_polaris', text: 'guide_summer_2', seconds: 25,
        guideLines: [['Merak', 'Dubhe', 'Polaris']]
      },
      {
        target: 'Cassiopeia', fov: 58, title: 'guide_step_cassiopeia', text: 'guide_summer_3', seconds: 25,
        guideLines: [['Merak', 'Dubhe', 'Polaris', 'Schedar']]
      },
      {
        target: 'Arcturus', fov: 85, title: 'guide_step_arcturus_spica', text: 'guide_summer_4', seconds: 30,
        guideLines: [['Alkaid', 'Arcturus', 'Spica']]
      },
      {
        target: 'Deneb', fov: 80, title: 'guide_step_deneb', text: 'guide_summer_5', seconds: 25,
        guideLines: [['Merak', 'Dubhe', 'Deneb']]
      },
      {
        target: 'Sadr', fov: 70, title: 'guide_step_summer_triangle', text: 'guide_summer_6', seconds: 30,
        guideLines: [['Vega', 'Deneb', 'Altair', 'Vega']]
      },
      { target: 'Antares', fov: 58, title: 'guide_step_scorpius', text: 'guide_summer_7', seconds: 25 },
      { target: 'Sagittarius', fov: 58, title: 'guide_step_sagittarius', text: 'guide_summer_8', seconds: 30 }
    ]
  },
  {
    id: 'winter-star-hopping',
    category: 'stargazing',
    title: 'guide_winter_sky',
    summary: 'guide_winter_sky_summary',
    credit: 'guide_credit',
    replacesScripts: ['constellations_tour.ssc', 'modern_constellations_tour.ssc'],
    initState: {
      atmosphere: true,
      landscape: true,
      jd: 2461056.041667,
      timeRate: 0,
      location: { name: 'Beijing', lat: 39.9042, lon: 116.4074, alt: 43 },
      skyCulture: 'modern',
      actions: [
        { id: 'actionShow_Constellation_Lines', enabled: true },
        { id: 'actionShow_Constellation_Labels', enabled: true },
        { id: 'actionShow_Constellation_Art', enabled: false },
        { id: 'actionShow_Nebulas', enabled: false },
        { id: 'actionShow_Cardinal_Points', enabled: true },
        { id: 'actionShow_MilkyWay', enabled: true }
      ]
    },
    steps: [
      { target: 'Alnilam', fov: 46, title: 'guide_step_orion_belt', text: 'guide_winter_1', seconds: 25 },
      {
        target: 'Sirius', fov: 56, title: 'guide_step_sirius', text: 'guide_winter_2', seconds: 25,
        guideLines: [['Mintaka', 'Alnilam', 'Alnitak', 'Sirius']]
      },
      {
        target: 'Betelgeuse', fov: 65, title: 'guide_step_winter_triangle', text: 'guide_winter_3', seconds: 30,
        guideLines: [['Betelgeuse', 'Sirius', 'Procyon', 'Betelgeuse']]
      },
      {
        target: 'Aldebaran', fov: 56, title: 'guide_step_taurus_pleiades', text: 'guide_winter_4', seconds: 25,
        guideLines: [['Alnitak', 'Alnilam', 'Mintaka', 'Aldebaran', 'Alcyone']]
      },
      {
        target: 'Capella', fov: 60, title: 'guide_step_auriga_gemini', text: 'guide_winter_5', seconds: 25,
        guideLines: [['Aldebaran', 'Capella', 'Pollux']]
      },
      {
        target: 'Alhena', fov: 88, title: 'guide_step_winter_hexagon', text: 'guide_winter_6', seconds: 30,
        guideLines: [['Sirius', 'Procyon', 'Pollux', 'Capella', 'Aldebaran', 'Rigel', 'Sirius']]
      }
    ]
  },
  {
    id: 'zodiac-ecliptic',
    category: 'stargazing',
    title: 'guide_zodiac',
    summary: 'guide_zodiac_summary',
    credit: 'guide_credit',
    replacesScripts: ['zodiac.ssc'],
    initState: {
      atmosphere: false,
      landscape: false,
      timeRate: 0,
      skyCulture: 'modern',
      actions: [
        { id: 'actionShow_Ecliptic_Line', enabled: true },
        { id: 'actionShow_Constellation_Lines', enabled: true },
        { id: 'actionShow_Constellation_Labels', enabled: true },
        { id: 'actionShow_Constellation_Art', enabled: true },
        { id: 'actionShow_Nebulas', enabled: false }
      ]
    },
    steps: [
      { target: 'Aries', fov: 48, title: 'guide_step_aries', text: 'guide_zodiac_1', seconds: 20 },
      { target: 'Taurus', fov: 50, title: 'guide_step_taurus', text: 'guide_zodiac_2', seconds: 20 },
      { target: 'Gemini', fov: 48, title: 'guide_step_gemini', text: 'guide_zodiac_3', seconds: 20 },
      { target: 'Cancer', fov: 48, title: 'guide_step_cancer', text: 'guide_zodiac_4', seconds: 20 },
      { target: 'Leo', fov: 52, title: 'guide_step_leo', text: 'guide_zodiac_5', seconds: 20 },
      { target: 'Virgo', fov: 58, title: 'guide_step_virgo', text: 'guide_zodiac_6', seconds: 20 },
      { target: 'Libra', fov: 48, title: 'guide_step_libra', text: 'guide_zodiac_7', seconds: 20 },
      { target: 'Scorpius', fov: 52, title: 'guide_step_scorpius', text: 'guide_zodiac_8', seconds: 20 },
      { target: 'Sagittarius', fov: 52, title: 'guide_step_sagittarius', text: 'guide_zodiac_9', seconds: 20 },
      { target: 'Capricornus', fov: 48, title: 'guide_step_capricornus', text: 'guide_zodiac_10', seconds: 20 },
      { target: 'Aquarius', fov: 54, title: 'guide_step_aquarius', text: 'guide_zodiac_11', seconds: 20 },
      { target: 'Pisces', fov: 56, title: 'guide_step_pisces', text: 'guide_zodiac_12', seconds: 20 }
    ]
  },
  {
    id: 'jupiter-galilean-moons',
    category: 'solar_system',
    title: 'guide_jupiter_moons',
    summary: 'guide_jupiter_moons_summary',
    credit: 'guide_credit',
    replacesScripts: ['BAS_Jupiter_Moons.ssc', 'morsels_1.ssc'],
    initState: {
      atmosphere: false,
      landscape: false,
      timeRate: 0
    },
    steps: [
      { target: 'Jupiter', fov: 0.45, title: 'guide_step_jup_system', text: 'guide_jup_1', seconds: 25 },
      { target: 'Io', fov: 0.008, title: 'guide_step_io', text: 'guide_jup_2', seconds: 25 },
      { target: 'Europa', fov: 0.008, title: 'guide_step_europa', text: 'guide_jup_3', seconds: 25 },
      { target: 'Ganymede', fov: 0.01, title: 'guide_step_ganymede', text: 'guide_jup_4', seconds: 25 },
      { target: 'Callisto', fov: 0.01, title: 'guide_step_callisto', text: 'guide_jup_5', seconds: 25 },
      {
        target: 'Jupiter', fov: 0.025, title: 'guide_step_triple_shadow', text: 'guide_jup_6', seconds: 30,
        scene: { jd: 2457046.777778, timeRate: 0 }
      }
    ]
  },
  {
    id: 'messier-highlights',
    category: 'deep_sky',
    title: 'guide_messier',
    summary: 'guide_messier_summary',
    credit: 'guide_credit',
    replacesScripts: ['BAS_Messier_Tour.ssc', 'messier_marathon.ssc', 'binosky.ssc'],
    initState: {
      atmosphere: false,
      landscape: false,
      timeRate: 0,
      actions: [
        { id: 'actionShow_Nebulas', enabled: true },
        { id: 'actionShow_DSO_Textures', enabled: true },
        { id: 'actionShow_MilkyWay', enabled: true }
      ]
    },
    steps: [
      { target: 'M1', fov: 0.8, title: 'guide_step_m1', text: 'guide_messier_1', seconds: 25 },
      { target: 'M8', fov: 3.5, title: 'guide_step_m8', text: 'guide_messier_2', seconds: 25 },
      { target: 'M13', fov: 1.2, title: 'guide_step_m13', text: 'guide_messier_3', seconds: 25 },
      { target: 'M27', fov: 0.9, title: 'guide_step_m27', text: 'guide_messier_4', seconds: 25 },
      { target: 'M44', fov: 4.5, title: 'guide_step_m44', text: 'guide_messier_5', seconds: 25 },
      { target: 'M51', fov: 0.9, title: 'guide_step_m51', text: 'guide_messier_6', seconds: 25 },
      { target: 'M57', fov: 0.35, title: 'guide_step_m57', text: 'guide_messier_7', seconds: 25 },
      { target: 'M104', fov: 0.8, title: 'guide_step_m104', text: 'guide_messier_8', seconds: 25 }
    ]
  },
  {
    id: 'double-and-giant-stars',
    category: 'deep_sky',
    title: 'guide_stars_tour',
    summary: 'guide_stars_tour_summary',
    credit: 'guide_credit',
    replacesScripts: ['double_stars.ssc', 'largest_known_stars.ssc'],
    initState: {
      atmosphere: false,
      landscape: false,
      timeRate: 0,
      actions: [
        { id: 'actionShow_Constellation_Lines', enabled: true },
        { id: 'actionShow_Constellation_Labels', enabled: true },
        { id: 'actionShow_Nebulas', enabled: false }
      ]
    },
    steps: [
      { target: 'Mizar', fov: 1.8, title: 'guide_step_mizar', text: 'guide_stars_1', seconds: 25 },
      { target: 'Albireo', fov: 0.25, title: 'guide_step_albireo', text: 'guide_stars_2', seconds: 25 },
      { target: 'Epsilon Lyrae', fov: 0.4, title: 'guide_step_eps_lyrae', text: 'guide_stars_3', seconds: 25 },
      { target: 'Antares', fov: 18, title: 'guide_step_antares_giant', text: 'guide_stars_4', seconds: 25 },
      { target: 'Betelgeuse', fov: 22, title: 'guide_step_betelgeuse_giant', text: 'guide_stars_5', seconds: 25 },
      { target: 'Mu Cep', fov: 12, title: 'guide_step_mu_cep', text: 'guide_stars_6', seconds: 25 }
    ]
  },
  {
    id: 'classic-eclipses-transits',
    category: 'events',
    title: 'guide_eclipses',
    summary: 'guide_eclipses_summary',
    credit: 'guide_credit',
    replacesScripts: ['solar_eclipse.ssc', 'lunar_total.ssc', 'transit_of_venus.ssc'],
    initState: {
      timeRate: 0,
      actions: [
        { id: 'actionShow_Constellation_Lines', enabled: false },
        { id: 'actionShow_Nebulas', enabled: false }
      ]
    },
    steps: [
      {
        target: 'Sun', fov: 3.5, title: 'guide_step_eclipse_2009', text: 'guide_event_1', seconds: 30,
        scene: {
          atmosphere: true, landscape: true,
          location: { name: 'Shanghai', lat: 31.2304, lon: 121.4737, alt: 10 },
          jd: 2455034.568866
        }
      },
      {
        target: 'Moon', fov: 1.6, title: 'guide_step_lunar_2004', text: 'guide_event_2', seconds: 30,
        scene: {
          atmosphere: false, landscape: false,
          jd: 2453130.354167
        }
      },
      {
        target: 'Sun', fov: 1.1, title: 'guide_step_venus_2012', text: 'guide_event_3', seconds: 30,
        scene: {
          atmosphere: true, landscape: true,
          location: { name: 'Sydney', lat: -33.8688, lon: 151.2093, alt: 20 },
          jd: 2456084.561806
        }
      },
      {
        target: 'Sun', fov: 1.0, title: 'guide_step_mercury_2019', text: 'guide_event_4', seconds: 30,
        scene: {
          atmosphere: false, landscape: false,
          location: { name: 'Quito', lat: -0.1807, lon: -78.4678, alt: 2850 },
          jd: 2458799.138889
        }
      }
    ]
  },
  {
    id: 'world-sky-cultures',
    category: 'sky_culture',
    title: 'guide_cultures',
    summary: 'guide_cultures_summary',
    credit: 'guide_credit',
    replacesScripts: ['sky_cultures.ssc'],
    initState: {
      atmosphere: true,
      landscape: true,
      jd: 2461056.041667,
      timeRate: 0,
      location: { name: 'Beijing', lat: 39.9042, lon: 116.4074, alt: 43 },
      actions: [
        { id: 'actionShow_Constellation_Lines', enabled: true },
        { id: 'actionShow_Constellation_Labels', enabled: true },
        { id: 'actionShow_Constellation_Art', enabled: true },
        { id: 'actionShow_Nebulas', enabled: false }
      ]
    },
    steps: [
      { target: 'Alnilam', fov: 72, title: 'guide_step_culture_modern', text: 'guide_culture_1', seconds: 25, scene: { skyCulture: 'modern' } },
      { target: 'Alnilam', fov: 72, title: 'guide_step_culture_chinese', text: 'guide_culture_2', seconds: 25, scene: { skyCulture: 'chinese' } },
      { target: 'Alnilam', fov: 72, title: 'guide_step_culture_greek', text: 'guide_culture_3', seconds: 25, scene: { skyCulture: 'greek_almagest' } },
      { target: 'Alnilam', fov: 72, title: 'guide_step_culture_egyptian', text: 'guide_culture_4', seconds: 25, scene: { skyCulture: 'egyptian' } },
      { target: 'Alnilam', fov: 72, title: 'guide_step_culture_norse', text: 'guide_culture_5', seconds: 25, scene: { skyCulture: 'norse' } },
      { target: 'Alnilam', fov: 72, title: 'guide_step_culture_inuit', text: 'guide_culture_6', seconds: 25, scene: { skyCulture: 'inuit' } }
    ]
  },
  {
    id: 'sun-across-planets',
    category: 'solar_system',
    title: 'guide_sun_planets',
    summary: 'guide_sun_planets_summary',
    credit: 'guide_credit',
    replacesScripts: ['sun.ssc'],
    initState: {
      atmosphere: false,
      landscape: false,
      timeRate: 0,
      actions: [
        { id: 'actionShow_Constellation_Lines', enabled: false },
        { id: 'actionShow_Nebulas', enabled: false }
      ]
    },
    steps: [
      { target: 'Sun', fov: 2.2, title: 'guide_step_sun_mercury', text: 'guide_sun_1', seconds: 22, scene: { observerPlanet: 'Mercury', jd: 2457728.645058 } },
      { target: 'Sun', fov: 2.2, title: 'guide_step_sun_venus', text: 'guide_sun_2', seconds: 22, scene: { observerPlanet: 'Venus', jd: 2457463.228403 } },
      { target: 'Sun', fov: 2.2, title: 'guide_step_sun_earth', text: 'guide_sun_3', seconds: 22, scene: { observerPlanet: 'Earth', jd: 2457381.978414 } },
      { target: 'Sun', fov: 2.2, title: 'guide_step_sun_mars', text: 'guide_sun_4', seconds: 22, scene: { observerPlanet: 'Mars', jd: 2457728.353391 } },
      { target: 'Sun', fov: 2.2, title: 'guide_step_sun_jupiter', text: 'guide_sun_5', seconds: 22, scene: { observerPlanet: 'Jupiter', jd: 2457728.289502 } },
      { target: 'Sun', fov: 2.2, title: 'guide_step_sun_saturn', text: 'guide_sun_6', seconds: 22, scene: { observerPlanet: 'Saturn', jd: 2453345.164502 } },
      { target: 'Sun', fov: 2.2, title: 'guide_step_sun_pluto', text: 'guide_sun_7', seconds: 22, scene: { observerPlanet: 'Pluto', jd: 2457426.060336 } }
    ]
  }
];

export function guideHasSkyAtmosphere(guide: AstronomyGuide, stepIndex: number): boolean {
  const step = guide.steps[stepIndex];
  if (step?.scene?.atmosphere !== undefined) return step.scene.atmosphere;
  return guide.initState?.atmosphere === true;
}

export function guideUsesOverlayLines(guide: AstronomyGuide): boolean {
  return guide.steps.some((step: GuideStep) => step.guideLines !== undefined && step.guideLines.length > 0);
}

function mergeActions(base?: GuideActionToggle[], patch?: GuideActionToggle[]): GuideActionToggle[] {
  const merged: GuideActionToggle[] = [];
  const upsert = (item: GuideActionToggle): void => {
    const idx = merged.findIndex((existing: GuideActionToggle) => existing.id === item.id);
    if (idx >= 0) merged[idx] = { id: item.id, enabled: item.enabled };
    else merged.push({ id: item.id, enabled: item.enabled });
  };
  if (base) {
    for (const item of base) upsert(item);
  }
  if (patch) {
    for (const item of patch) upsert(item);
  }
  return merged;
}

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

  private buildStepCommands(guide: AstronomyGuide, step: GuideStep): string[][] {
    const init = guide.initState;
    const patch = step.scene;
    const atmosphere = patch?.atmosphere ?? init?.atmosphere ?? false;
    const landscape = patch?.landscape ?? init?.landscape ?? false;
    const timeRate = patch?.timeRate ?? init?.timeRate ?? 0;
    const jd = patch?.jd ?? init?.jd;
    const location = patch?.location ?? init?.location;
    const observerPlanet = patch?.observerPlanet ?? init?.observerPlanet;
    const skyCulture = patch?.skyCulture ?? init?.skyCulture;
    const actions = mergeActions(init?.actions, patch?.actions);

    const commands: string[][] = [
      ['setTimeRate', '0'],
      ['setActionChecked', 'actionShow_MistHorizon|0']
    ];
    if (observerPlanet !== undefined && observerPlanet.length > 0) {
      commands.push(['setObserverPlanet', observerPlanet]);
    } else if (location !== undefined) {
      commands.push(['setLocation',
        location.name + '|' + location.lat.toString() + '|' + location.lon.toString() + '|' + location.alt.toString()]);
    }
    if (jd !== undefined) {
      commands.push(['setJD', jd.toString()]);
    }
    if (skyCulture !== undefined && skyCulture.length > 0) {
      commands.push(['setSkyCulture', skyCulture]);
    }
    commands.push(['setAtmosphereFlag', atmosphere ? 'atmosphere|1' : 'atmosphere|0']);
    commands.push(['setAtmosphereFlag', landscape ? 'landscape|1' : 'landscape|0']);
    for (const toggle of actions) {
      commands.push(['setActionChecked', toggle.id + (toggle.enabled ? '|1' : '|0')]);
    }
    if (step.guideLines !== undefined && step.guideLines.length > 0) {
      const encoded = step.guideLines.map((line: string[]) => line.join('|')).join(';');
      commands.push(['setGuideOverlayLines', encoded]);
    } else if (guideUsesOverlayLines(guide)) {
      commands.push(['setGuideOverlayLines', '']);
    }
    commands.push(['searchObject', step.target + '|selectOnly']);
    commands.push(['moveToSelected', '']);
    commands.push(['setFOV', step.fov.toString()]);
    if (timeRate !== 0) {
      commands.push(['setTimeRate', timeRate.toString()]);
    }
    return commands;
  }

  private async applyStep(step: GuideStep): Promise<GuideResult> {
    if (!this.guide) return { ok: false, error: 'unknown_guide' };
    const commands = this.buildStepCommands(this.guide, step);
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
