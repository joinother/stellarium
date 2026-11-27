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

	//! Physical archetype for realistic meteor diversity
	enum class Archetype
	{
		MicroNeedle = 0,           //! Razor-thin hairline streak (most common naked-eye meteor)
		SpectralStreak = 1,        //! Fast multi-spectral meteor (e.g. Perseid: green->rose->flare->lilac)
		AirburstBolide = 2,        //! Intense mid/late airburst with atmospheric scattering glare & optical halo ring
		FragmentingSuperbolide = 3 //! Slower warm-gold bolide that explodes & splits into glowing lead chunks + trailing sparks
	};

	//! Initialize a preview meteor whose 3D AltAz trajectory crosses near centerAltAz.
	void initInViewport(const Vec3d& centerAltAz, float offsetRightRad, float offsetUpRad,
			    float slopeAngleRad, float speed, const QList<ColorPair>& colors,
			    bool isFireball, float startDelaySec = 0.f,
			    Archetype forcedArchetype = Archetype::SpectralStreak);

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

	//! Configure physical morphology (width class, terminal flare, airburst glare, fragmentation, smoke train).
	void configureMorphology(bool forceFireball, float speedKmS, const QList<ColorPair>& colors, int forcedArchetype = -1);

	//! Draws intense atmospheric scattering glare & subtle optical halo ring during bright airbursts.
	void drawAirburstGlare(StelPainter& sPainter, const Vec3d& burstDir, float burstIntensity, const Vec3f& tintRgb);

	//! Spawns physical breakup fragments (lead chunks + trailing sparks) for FragmentingSuperbolide.
	void spawnBreakupFragments();

	//! Draws active glowing breakup fragments & trailing embers.
	void drawFragments(StelPainter& sPainter);

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

	//! Evaluates the meteor's exact analytical state (position, flare, glare, fragments, smoke) as a pure function of simulation Julian Day.
	bool evaluateAtSimTime(double currentJd);

	//! Captures 3D sky anchors for a persistent mesospheric wind-sheared smoke train.
	void captureSmokeTrainAnchors();

	//! Draws the slowly drifting, curling, diffusing persistent smoke/dust train after fireball ablation.
	void drawPersistentSmokeTrain(StelPainter& sPainter);

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
	double m_birthJd;               //! Simulation Julian Day when meteor was born
	double m_burnDurationSec;       //! Total luminous burn duration in simulation seconds
	double m_totalLifetimeSec;      //! Total lifetime including embers & smoke in simulation seconds
	double m_breakupTimeSec;        //! Simulation seconds after birth when superbolide fragments
	bool m_visibleAtSimTime;        //! True when current simulation time is inside [0, totalLifetime]
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
	Vec3f m_afterglowColor;         //! Spectral tint for persistent ionization/smoke train

	// Persistent wind-sheared mesospheric smoke train (bright meteors / fireballs)
	bool m_smokeCaptured;           //! True once smoke anchor points along the luminous path are recorded
	float m_smokeAgeSec;            //! Elapsed seconds since smoke train started drifting/diffusing
	float m_smokeDurationSec;       //! Total smoke persistence lifetime (seconds)
	float m_smokeWindFreq;          //! Spatial frequency of mesospheric wind shear waves along path
	float m_smokeWindPhase;         //! Random phase for S-curve shear
	float m_smokeWindPhase2;        //! Secondary eddy phase for organic curling hooks
	float m_smokeDriftRate;         //! Base angular drift rate (rad/sec)
	Vec3d m_smokeShearAxis1;        //! Primary unit wind-shear axis on celestial sphere
	Vec3d m_smokeShearAxis2;        //! Secondary orthogonal axis for subtle 3D eddy curl
	QVector<Vec3d> m_smokeAnchors;  //! Unit AltAz sky vectors recorded along ablation path
	QVector<float> m_smokeWeights;  //! Per-anchor dust density weight (peaking at ablation flare)
	QVector<float> m_smokeU;        //! Normalized longitudinal coordinate [0..1] per anchor

	Archetype m_archetype;          //! Physical meteor archetype
	int m_lightCurveMode;           //! 0=GradualSwell, 1=SlowBuildToDazzlingPeak, 2=PulsingBreakupSurge
	int m_glareStyle;               //! 0=PureHaze, 1=AsymCross4, 2=AnamorphicStreak, 3=OrganicScatterRays, 4=Aperture6or8
	unsigned int m_glareSeed;       //! Per-meteor seed for unique ray angles/lengths/widths
	float m_glareAngleOffset;       //! Random diffraction spike orientation angle (radians)
	float m_burstProgress;          //! Normalized burn progress [0..1] when peak brightness/breakup occurs
	float m_burstFlash;             //! Smoothly filtered instantaneous glare intensity [0..1.2]
	float m_burstPeakMag;           //! Peak glare strength for bright bolides & superbolides
	float m_burnTimeSec;            //! Elapsed active burn seconds (for subtle ablation flicker)
	Vec3d m_burstAltAzDir;          //! Live moving unit AltAz direction of the dazzling fireball head
	bool m_burstTriggered;          //! True once breakup fragmentation has triggered

	struct BreakupFragment
	{
		Vec3d originPosRad;     //! Initial breakup position in radiant frame (km)
		Vec3d initVelRad;       //! Initial breakup velocity in radiant frame (km/s)
		Vec3d posRad;           //! Evaluated position at current sim time (km)
		Vec3d prevPosRad;       //! Evaluated short wake tail at current sim time (km)
		float dragRate;         //! Deceleration rate (1/s) — smaller sparks slow down faster
		float sizePx;           //! Base screen radius scale
		float brightness;       //! Initial brightness multiplier
		float ageSec;           //! Evaluated elapsed seconds since breakup
		float lifeSec;          //! Total luminous ember lifetime
		bool isLeadChunk;       //! True for major glowing companion chunk; false for trailing spark
	};
	QVector<BreakupFragment> m_fragments;

	StelTextureSP m_bolideTexture;  //! Meteor bolide texture
	int m_segments;                 //! Number of segments along the train (10 classic / 24 vivid)
	QVector<Vec4f> m_outerColorVector;  //! Smooth saturated spectral halo color per segment
	QVector<Vec4f> m_coreColorVector;   //! Smooth hot incandescent core color per segment
	QVector<Vec4f> m_trainColorVector;  //! Scratch buffer (2 * m_segments) for ribbon vertices
	QVector<Vec4f> m_lineColorVector;   //! Scratch buffer (m_segments) for crisp spine highlight
};

#endif // METEOR_HPP
