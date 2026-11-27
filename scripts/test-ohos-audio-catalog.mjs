#!/usr/bin/env node
import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'

const repoRoot = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..')
const catalogPath = path.join(repoRoot, 'harmonyos/ets-source/capability/AudioCatalog.ets')
const enginePath = path.join(repoRoot, 'harmonyos/ets-source/capability/AudioEngine.ets')
const storePath = path.join(repoRoot, 'harmonyos/ets-source/state/AudioStore.ets')
const panelPath = path.join(repoRoot, 'harmonyos/ets-source/panels/panels/AudioPanel.ets')
const repoPath = path.join(repoRoot, 'harmonyos/ets-source/state/SettingsRepository.ets')

const catalogSrc = fs.readFileSync(catalogPath, 'utf8')
const engineSrc = fs.readFileSync(enginePath, 'utf8')
const storeSrc = fs.readFileSync(storePath, 'utf8')
const panelSrc = fs.readFileSync(panelPath, 'utf8')
const settingsSrc = fs.readFileSync(repoPath, 'utf8')

// 1. Verify AudioCatalog contract & dBFS / semantic categories
assert.match(catalogSrc, /export function dbToLinear\(/, 'AudioCatalog must export dbToLinear')
assert.match(catalogSrc, /export function resolveCelestialAudioCue\(/, 'AudioCatalog must export resolveCelestialAudioCue')
assert.match(catalogSrc, /export function resolveBandAudioCue\(/, 'AudioCatalog must export resolveBandAudioCue')
assert.match(catalogSrc, /export function getUiAudioCueSpec\(/, 'AudioCatalog must export getUiAudioCueSpec')
assert.match(catalogSrc, /station_tiangong/, 'AudioCatalog must include dedicated Tiangong station cue')
assert.match(catalogSrc, /station_iss/, 'AudioCatalog must include dedicated ISS station cue')
assert.match(catalogSrc, /nextConstellationSlot\(15\)/, 'AudioCatalog must rotate 15 constellation slots')
assert.match(catalogSrc, /nextSatelliteSlot\(3\)/, 'AudioCatalog must rotate 3 satellite slots')

// 2. Verify AudioEngine HarmonyOS native architecture (AVPlayer ping-pong, SFX pool, SoundPool, AudioSessionManager, stereo fallback)
assert.match(engineSrc, /import \{ media \} from '@kit\.MediaKit'/, 'AudioEngine must import @kit.MediaKit')
assert.match(engineSrc, /getSessionManager\(\)/, 'AudioEngine must govern AudioSessionManager')
assert.match(engineSrc, /CONCURRENCY_MIX_WITH_OTHERS/, 'AudioEngine must support mix-with-others when only SFX is active')
assert.match(engineSrc, /audioSessionDeactivated/, 'AudioEngine must handle system audio session deactivation')
assert.match(engineSrc, /createAVPlayer\(\)/, 'AudioEngine must use AVPlayer for ambient & celestial stems')
assert.match(engineSrc, /createSoundPool\(/, 'AudioEngine must use SoundPool for low-latency UI micro-SFX')
assert.match(engineSrc, /AudioChannel\.CHANNEL_2/, 'AudioEngine fallback must be stereo CHANNEL_2')
assert.match(engineSrc, /FALLBACK_IDLE_RELEASE_SAMPLES/, 'AudioEngine fallback must auto-release when idle')
assert.doesNotMatch(engineSrc, /Sky\s*Guide/i, 'AudioEngine must not reference third-party app names')

// 3. Verify AudioStore / SettingsRepository / AudioPanel independent SFX wiring
assert.match(storeSrc, /sfxEnabled:\s*boolean\s*=\s*true/, 'AudioStore must track sfxEnabled')
assert.match(storeSrc, /setSfxEnabled\(/, 'AudioStore must expose setSfxEnabled')
assert.match(settingsSrc, /sfxEnabled:\s*boolean/, 'SettingsRepository must persist sfxEnabled')
assert.match(settingsSrc, /audioVolume:\s*number/, 'SettingsRepository must persist audioVolume')
assert.match(panelSrc, /I18n\.t\('audio_sfx_toggle'\)/, 'AudioPanel must expose independent SFX toggle')

console.log('Audio framework static & architectural checks PASSED.')
