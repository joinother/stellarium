/*
 * Stellarium / Sky Instrument — Rocket Launch Trajectory & Twilight Plume Module
 *
 * Provides:
 *  - 3-DOF rotating WGS-84 + J2 + US76 atmosphere multi-stage ascent simulator
 *  - Independent ballistic re-entry impact prediction for boosters, fairings & core stages
 *  - ICAO NOTAM danger-zone polygon / Q-line circle parser, launch azimuth inversion & dispersion
 *  - 6-propellant rocket twilight plume (jellyfish / solid wind-sheared ribbon / hybrid)
 *    physical visibility & scoring model with Earth-shadow tangent altitude & horizon occlusion
 *  - OpenGL ES 3D sky trajectory & live plume preview hook (Phase 3 draw integration)
 */

#ifndef ROCKETLAUNCHMGR_HPP
#define ROCKETLAUNCHMGR_HPP

#include "StelModule.hpp"

#include <QJsonArray>
#include <QJsonObject>
#include <QString>
#include <QVector>

class StelCore;
class StelPainter;

struct RocketLaunchSite
{
	QString id;
	QString nameZh;
	QString nameEn;
	QString code;
	QString country;
	double latDeg = 0.0;
	double lonDeg = 0.0;
	double altM = 0.0;
	double defaultAzimuthDeg = 90.0;
	bool isSeaLaunch = false;
};

struct RocketStageSpec
{
	QString nameZh;
	QString nameEn;
	QString propellant; // solid | kerolox | methalox | hydrolox | hypergolic
	double dryMassKg = 0.0;
	double propMassKg = 0.0;
	double thrustSLN = 0.0;
	double thrustVacN = 0.0;
	double burnTimeSec = 0.0;
	double refAreaM2 = 10.0;
	double debrisCd = 1.1;
};

struct RocketVehicleSpec
{
	QString id;
	QString nameZh;
	QString nameEn;
	QString family;
	QString propellantClass; // solid | kerolox | methalox | hydrolox | hypergolic | hybrid_solid_liquid
	QString plumeTypeZh;
	QString plumeTypeEn;
	QString summaryZh;
	QString summaryEn;
	double payloadMassKg = 1000.0;
	double fairingMassKg = 800.0;
	double fairingSepSec = 200.0;
	double fairingAreaM2 = 12.0;
	double kickStartSec = 10.0;
	double kickDurationSec = 12.0;
	double kickAngleDeg = 4.5;
	double stage2TargetPitchDeg = 6.0;
	bool hasBoosters = false;
	int boosterCount = 0;
	RocketStageSpec booster;
	RocketStageSpec stage1;
	RocketStageSpec stage2;
	bool hasStage3 = false;
	RocketStageSpec stage3;
};

struct RocketLaunchPreset
{
	QString id;
	QString titleZh;
	QString titleEn;
	QString badgeZh;
	QString badgeEn;
	QString siteId;
	QString vehicleId;
	QString launchTimeUtc; // ISO-8601 UTC e.g. 2026-10-23T10:15:00Z
	double azimuthDeg = 90.0;
	double kickAngleDeg = -1.0; // < 0 uses vehicle default
	QString targetOrbit;
	QString descriptionZh;
	QString descriptionEn;
	QString sampleNotam;
};

struct RocketNotamZone
{
	bool valid = false;
	QString notamId;
	QString validFromUtc;
	QString validToUtc;
	bool hasCircle = false;
	double circleLatDeg = 0.0;
	double circleLonDeg = 0.0;
	double circleRadiusKm = 0.0;
	QVector<QPair<double, double>> polygonLatLon; // (latDeg, lonDeg)
	double centerLatDeg = 0.0;
	double centerLonDeg = 0.0;
	double invertedAzimuthDeg = -1.0;
	double downrangeKm = 0.0;
};

struct RocketTrajectorySample
{
	double tSec = 0.0;
	int phaseIndex = 0; // 0=booster+core, 1=core, 2=stage2, 3=stage3, 4=coast
	QString activePropellant;
	double latDeg = 0.0;
	double lonDeg = 0.0;
	double altKm = 0.0;
	double speedKmS = 0.0;
	double downrangeKm = 0.0;
	double dynamicPressureKPa = 0.0;
	double accelG = 0.0;
	// Observer-relative geometry
	double azDeg = 0.0;
	double altDeg = -90.0;
	double rangeKm = 0.0;
	double horizonAltDeg = 0.0;
	bool aboveHorizon = false;
	// Plume & solar illumination physics
	double shadowTangentAltKm = -999.0; // h_eff: <=0 umbra, 0..25 red_twilight, >25 sunlit
	QString sunlitState;                // umbra | red_twilight | sunlit | daylit
	double plumeWidthKm = 0.0;
	double plumeAngularDeg = 0.0;
	double plumeBrightness = 0.0;       // 0..1
	double plumeR = 1.0;
	double plumeG = 1.0;
	double plumeB = 1.0;
	bool plumeVisible = false;
	double windDriftEastKm = 0.0;       // accumulated wind-shear drift proxy for solid trails
	double windDriftNorthKm = 0.0;
};

struct RocketFlightEvent
{
	QString code; // LIFTOFF | MAX_Q | BOOSTER_CUTOFF | BOOSTER_SEP | FAIRING_SEP | MECO | STAGE_SEP | SECO | SUNLIT_ENTRY | FIRST_VISIBLE | MAX_ALT | LOST_VISIBLE
	QString labelZh;
	QString labelEn;
	double tSec = 0.0;
	double latDeg = 0.0;
	double lonDeg = 0.0;
	double altKm = 0.0;
	double speedKmS = 0.0;
	double azDeg = 0.0;
	double altDeg = -90.0;
	double rangeKm = 0.0;
};

struct RocketDebrisTrack
{
	QString kind; // booster | fairing | stage1
	QString labelZh;
	QString labelEn;
	double sepTimeSec = 0.0;
	double impactTimeSec = 0.0;
	QString impactTimeUtc;
	double impactLatDeg = 0.0;
	double impactLonDeg = 0.0;
	double downrangeKm = 0.0;
	double maxAltKm = 0.0;
	bool insideNotam = false;
	double distanceToNotamKm = -1.0;
	QVector<QVector<double>> arcPoints; // [tSec, latDeg, lonDeg, altKm]
};

struct RocketDispersionPoint
{
	double latDeg = 0.0;
	double lonDeg = 0.0;
	bool insideNotam = false;
};

struct RocketSimulationResult
{
	bool ok = false;
	QString error;
	QString simulationId;
	QString titleZh;
	QString titleEn;
	QString launchTimeUtc;
	double launchJd = 0.0;
	double timeOffsetMin = 0.0;
	double launchAzimuthDeg = 90.0;
	double computeMs = 0.0;
	RocketLaunchSite site;
	RocketVehicleSpec vehicle;
	RocketNotamZone notam;

	double observerLatDeg = 0.0;
	double observerLonDeg = 0.0;
	double observerAltM = 0.0;
	double observerSunAltDeg = 0.0;
	double observerSunAzDeg = 0.0;
	QString twilightStage; // daylight | civil | nautical | astronomical | night
	double distanceToPadKm = 0.0;

	// Summary visibility & plume prediction
	bool visibleFromObserver = false;
	double firstVisibleSec = -1.0;
	double lastVisibleSec = -1.0;
	double maxAltDeg = -90.0;
	double maxAltSec = -1.0;
	double maxAltAzDeg = 0.0;
	double sunlitEntrySec = -1.0;
	double sunlitEntryAltKm = -1.0;

	int plumeScore = 0;           // 0..100
	QString plumeGrade;           // excellent | good | fair | flame_only | invisible
	QString plumeGradeZh;
	QString plumeGradeEn;
	QString plumeAdviceZh;
	QString plumeAdviceEn;
	double plumeWindowStartSec = -1.0;
	double plumeWindowEndSec = -1.0;
	double peakPlumeSec = -1.0;
	double peakPlumeBrightness = 0.0;
	double peakPlumeAzDeg = 0.0;
	double peakPlumeAltDeg = 0.0;
	int recommendedFocalMm = 35;

	QVector<RocketTrajectorySample> trajectory;
	QVector<RocketFlightEvent> events;
	QVector<RocketDebrisTrack> debris;
	QVector<RocketDispersionPoint> dispersion;
	QVector<QPair<double, double>> horizonProfile; // (azDeg, horizonAltDeg)
};

class RocketLaunchMgr : public StelModule
{
	Q_OBJECT

public:
	RocketLaunchMgr();
	~RocketLaunchMgr() override;

	void init() override;
	void update(double deltaTime) override;
	void draw(StelCore* core) override;
	double getCallOrder(StelModuleActionName actionName) const override;

	//! Static catalog queries (also usable without active GL context for unit tests)
	static const QVector<RocketLaunchSite>& launchSites();
	static const QVector<RocketVehicleSpec>& vehicles();
	static const QVector<RocketLaunchPreset>& presets();
	static QJsonObject catalogToJson();

	//! Parse standard ICAO NOTAM text (Q-line circle + E-line polygon + B/C timestamps)
	static RocketNotamZone parseNotamText(const QString& text, double padLatDeg = 0.0, double padLonDeg = 0.0, bool hasPad = false);

	//! Core 3-DOF trajectory + debris + twilight rocket plume simulation
	static RocketSimulationResult simulate(
		const QJsonObject& request,
		double observerLatDeg,
		double observerLonDeg,
		double observerAltM,
		const std::function<double(double)>& horizonLookupDeg = nullptr);

	static QJsonObject simulationToJson(const RocketSimulationResult& sim, bool includeFullTrack = true);

	//! Live sky preview state (used by Phase 3 OpenGL rendering)
	void setActivePreview(const RocketSimulationResult& sim, double playbackTimeSec = 0.0, bool playing = false, double speed = 1.0);
	void clearActivePreview();
	bool hasActivePreview() const { return previewActive; }
	void setPreviewPlayback(double playbackTimeSec, bool playing, double speed);
	void setPreviewFramingFocalMm(int focalMm);
	QJsonObject getPreviewStateJson() const;

private:
	bool previewActive = false;
	bool previewPlaying = false;
	double previewTimeSec = 0.0;
	double previewSpeed = 1.0;
	int previewFocalMm = 0; // 0 = off
	RocketSimulationResult activePreview;
};

#endif // ROCKETLAUNCHMGR_HPP
