/*
 * Stellarium
 * Copyright (C) 2026 Stellarium Developers
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1335, USA.
 */

#ifndef AURORARENDERER_HPP
#define AURORARENDERER_HPP

#include <memory>

class StelCore;
struct AuroraRendererResources;

//! High-performance 3D flowing silk-curtain atmospheric aurora renderer.
//! Builds animated 3D magnetic-field-aligned curtain ribbons suspended in the
//! upper atmosphere (100-360 km above a curved Earth), projects them through
//! Stellarium's active projection, and shades crisp vertical light pillars with
//! physical grazing-angle fold brightening and multi-altitude emission spectra.
//!
//! Four curated natural morphologies & emission palettes:
//!   0: Classic Arctic Silk Curtains (lime-emerald hem, vertical rays, violet crown)
//!   1: Crimson & Emerald Storm (lime-green hem erupting into soaring hot-magenta & crimson)
//!   2: Violet-Emerald Pillars (dense harp-string vertical rays, emerald base to electric purple)
//!   3: Sapphire-Green Polar Arc (serene mint-aqua ribbons rising into deep sapphire-blue)
class AuroraRenderer
{
public:
	static constexpr int kStyleCount = 4;

	AuroraRenderer();
	~AuroraRenderer();

	//! Advance smooth opacity transition and flowing silk animation clock.
	void update(double deltaTime, bool enabled, bool onEarth, double sunAltDeg, float zoomVisibility, int style);

	//! Render the animated 3D aurora silk curtains into the current sky viewport.
	void draw(StelCore* core);

	//! Current combined opacity in [0, 1] (user fade * solar depression gate * zoom fade).
	float effectiveOpacity() const { return fadeOpacity * solarGateValue * zoomOpacity; }

	//! Current solar depression darkness gate in [0, 1].
	float solarGate() const { return solarGateValue; }

	//! Current user toggle fade level in [0, 1].
	float userFade() const { return fadeOpacity; }

	//! Current active style index [0..3].
	int currentStyle() const { return activeStyle; }

	//! Release GL resources explicitly before context teardown if needed.
	void releaseGL();

	//! Pure smoothstep solar depression gate: 0 above -6 deg, 1 below -18 deg.
	static float computeSolarGate(double sunAltDeg);

private:
	void prepareResources();
	void buildProgram();

	float fadeOpacity = 0.f;
	float solarGateValue = 0.f;
	float zoomOpacity = 1.f;
	float animationTime = 0.f;
	int activeStyle = 0;
	std::unique_ptr<AuroraRendererResources> res;
};

#endif // AURORARENDERER_HPP
