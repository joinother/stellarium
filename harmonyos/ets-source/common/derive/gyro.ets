// Gyroscope quaternion / vector math helpers.
// Migrated verbatim from pages/MainWindowNativeNode.ets (plan §14.2, track A1-1).
// These are pure, stateless file-level functions: no host-field access, no IO,
// no store/UI imports. They only operate on the `number[]` arguments passed in.

export function gyroNormalizeQuaternion(q: number[]): number[] {
  const length = Math.sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3])
  if (length < 0.000001) { return [0, 0, 0, 1] }
  return [q[0] / length, q[1] / length, q[2] / length, q[3] / length]
}

export function gyroConjugateQuaternion(q: number[]): number[] {
  return [-q[0], -q[1], -q[2], q[3]]
}

export function gyroMultiplyQuaternions(a: number[], b: number[]): number[] {
  return [
    a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1],
    a[3] * b[1] - a[0] * b[2] + a[1] * b[3] + a[2] * b[0],
    a[3] * b[2] + a[0] * b[1] - a[1] * b[0] + a[2] * b[3],
    a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2]
  ]
}

export function gyroNormalizeVector(v: number[]): number[] {
  const length = Math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
  if (length < 0.000001) { return [1, 0, 0] }
  return [v[0] / length, v[1] / length, v[2] / length]
}

// Rotate about the local vertical. Azimuth in the bridge frame is
// atan2(y, x), so the helper adds `deg` to the azimuth of any vector.
export function gyroRotateAboutVertical(v: number[], deg: number): number[] {
  if (deg === 0) { return v }
  const r = deg * Math.PI / 180
  const c = Math.cos(r)
  const s = Math.sin(r)
  return [v[0] * c - v[1] * s, v[0] * s + v[1] * c, v[2]]
}

export function gyroRotateAboutAxis(v: number[], axis: number[], deg: number): number[] {
  if (deg === 0) { return v }
  const r = deg * Math.PI / 180
  const c = Math.cos(r)
  const s = Math.sin(r)
  const d = axis[0] * v[0] + axis[1] * v[1] + axis[2] * v[2]
  const cx = axis[1] * v[2] - axis[2] * v[1]
  const cy = axis[2] * v[0] - axis[0] * v[2]
  const cz = axis[0] * v[1] - axis[1] * v[0]
  return [
    v[0] * c + cx * s + axis[0] * d * (1 - c),
    v[1] * c + cy * s + axis[1] * d * (1 - c),
    v[2] * c + cz * s + axis[2] * d * (1 - c)
  ]
}

export function gyroFilterDeviceVector(previous: number[], sample: number[], alpha: number): number[] {
  if (previous.length !== 3) { return sample }
  return [
    previous[0] + (sample[0] - previous[0]) * alpha,
    previous[1] + (sample[1] - previous[1]) * alpha,
    previous[2] + (sample[2] - previous[2]) * alpha
  ]
}

export function gyroCross(a: number[], b: number[]): number[] {
  return [
    a[1] * b[2] - a[2] * b[1],
    a[2] * b[0] - a[0] * b[2],
    a[0] * b[1] - a[1] * b[0]
  ]
}

export function gyroDot(a: number[], b: number[]): number {
  return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}

export function gyroScreenAxisForDisplay(axis: number[], rotation: number): number[] {
  const angle = rotation * Math.PI / 2
  const c = Math.cos(angle)
  const s = Math.sin(angle)
  return [axis[0] * c - axis[1] * s, axis[0] * s + axis[1] * c, axis[2]]
}

export function wrapGyroAzimuth(angle: number): number {
  let wrapped = angle % 360
  if (wrapped < 0) { wrapped += 360 }
  return wrapped
}

export function shortestGyroAzimuthDelta(from: number, to: number): number {
  let delta = to - from
  if (delta > 180) { delta -= 360 }
  if (delta < -180) { delta += 360 }
  return delta
}

// Heading from magnetic north with tilt compensation. GRAVITY supplies the
// physical up axis and the horizontal component of the magnetic field supplies
// magnetic north, so this remains meaningful while the tablet is tilted toward
// the horizon. Moved verbatim from the host (plan §14.3 track A2-2); the four
// device vectors are passed in explicitly because they stay reserved host
// fields (review §2.7.1).
export function gyroMagneticHeadingFromDeviceVectors(gravityDevice: number[], magneticDevice: number[], filteredGravityDevice: number[], filteredMagneticDevice: number[]): number {
  if (gravityDevice.length !== 3 || magneticDevice.length !== 3) {
    return Number.NaN
  }
  const gravity = filteredGravityDevice.length === 3
    ? filteredGravityDevice : gravityDevice
  const magneticField = filteredMagneticDevice.length === 3
    ? filteredMagneticDevice : magneticDevice
  const up = gyroNormalizeVector(gravity)
  const magnetic = gyroNormalizeVector(magneticField)
  const northRaw = [
    magnetic[0] - up[0] * gyroDot(magnetic, up),
    magnetic[1] - up[1] * gyroDot(magnetic, up),
    magnetic[2] - up[2] * gyroDot(magnetic, up)
  ]
  const northLength = Math.sqrt(gyroDot(northRaw, northRaw))
  if (northLength < 0.12) { return Number.NaN }
  const north = [northRaw[0] / northLength, northRaw[1] / northLength, northRaw[2] / northLength]
  const east = gyroNormalizeVector(gyroCross(north, up))
  // The observer looks through the rear side of the display.
  const rearNormal = [0, 0, -1]
  const eastComponent = gyroDot(rearNormal, east)
  const northComponent = gyroDot(rearNormal, north)
  return wrapGyroAzimuth(Math.atan2(eastComponent, northComponent) * 180 / Math.PI)
}
