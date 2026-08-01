# Gyroscope Pose Audit

Last audited: 2026-08-01

## Purpose

This is an implementation audit, not a claim that real-device orientation is
correct. It records the active path before further changes so that sensor-axis
experiments cannot silently replace one another.

## Active Path Today

```text
ROTATION_VECTOR callback
  -> onRotationVectorDirect()
  -> gravity + magnetic-field forward vector, if both are available
  -> rotation-vector forward vector only as fallback
  -> exponential filter of forward direction
  -> setGyroView(azimuth, altitude) about 30 times/sec
  -> C++ creates a target direction, then reconstructs "up" from world zenith
```

Relevant code:

- `harmonyos/ets-source/pages/MainWindowNativeNode.ets`
  - subscription: `startGyroscope()`
  - active callback: `onRotationVectorDirect()`
  - gravity/magnetic basis: `gyroForwardFromGravityAndMagnetic()`
- `src/StelMainView.cpp`
  - command queue coalescing: `runOhosCommandOnQtThread()`
  - native application: `setGyroView`

## What Is Conflicting

1. `onRotationVectorData()` contains an anchored full-pose implementation
   (`forward + up`), but it is not the callback registered by
   `startGyroscope()`. It is diagnostic/legacy code today.
2. The active ArkTS path passes only azimuth and altitude to C++. Although the
   bridge accepts optional `upX|upY|upZ`, C++ currently ignores those values.
3. C++ reconstructs `up` from the local zenith and a transported previous
   vector. This keeps ordinary horizons upright but cannot preserve the
   tablet's screen roll and becomes ill-conditioned near zenith/nadir.
4. Rotation-vector, gravity, and magnetic-field subscriptions all run at once,
   but there is no explicit display/window-rotation transform between device
   coordinates and the visible screen coordinate system.

These facts explain the observed behavior: a stable-looking horizon in some
poses, but incorrect roll, disagreement with the physical compass, and
instability while passing poles. They also explain why isolated sign changes
can appear to fix one pose while breaking another.

## Target Design

Use one authoritative sensor pose at a time:

1. Use `ROTATION_VECTOR` as the primary orientation source.
2. Use gravity + magnetic field only when the rotation-vector sensor is
   unavailable, not as a competing primary source.
3. Apply display/window rotation once in a dedicated device-to-screen mapping.
4. Turn the quaternion into an orthonormal rigid camera pose:
   - `forward`: direction through the rear of the display
   - `screenUp`: top edge of the displayed application
5. Smooth that one rigid pose (quaternion/Slerp or equivalent), not two
   independently rebuilt vectors.
6. Pass both vectors through the bridge and have C++ preserve the supplied
   `screenUp` after orthonormalization.
7. Apply magnetic declination, if added, once as a world-frame correction;
   never as a per-sample axis tweak.

The existing latest-value queue and 33ms dispatch limit should remain. They
prevent sensor samples from accumulating on the render thread.

## Required Tablet Validation

Every candidate must be tested with a fixed observation location and the same
display orientation:

- [ ] Tablet flat on a table: view reaches nadir without a sideways roll.
- [ ] Tablet raised vertically: horizon remains horizontal.
- [ ] Tablet facing the sky: view reaches zenith without a flip.
- [ ] Cross horizon in both directions: no lateral jump.
- [ ] Rotate about the screen normal while vertical: scene roll changes in the
      corresponding direction.
- [ ] Turn around the vertical axis: heading responds continuously and in the
      correct direction.
- [ ] Compare cardinal directions against an external calibrated compass.
- [ ] Enable gyro from an arbitrary view: one visible handoff only, then no
      competing object tracking.
- [ ] Search/select during gyro mode: target guide moves, camera does not
      snap away from the physical pose.

## Implementation Order

1. Add read-only logging of rotation-vector quaternion, display rotation, and
   derived `forward + screenUp` for the validation poses above.
2. Confirm the sensor coordinate convention on the actual tablet from those
   logs.
3. Replace the active gravity/magnetic-primary callback with the confirmed
   rotation-vector full-pose path.
4. Change native `setGyroView` to consume and preserve `screenUp`.
5. Build, install, test every checklist case, then make one focused commit.

Do not change signs, reorder axes, or add calibration offsets before step 2.
