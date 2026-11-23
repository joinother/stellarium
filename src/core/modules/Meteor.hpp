/*
 * Stellarium
 * Copyright (C) 2014-2015 Marcos Cardinot
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

#ifndef METEOR_HPP
#define METEOR_HPP

#include "StelTextureTypes.hpp"
#include "VecMath.hpp"

#include <QList>
#include <QPair>

class StelCore;
class StelPainter;

//! @class Meteor 
//! Models a single meteor.
//! Once created, a meteor object only lasts for some amount of time,
//! and then "dies", after which, the update() member returns false.
//! @author Marcos Cardinot <mcardinot@gmail.com>
class Meteor
{
public:
	//! <colorName, intensity>
	typedef QPair<QString, int> ColorPair;

	//! Create a Meteor object.
	Meteor(const StelCore* core, const StelTextureSP &bolideTexture);
	virtual ~Meteor();

	//! Initialize meteor
	void init(const float& radiantAlpha, const float& radiantDelta,
		  const float& speed, const QList<ColorPair> colors);

	//! Initialize a preview meteor whose 3D AltAz trajectory crosses near centerAltAz.
	void initInViewport(const Vec3d& centerAltAz, float offsetRightRad, float offsetUpRad,
			    float slopeAngleRad, float speed, const QList<ColorPair>& colors,
			    bool isFireball, float startDelaySec = 0.f);

	//! Updates the position of the meteor, and expires it if necessary.
	//! @param deltaTime the time increment in seconds since the last call.
	//! @return true of the meteor is still alive, else false.
	virtual bool update(double deltaTime);
	
	//! Draws the meteor.
	virtual void draw(const StelCore* core, StelPainter& sPainter);

	//! Indicate if the meteor still visible.
	bool isAlive() const { return m_alive; }
	bool isPreviewBypassDaylight() const { return m_bypassDaylight; }
	QString getRejectionReason() const { return m_rejectionReason; }
	//! Set meteor absolute magnitude.
	void setAbsMag(float mag) { m_absMag = mag; }
	//! Get meteor absolute magnitude.
	float absMag() const { return m_absMag; }

private:
	void initLegacy(const float& radiantAlpha, const float& radiantDelta,
			const float& speed, const QList<ColorPair> colors);
	bool updateLegacy(double deltaTime);
	void drawLegacy(const StelCore* core, StelPainter& sPainter);
	void buildColorVectorsLegacy(const QList<ColorPair> colors);
	static Vec4f getColorFromNameLegacy(QString colorName);
	static void calculateThicknessLegacy(const StelCore* core, double& thickness, double& bolideSize);
	void drawBolideLegacy(StelPainter& sPainter, const double& bolideSize);
	void drawTrainLegacy(StelPainter& sPainter, const double& thickness);

	//! Determine color vectors of outer halo, spectral sheath and incandescent core.
	void buildColorVectors(const QList<ColorPair> colors);

	//! Configure physical morphology (width class, terminal flare, ionization afterglow).
	void configureMorphology(bool forceFireball, float speedKmS, const QList<ColorPair>& colors);

	//! get RGB from color name
	static Vec4f getColorFromName(QString colorName);

	//! Calculates angular base radius (in radians) and bolide angular size.
	static void calculateThickness(const StelCore* core, const StelPainter& sPainter,
				       double &angularHalfWidth, double &bolideAngularSize);

	//! Draws the meteor bolide (camera-facing spectral coma + white-hot core).
	void drawBolide(StelPainter &sPainter, const Vec3d& headDir, const Vec3d& tangentDir,
			const double &bolideAngularSize, float headIntensity);

	//! Draws the meteor train (camera-facing tapered multi-layer additive ribbons).
	void drawTrain(const StelCore* core, StelPainter& sPainter, const double &angularHalfWidth,
		       Vec3d& outHeadDir, Vec3d& outHeadTangent);

	//! Calculates the z-component of a meteor as a function of meteor zenith angle
	static float meteorZ(float zenithAngle, float altitude);

	//! find meteor position in horizontal coordinate system
	Vec3d radiantToAltAz(Vec3d position);

	//! find meteor position in radiant coordinate system
	Vec3d altAzToRadiant(Vec3d position);

	const StelCore* m_core;         //! The associated StelCore instance.

	bool m_alive;                   //! Indicates if the meteor it still visible.
	bool m_bypassDaylight;          //! Preview meteors animate regardless of daylight or pause.
	QString m_rejectionReason;
	double m_speed;                  //! Velocity of meteor in km/s.
	Mat4d m_matAltAzToRadiant;      //! Rotation matrix to convert from horizontal to radiant coordinate system.
	Vec3d m_position;               //! Meteor position in radiant coordinate system.
	Vec3d m_posTrain;               //! End of train in radiant coordinate system.
	float m_initialZ;               //! Initial z-component of the meteor in radiant coordinates.
	float m_finalZ;                 //! Final z-compoenent of the meteor in radiant coordinates.
	float m_minDist;                //! Shortest distance between meteor and observer.
	float m_absMag;                 //! Absolute magnitude [0, 1]
	float m_aptMag;                 //! Apparent magnitude [0, 1]
	float m_peakAbsMag;             //! Initial/peak absolute magnitude for fade ratios
	float m_startDelay;             //! Optional stagger delay before entering burn (seconds)
	float m_trainSeconds;           //! Wake persistence window in seconds (0.35..0.85)
	float m_widthScale;             //! Morphology width multiplier (needle 0.65 .. fireball 1.85)
	bool m_hasTerminalFlare;        //! Whether meteor exhibits a late-stage ablation flare
	float m_flarePos;               //! Normalized longitudinal position of flare [0.68, 0.90]
	float m_flareStrength;          //! Extra brightness/width boost at flare peak
	bool m_hasAfterglow;            //! Whether bright meteor leaves an O I / Mg ionization afterglow
	float m_afterglowRemaining;     //! Remaining afterglow seconds after head extinguishes
	float m_afterglowDuration;      //! Total afterglow seconds
	bool m_headExtinguished;        //! True once meteor passes m_finalZ
	float m_headFade;               //! Rapid head fade factor [1 -> 0] after m_finalZ
	Vec3f m_headTintColor;          //! Spectral tint for bolide coma
	Vec3f m_afterglowColor;         //! Spectral tint for persistent ionization train

	StelTextureSP m_bolideTexture;  //! Meteor bolide texture
	int m_segments;                 //! Number of segments along the train (10 classic / 24 vivid)
	QVector<Vec4f> m_outerColorVector;  //! Smooth saturated spectral halo color per segment
	QVector<Vec4f> m_coreColorVector;   //! Smooth hot incandescent core color per segment
	QVector<Vec4f> m_trainColorVector;  //! Scratch buffer (2 * m_segments) for ribbon vertices
	QVector<Vec4f> m_lineColorVector;   //! Scratch buffer (m_segments) for crisp spine highlight
};

#endif // METEOR_HPP
