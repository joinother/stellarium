export const add: (a: number, b: number) => number;
export const setEnv: (name: string, value: string) => boolean;
export const command: (name: string, payload: string) => string;
export const isPresentationReady: () => boolean;
export const isEngineReady: () => boolean;
export const probeArHardware: () => string;
export const createArCameraSurface: () => string;
export const destroyArCameraSurface: () => void;
export const setArCameraComposite: (enabled: boolean, blend: number, cameraAspect: number, baseFovDeg?: number) => void;
export const renderDetailModelSphere: (
  texture: ArrayBuffer,
  textureWidth: number,
  textureHeight: number,
  textureStride: number,
  ringTexture: ArrayBuffer | undefined,
  ringWidth: number,
  ringHeight: number,
  hasRing: boolean,
  ringInner: number,
  ringOuter: number,
  ringOpacity: number,
  renderSize: number,
  scale: number,
  transform: number[],
  hasLighting: boolean,
  emissive: boolean,
  lightX: number,
  lightY: number,
  lightZ: number,
) => ArrayBuffer | undefined;
export const renderDetailModelProcedural: (
  kind: string,
  temperature: number,
  particles: Float32Array,
  renderSize: number,
  scale: number,
  transform: number[],
) => ArrayBuffer | undefined;
export const renderDetailModelConstellation: (
  scmBuffer: ArrayBuffer,
  renderSize: number,
  scale: number,
  transform: number[],
) => ArrayBuffer | undefined;
export const renderDetailModelBodyMesh: (
  sbmBuffer: ArrayBuffer,
  texture: ArrayBuffer | undefined,
  textureWidth: number,
  textureHeight: number,
  textureStride: number,
  renderSize: number,
  scale: number,
  transform: number[],
  hasLighting: boolean,
  lightX: number,
  lightY: number,
  lightZ: number,
) => ArrayBuffer | undefined;
export const aetherisRender: (buffer: ArrayBuffer) => number;
export const aetherisSetMaster: (musicEnabled: boolean, sfxEnabled: boolean, volume: number, ducked: boolean) => void;
export const aetherisSetDNA: (
  seed: string,
  mood: string,
  rootPc: number,
  jade: number,
  felt: number,
  tape: number,
  bowl: number,
  variation: number,
) => void;
export const aetherisApplySeed: (seed: string) => string;
export const aetherisSetOutputMode: (isSpeaker: boolean) => void;
export const aetherisSetHorizonAltitude: (altDeg: number) => void;
export const aetherisSetLowPower: (enabled: boolean) => void;
export const aetherisSkipNextAct: () => void;
export const aetherisTriggerStar: (tempK: number, mag: number, distLy: number, pan: number, altitude: number) => void;
export const aetherisTriggerCue: (cueId: string, pan: number) => void;
export const aetherisReset: () => void;
