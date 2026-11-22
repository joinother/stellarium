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
