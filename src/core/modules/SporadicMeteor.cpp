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
	float speed = 11.f + (maxVel - 11.f) * static_cast<float>(StelApp::getInstance().getRandF());

	// select a random radiant in a visible area
	double rAlt = M_PI_2  * static_cast<double>(StelApp::getInstance().getRandF());  // [0, pi/2]
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
			       const StelTextureSP& bolideTexture, bool isFireball, float startDelaySec)
	: Meteor(core, bolideTexture)
{
	initInViewport(centerAltAz, offsetRightRad, offsetUpRad, slopeAngleRad,
		       speed, colors, isFireball, startDelaySec);
}

SporadicMeteor::~SporadicMeteor()
{
}

QList<Meteor::ColorPair> SporadicMeteor::getRandColor(float speedKmS)
{
	QList<ColorPair> colors;
	const float prob = StelApp::getInstance().getRandF();
	const bool fast = speedKmS >= 46.f;

	// Velocity-correlated multi-spectral emission palettes:
	//   1. Emerald Magnesium / Forbidden Oxygen (signature vibrant green -> cyan -> white head)
	//   2. High-Speed Rose-Magenta -> Emerald -> Cyan-White (N2/O atmospheric wake + Mg plasma)
	//   3. Sodium Gold / Warm Amber (Na I 589 nm, enriched in slower meteoroids)
	//   4. Ice-Blue / Calcium Violet (Ca II H&K / Fe)
	//   5. Crisp Silver-White / Pale-Cyan Needle (abundant fine background micro-meteors)
	if (fast)
	{
		if (prob < 0.34f)
		{
			// Vivid emerald Mg/O streak
			colors.push_back(Meteor::ColorPair("emerald", 45));
			colors.push_back(Meteor::ColorPair("cyanGreen", 35));
			colors.push_back(Meteor::ColorPair("white", 20));
		}
		else if (prob < 0.56f)
		{
			// Multi-spectral high-velocity streak: rose-magenta tail -> emerald body -> cyan-white head
			colors.push_back(Meteor::ColorPair("roseMagenta", 22));
			colors.push_back(Meteor::ColorPair("emerald", 48));
			colors.push_back(Meteor::ColorPair("cyanGreen", 20));
			colors.push_back(Meteor::ColorPair("white", 10));
		}
		else if (prob < 0.72f)
		{
			// Calcium violet / ice-blue streak
			colors.push_back(Meteor::ColorPair("violet", 30));
			colors.push_back(Meteor::ColorPair("iceBlue", 45));
			colors.push_back(Meteor::ColorPair("white", 25));
		}
		else if (prob < 0.86f)
		{
			// Warm amber-gold sodium streak
			colors.push_back(Meteor::ColorPair("amberGold", 45));
			colors.push_back(Meteor::ColorPair("paleGold", 35));
			colors.push_back(Meteor::ColorPair("white", 20));
		}
		else
		{
			// Crisp silver-white / pale-cyan fine needle
			colors.push_back(Meteor::ColorPair("iceBlue", 35));
			colors.push_back(Meteor::ColorPair("white", 65));
		}
	}
	else
	{
		if (prob < 0.30f)
		{
			// Warm sodium amber-gold streak
			colors.push_back(Meteor::ColorPair("amberGold", 50));
			colors.push_back(Meteor::ColorPair("paleGold", 32));
			colors.push_back(Meteor::ColorPair("white", 18));
		}
		else if (prob < 0.56f)
		{
			// Emerald Mg/O streak
			colors.push_back(Meteor::ColorPair("emerald", 45));
			colors.push_back(Meteor::ColorPair("cyanGreen", 35));
			colors.push_back(Meteor::ColorPair("white", 20));
		}
		else if (prob < 0.70f)
		{
			// Rose-amber -> pale gold warm streak
			colors.push_back(Meteor::ColorPair("roseMagenta", 25));
			colors.push_back(Meteor::ColorPair("amberGold", 45));
			colors.push_back(Meteor::ColorPair("paleGold", 30));
		}
		else if (prob < 0.84f)
		{
			// Ice-blue / violet streak
			colors.push_back(Meteor::ColorPair("iceBlue", 50));
			colors.push_back(Meteor::ColorPair("violet", 25));
			colors.push_back(Meteor::ColorPair("white", 25));
		}
		else
		{
			// Crisp silver-white needle
			colors.push_back(Meteor::ColorPair("paleGold", 25));
			colors.push_back(Meteor::ColorPair("white", 75));
		}
	}

	return colors;
}
