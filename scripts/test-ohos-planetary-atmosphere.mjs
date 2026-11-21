import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = (rel) => fs.readFileSync(path.join(root, rel), 'utf8');

test('AtmospherePlanetary header defines profiles for solar system atmospheric worlds and safe GLSL', () => {
	const src = read('src/core/modules/AtmospherePlanetary.hpp');
	for (const id of ['"earth"', '"mars"', '"venus"', '"titan"', '"jupiter"', '"saturn"', '"uranus"', '"neptune"', '"pluto"', '"triton"']) {
		assert.match(src, new RegExp(id), `missing profile ${id}`);
	}
	assert.match(src, /vec3 planetaryAtmosphereColor\s*\(/);
	assert.match(src, /if\s*\(planetAtmoParams\.x\s*<=\s*0\.\)\s*return\s+original;/);
	assert.match(src, /horizonBase\s*>\s*0\.00001\s*\?\s*pow\(/, 'pow() base must guard against 0 on mobile GPUs');
});

test('AtmosphereLightweight wires planetary profile, luminance scaling, shader, and uniforms', () => {
	const hpp = read('src/core/modules/AtmosphereLightweight.hpp');
	const cpp = read('src/core/modules/AtmosphereLightweight.cpp');
	assert.match(hpp, /#include\s+"AtmospherePlanetary\.hpp"/);
	assert.match(hpp, /AtmospherePlanetary::Profile\s+planetaryProfile_/);
	assert.match(cpp, /AtmospherePlanetary::shaderSource\(\)/);
	assert.match(cpp, /planetaryAtmosphereColor\(color_RGB,\s*viewDir,\s*sunDir\)/);
	assert.match(cpp, /p\.relativeBrightness\s*=\s*noScatter\s*\?\s*0\.f\s*:\s*planetaryProfile_\.luminanceScale;/);
	assert.match(cpp, /planetaryProfileId\s*=\s*QString::fromLatin1\(planetaryProfile_\.id\);/);
	assert.match(cpp, /renderUniformLocations_\.planetAtmoParams/);
});

test('AtmospherePreetham wires planetary profile, cache invalidation, luminance scaling, and shader', () => {
	const hpp = read('src/core/modules/AtmospherePreetham.hpp');
	const cpp = read('src/core/modules/AtmospherePreetham.cpp');
	assert.match(hpp, /#include\s+"AtmospherePlanetary\.hpp"/);
	assert.match(hpp, /float\s+cachedPlanetaryLuminanceScale/);
	assert.match(cpp, /AtmospherePlanetary::shaderSource\(\)/);
	assert.match(cpp, /planetaryAtmosphereColor\(resultSkyColor,\s*skyColor\.xyz,\s*sunPos\)/);
	assert.match(cpp, /cachedPlanetaryLuminanceScale\s*==\s*planetaryProfile_\.luminanceScale/);
	assert.match(cpp, /lumi\s*\*=\s*eclipseFactor\s*\*\s*planetaryProfile_\.luminanceScale;/);
	assert.match(cpp, /shaderAttribLocations\.planetAtmoParams/);
});

test('LandscapeMgr and StelMainView expose atmosphereProfile without breaking Earth defaults', () => {
	const atmo = read('src/core/modules/Atmosphere.hpp');
	const lmgrH = read('src/core/modules/LandscapeMgr.hpp');
	const lmgrC = read('src/core/modules/LandscapeMgr.cpp');
	const view = read('src/StelMainView.cpp');
	assert.match(atmo, /QString\s+getPlanetaryProfileId\(\)\s+const/);
	assert.match(lmgrH, /QString\s+getAtmosphereProfile\(\)\s+const/);
	assert.match(lmgrC, /LandscapeMgr::getAtmosphereProfile\(\)\s+const/);
	assert.match(view, /result\["atmosphereProfile"\]\s*=\s*lmgr->getAtmosphereProfile\(\);/);
});
