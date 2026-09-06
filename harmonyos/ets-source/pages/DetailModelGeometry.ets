export function modelIdentity(): number[] {
  return [1, 0, 0, 0, 1, 0, 0, 0, 1]
}

export function modelMultiply(left: number[], right: number[]): number[] {
  const result: number[] = []
  for (let row = 0; row < 3; row++) {
    for (let column = 0; column < 3; column++) {
      result.push(left[row * 3] * right[column] + left[row * 3 + 1] * right[column + 3] +
        left[row * 3 + 2] * right[column + 6])
    }
  }
  return result
}

export function modelDrag(rotation: number[], deltaX: number, deltaY: number): number[] {
  const yaw = deltaX * 0.008
  const pitch = deltaY * 0.008
  const yawRotation = [Math.cos(yaw), 0, -Math.sin(yaw), 0, 1, 0, Math.sin(yaw), 0, Math.cos(yaw)]
  const pitchRotation = [1, 0, 0, 0, Math.cos(pitch), Math.sin(pitch), 0, -Math.sin(pitch), Math.cos(pitch)]
  return modelMultiply(modelMultiply(rotation, yawRotation), pitchRotation)
}

export function modelVector(matrix: number[], vector: number[]): number[] {
  return [matrix[0] * vector[0] + matrix[1] * vector[1] + matrix[2] * vector[2],
    matrix[3] * vector[0] + matrix[4] * vector[1] + matrix[5] * vector[2],
    matrix[6] * vector[0] + matrix[7] * vector[1] + matrix[8] * vector[2]]
}
