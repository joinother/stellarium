/*
 * Stellarium
 * Copyright (C) 2015 Marcos Cardinot
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Suite 500, Boston, MA  02110-1335, USA.
 */

#include "SporadicMeteor.hpp"
#include "StelCore.hpp"
#include "StelUtils.hpp"
#include "StelApp.hpp"

SporadicMeteor::SporadicMeteor(const StelCore* core, const float& maxVel, const StelTextureSP& bolideTexture)
	: Meteor(core, bolideTexture)
{
	// meteor velocity [11, maxVel] km/s
	const bool vivid = StelApp::getInstance().getFlagVividRendering();
	// In vivid mode, keep shallow earth-grazing fireballs genuinely rare (~4% instead of 24%)
	// so the night sky stays natural and never spams screen-spanning streaks.
	const bool longSkySweeper = vivid && (StelApp::getInstance().getRandF() < 0.04f);
	float speed = longSkySweeper
		? (32.f + qMax(1.f, qMin(maxVel, 58.f) - 32.f) * static_cast<float>(StelApp::getInstance().getRandF()))
		: (11.f + (maxVel - 11.f) * static_cast<float>(StelApp::getInstance().getRandF()));

	// select a random radiant in a visible area
	double rAlt = longSkySweeper
		? (0.045 + 0.095 * static_cast<double>(StelApp::getInstance().getRandF())) // [2.6°, 8.0°] rare shallow grazer
		: (M_PI_2 * static_cast<double>(StelApp::getInstance().getRandF()));       // [0°, 90°]
	double rAz = 2 * M_PI * static_cast<double>(StelApp::getInstance().getRandF());  // [0, 2pi]
	Vec3d pos;
	StelUtils::spheToRect(rAz, rAlt, pos);

	// convert to J2000
	float rAlpha, rDelta;
	pos = core->altAzToJ2000(pos);
	StelUtils::rectToSphe(&rAlpha, &rDelta, pos);

	// initialize the meteor model with velocity-correlated physical spectroscopy
	init(rAlpha, rDelta, speed, getRandColor(speed));
}

SporadicMeteor::SporadicMeteor(const StelCore* core, const Vec3d& centerAltAz,
			       float offsetRightRad, float offsetUpRad, float slopeAngleRad,
			       float speed, const QList<ColorPair>& colors,
			       const StelTextureSP& bolideTexture, bool isFireball, float startDelaySec,
			       Meteor::Archetype forcedArchetype)
	: Meteor(core, bolideTexture)
{
	initInViewport(centerAltAz, offsetRightRad, offsetUpRad, slopeAngleRad,
		       speed, colors, isFireball, startDelaySec, forcedArchetype);
}

SporadicMeteor::~SporadicMeteor()
{
}

QList<Meteor::ColorPair> SporadicMeteor::getRandColor(float speedKmS)
{
	QList<ColorPair> colors;
	const float prob = StelApp::getInstance().getRandF();
	if (!StelApp::getInstance().getFlagVividRendering())
	{
		if (prob > 0.9f)
		{
			colors.push_back(Meteor::ColorPair("white", 70));
			colors.push_back(Meteor::ColorPair("orangeYellow", 10));
			colors.push_back(Meteor::ColorPair("yellow", 10));
			colors.push_back(Meteor::ColorPair("blueGreen", 10));
		}
		else if (prob > 0.85f)
		{
			colors.push_back(Meteor::ColorPair("white", 80));
			colors.push_back(Meteor::ColorPair("violet", 20));
		}
		else if (prob > 0.80f)
		{
			colors.push_back(Meteor::ColorPair("white", 80));
			colors.push_back(Meteor::ColorPair("orangeYellow", 20));
		}
		else
		{
			colors.push_back(Meteor::ColorPair("white", 100));
		}
		return colors;
	}

	const bool fast = speedKmS >= 46.f;

	// Realistic naked-eye multi-spectral emission distribution:
	//   Most sporadic meteors appear crisp silver-white or warm pale-gold;
	//   only a modest subset of faster/brighter meteors display subtle Mg/O emerald-cyan or Na amber tints.
	if (fast)
	{
		if (prob < 0.48f)
		{
			// Crisp silver-white / pale ice-blue needle (most common)
			colors.push_back(Meteor::ColorPair("iceBlue", 24));
			colors.push_back(Meteor::ColorPair("white", 76));
		}
		else if (prob < 0.68f)
		{
			// Warm golden-white streak
			colors.push_back(Meteor::ColorPair("paleGold", 35));
			colors.push_back(Meteor::ColorPair("white", 65));
		}
		else if (prob < 0.86f)
		{
			// Authentic Perseid-type high-velocity spectroscopy:
			// fine O I green entry -> warm N2/Na rose-gold -> Mg emerald/white burst -> faint Ca II lilac tip
			colors.push_back(Meteor::ColorPair("oGreen", 32));
			colors.push_back(Meteor::ColorPair("roseGold", 28));
			colors.push_back(Meteor::ColorPair("emerald", 28));
			colors.push_back(Meteor::ColorPair("lilacTip", 12));
		}
		else if (prob < 0.94f)
		{
			// Subtle emerald-cyan Mg/O -> incandescent white needle
			colors.push_back(Meteor::ColorPair("oGreen", 30));
			colors.push_back(Meteor::ColorPair("cyanGreen", 32));
			colors.push_back(Meteor::ColorPair("white", 38));
		}
		else
		{
			// Calcium violet / ice-blue streak
			colors.push_back(Meteor::ColorPair("violet", 24));
			colors.push_back(Meteor::ColorPair("iceBlue", 38));
			colors.push_back(Meteor::ColorPair("white", 38));
		}
	}
	else
	{
		if (prob < 0.50f)
		{
			// Crisp silver-white / faint warm-white needle
			colors.push_back(Meteor::ColorPair("paleGold", 20));
			colors.push_back(Meteor::ColorPair("white", 80));
		}
		else if (prob < 0.78f)
		{
			// Warm sodium amber-gold streak
			colors.push_back(Meteor::ColorPair("amberGold", 38));
			colors.push_back(Meteor::ColorPair("paleGold", 34));
			colors.push_back(Meteor::ColorPair("white", 28));
		}
		else if (prob < 0.90f)
		{
			// Subtle emerald-cyan Mg/O streak
			colors.push_back(Meteor::ColorPair("emerald", 30));
			colors.push_back(Meteor::ColorPair("cyanGreen", 30));
			colors.push_back(Meteor::ColorPair("white", 40));
		}
		else
		{
			// Soft ice-blue / violet streak
			colors.push_back(Meteor::ColorPair("iceBlue", 42));
			colors.push_back(Meteor::ColorPair("violet", 18));
			colors.push_back(Meteor::ColorPair("white", 40));
		}
	}

	return colors;
}
