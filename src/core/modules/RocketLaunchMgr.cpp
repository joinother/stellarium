/*
 * Stellarium / Sky Instrument — Rocket Launch Trajectory & Twilight Plume Module
 */

#include "RocketLaunchMgr.hpp"

#include "StelCore.hpp"

#include <QDateTime>
#include <QElapsedTimer>
#include <QRegularExpression>
#include <QTimeZone>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>

namespace
{
constexpr double kPi = 3.14159265358979323846;
constexpr double kDeg2Rad = kPi / 180.0;
constexpr double kRad2Deg = 180.0 / kPi;

// WGS-84 & Earth gravity constants
constexpr double kWgs84A = 6378137.0;
constexpr double kWgs84F = 1.0 / 298.257223563;
constexpr double kWgs84E2 = 2.0 * kWgs84F - kWgs84F * kWgs84F;
constexpr double kEarthMeanR = 6371008.8;
constexpr double kEarthMu = 3.986004418e14;
constexpr double kEarthJ2 = 1.08262668e-3;
constexpr double kEarthOmega = 7.2921150e-5;
constexpr double kG0 = 9.80665;
constexpr double kP0 = 101325.0;

struct Vec3
{
	double x = 0.0;
	double y = 0.0;
	double z = 0.0;

	Vec3 operator+(const Vec3& o) const { return {x + o.x, y + o.y, z + o.z}; }
	Vec3 operator-(const Vec3& o) const { return {x - o.x, y - o.y, z - o.z}; }
	Vec3 operator*(double s) const { return {x * s, y * s, z * s}; }
	Vec3 operator/(double s) const { return {x / s, y / s, z / s}; }
};

inline double dot(const Vec3& a, const Vec3& b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
inline Vec3 cross(const Vec3& a, const Vec3& b)
{
	return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x};
}
inline double norm(const Vec3& a) { return std::sqrt(dot(a, a)); }
inline Vec3 normalized(const Vec3& a)
{
	const double n = norm(a);
	return n > 1e-12 ? a / n : Vec3{0.0, 0.0, 1.0};
}

inline double clampVal(double v, double lo, double hi)
{
	return v < lo ? lo : (v > hi ? hi : v);
}

inline double wrap360(double deg)
{
	double r = std::fmod(deg, 360.0);
	if (r < 0.0) r += 360.0;
	return r;
}

Vec3 geodeticToEcef(double latDeg, double lonDeg, double altM)
{
	const double lat = latDeg * kDeg2Rad;
	const double lon = lonDeg * kDeg2Rad;
	const double sinLat = std::sin(lat);
	const double cosLat = std::cos(lat);
	const double sinLon = std::sin(lon);
	const double cosLon = std::cos(lon);
	const double N = kWgs84A / std::sqrt(1.0 - kWgs84E2 * sinLat * sinLat);
	return {
		(N + altM) * cosLat * cosLon,
		(N + altM) * cosLat * sinLon,
		(N * (1.0 - kWgs84E2) + altM) * sinLat
	};
}

void ecefToGeodetic(const Vec3& r, double& latDeg, double& lonDeg, double& altM)
{
	const double lon = std::atan2(r.y, r.x);
	const double p = std::hypot(r.x, r.y);
	double lat = std::atan2(r.z, p * (1.0 - kWgs84E2));
	for (int i = 0; i < 4; ++i)
	{
		const double sinLat = std::sin(lat);
		const double N = kWgs84A / std::sqrt(1.0 - kWgs84E2 * sinLat * sinLat);
		lat = std::atan2(r.z + kWgs84E2 * N * sinLat, p);
	}
	const double sinLat = std::sin(lat);
	const double cosLat = std::cos(lat);
	const double N = kWgs84A / std::sqrt(1.0 - kWgs84E2 * sinLat * sinLat);
	altM = (std::fabs(cosLat) > 1e-6) ? (p / cosLat - N) : (std::fabs(r.z) / std::fabs(sinLat) - N * (1.0 - kWgs84E2));
	latDeg = lat * kRad2Deg;
	lonDeg = lon * kRad2Deg;
}

void localEnuBasis(double latDeg, double lonDeg, Vec3& east, Vec3& north, Vec3& up)
{
	const double lat = latDeg * kDeg2Rad;
	const double lon = lonDeg * kDeg2Rad;
	const double sLat = std::sin(lat), cLat = std::cos(lat);
	const double sLon = std::sin(lon), cLon = std::cos(lon);
	east = {-sLon, cLon, 0.0};
	north = {-sLat * cLon, -sLat * sLon, cLat};
	up = {cLat * cLon, cLat * sLon, sLat};
}

double greatCircleDistanceKm(double lat1Deg, double lon1Deg, double lat2Deg, double lon2Deg)
{
	const double dLat = (lat2Deg - lat1Deg) * kDeg2Rad;
	const double dLon = (lon2Deg - lon1Deg) * kDeg2Rad;
	const double a = std::sin(dLat * 0.5) * std::sin(dLat * 0.5)
		+ std::cos(lat1Deg * kDeg2Rad) * std::cos(lat2Deg * kDeg2Rad)
		* std::sin(dLon * 0.5) * std::sin(dLon * 0.5);
	const double c = 2.0 * std::atan2(std::sqrt(a), std::sqrt(std::max(0.0, 1.0 - a)));
	return (kEarthMeanR * c) / 1000.0;
}

double initialBearingDeg(double lat1Deg, double lon1Deg, double lat2Deg, double lon2Deg)
{
	const double phi1 = lat1Deg * kDeg2Rad;
	const double phi2 = lat2Deg * kDeg2Rad;
	const double dLon = (lon2Deg - lon1Deg) * kDeg2Rad;
	const double y = std::sin(dLon) * std::cos(phi2);
	const double x = std::cos(phi1) * std::sin(phi2) - std::sin(phi1) * std::cos(phi2) * std::cos(dLon);
	return wrap360(std::atan2(y, x) * kRad2Deg);
}

// US Standard Atmosphere 1976 (0..500 km)
struct AtmosSample
{
	double densityKgM3 = 0.0;
	double pressurePa = 0.0;
	double soundSpeedMS = 300.0;
};

AtmosSample us76Atmosphere(double altM)
{
	const double h = std::max(0.0, altM);
	if (h >= 86000.0)
	{
		// Thermosphere / mesopause exponential continuation
		const double hKm = h / 1000.0;
		const double scaleKm = (hKm < 120.0) ? 6.2 : ((hKm < 200.0) ? 18.0 : 42.0);
		const double rho86 = 6.958e-6;
		const double p86 = 0.3734;
		double rho = 0.0;
		double p = 0.0;
		if (hKm <= 120.0)
		{
			const double fac = std::exp(-(hKm - 86.0) / 6.2);
			rho = rho86 * fac;
			p = p86 * fac;
		}
		else if (hKm <= 200.0)
		{
			const double fac86 = std::exp(-(120.0 - 86.0) / 6.2);
			const double fac = std::exp(-(hKm - 120.0) / 18.0);
			rho = rho86 * fac86 * fac;
			p = p86 * fac86 * fac;
		}
		else
		{
			const double fac86 = std::exp(-(120.0 - 86.0) / 6.2) * std::exp(-(200.0 - 120.0) / 18.0);
			const double fac = std::exp(-(hKm - 200.0) / scaleKm);
			rho = rho86 * fac86 * fac;
			p = p86 * fac86 * fac;
		}
		return {rho, p, 274.0};
	}

	static const double hBase[7] = {0.0, 11000.0, 20000.0, 32000.0, 47000.0, 51000.0, 71000.0};
	static const double tBase[7] = {288.15, 216.65, 216.65, 228.65, 270.65, 270.65, 214.65};
	static const double pBase[7] = {101325.0, 22632.06, 5474.889, 868.0187, 110.9063, 66.93887, 3.95642};
	static const double lapse[7] = {-0.0065, 0.0, 0.0010, 0.0028, 0.0, -0.0028, -0.0020};
	constexpr double R = 287.05287;

	int idx = 0;
	for (int i = 6; i >= 0; --i)
	{
		if (h >= hBase[i])
		{
			idx = i;
			break;
		}
	}
	const double dh = h - hBase[idx];
	const double L = lapse[idx];
	const double T = tBase[idx] + L * dh;
	double P = 0.0;
	if (std::fabs(L) < 1e-9)
		P = pBase[idx] * std::exp(-kG0 * dh / (R * tBase[idx]));
	else
		P = pBase[idx] * std::pow(T / tBase[idx], -kG0 / (R * L));
	const double rho = P / (R * T);
	const double cs = std::sqrt(1.4 * R * T);
	return {rho, P, cs};
}

double rocketDragCoeff(double mach)
{
	if (mach < 0.7) return 0.24;
	if (mach < 1.05) return 0.24 + (mach - 0.7) / 0.35 * 0.28;
	if (mach < 2.0) return 0.52 - (mach - 1.05) / 0.95 * 0.24;
	if (mach < 4.0) return 0.28 - (mach - 2.0) / 2.0 * 0.06;
	return 0.22;
}

Vec3 gravityJ2Ecef(const Vec3& r)
{
	const double r2 = dot(r, r);
	const double rMag = std::sqrt(r2);
	if (rMag < 1e3) return {0.0, 0.0, 0.0};
	const double r3 = r2 * rMag;
	const double fac = -kEarthMu / r3;
	const double z2 = r.z * r.z;
	const double j2Term = 1.5 * kEarthJ2 * (kWgs84A * kWgs84A / r2);
	const double xyScale = 1.0 + j2Term * (1.0 - 5.0 * z2 / r2);
	const double zScale = 1.0 + j2Term * (3.0 - 5.0 * z2 / r2);
	return {fac * r.x * xyScale, fac * r.y * xyScale, fac * r.z * zScale};
}

// Convert ISO-8601 UTC string to Julian Date (exact Gregorian formula)
double unixSecToJd(double unixSec)
{
	return unixSec / 86400.0 + 2440587.5;
}

QString unixSecToIsoUtc(double unixSec)
{
	const qint64 ms = static_cast<qint64>(std::llround(unixSec * 1000.0));
	return QDateTime::fromMSecsSinceEpoch(ms, QTimeZone::utc()).toString(Qt::ISODate);
}

bool parseIsoUtcToUnixSec(const QString& iso, double& outUnixSec)
{
	const QString trimmed = iso.trimmed();
	if (trimmed.isEmpty()) return false;
	QDateTime dt = QDateTime::fromString(trimmed, Qt::ISODate);
	if (!dt.isValid())
		dt = QDateTime::fromString(trimmed, Qt::ISODateWithMs);
	if (!dt.isValid()) return false;
	outUnixSec = static_cast<double>(dt.toUTC().toMSecsSinceEpoch()) / 1000.0;
	return true;
}

// Sun unit vector in ECEF at given Julian Date (Meeus low-precision, <0.01 deg error)
Vec3 sunDirectionEcef(double jd)
{
	const double n = jd - 2451545.0;
	const double L = wrap360(280.460 + 0.9856474 * n);
	const double g = wrap360(357.528 + 0.9856003 * n) * kDeg2Rad;
	const double lambda = (L + 1.915 * std::sin(g) + 0.020 * std::sin(2.0 * g)) * kDeg2Rad;
	const double eps = (23.439 - 0.0000004 * n) * kDeg2Rad;
	const double ra = std::atan2(std::cos(eps) * std::sin(lambda), std::cos(lambda));
	const double dec = std::asin(clampVal(std::sin(eps) * std::sin(lambda), -1.0, 1.0));
	const double gmst = wrap360(280.46061837 + 360.98564736629 * n) * kDeg2Rad;
	const double gha = gmst - ra;
	return {
		std::cos(dec) * std::cos(gha),
		-std::cos(dec) * std::sin(gha),
		std::sin(dec)
	};
}

void sunAzAltAtObserver(double jd, double latDeg, double lonDeg, double& azDeg, double& altDeg)
{
	const Vec3 s = sunDirectionEcef(jd);
	Vec3 e, n, u;
	localEnuBasis(latDeg, lonDeg, e, n, u);
	const double se = dot(s, e);
	const double sn = dot(s, n);
	const double su = dot(s, u);
	altDeg = std::asin(clampVal(su, -1.0, 1.0)) * kRad2Deg;
	azDeg = wrap360(std::atan2(se, sn) * kRad2Deg);
}

QString classifyTwilight(double sunAltDeg)
{
	if (sunAltDeg > -0.833) return QStringLiteral("daylight");
	if (sunAltDeg > -6.0) return QStringLiteral("civil");
	if (sunAltDeg > -12.0) return QStringLiteral("nautical");
	if (sunAltDeg > -18.0) return QStringLiteral("astronomical");
	return QStringLiteral("night");
}

// Point-in-polygon (ray casting in lon/lat) & min edge distance (km)
bool pointInPolygon(double latDeg, double lonDeg, const QVector<QPair<double, double>>& poly)
{
	if (poly.size() < 3) return false;
	bool inside = false;
	const int n = poly.size();
	for (int i = 0, j = n - 1; i < n; j = i++)
	{
		const double yi = poly[i].first, xi = poly[i].second;
		const double yj = poly[j].first, xj = poly[j].second;
		const bool intersect = ((yi > latDeg) != (yj > latDeg))
			&& (lonDeg < (xj - xi) * (latDeg - yi) / (yj - yi + 1e-12) + xi);
		if (intersect) inside = !inside;
	}
	return inside;
}

double distanceToSegmentKm(double lat, double lon, double latA, double lonA, double latB, double lonB)
{
	const double cosLat = std::cos(lat * kDeg2Rad);
	const double px = (lon - lonA) * cosLat;
	const double py = (lat - latA);
	const double bx = (lonB - lonA) * cosLat;
	const double by = (latB - latA);
	const double b2 = bx * bx + by * by;
	double t = (b2 > 1e-12) ? clampVal((px * bx + py * by) / b2, 0.0, 1.0) : 0.0;
	const double cxLat = latA + t * (latB - latA);
	const double cxLon = lonA + t * (lonB - lonA);
	return greatCircleDistanceKm(lat, lon, cxLat, cxLon);
}

double distanceToNotamBoundaryKm(double lat, double lon, const RocketNotamZone& zone, bool& inside)
{
	inside = false;
	if (!zone.valid) return -1.0;
	if (zone.polygonLatLon.size() >= 3)
	{
		inside = pointInPolygon(lat, lon, zone.polygonLatLon);
		double bestKm = 1e9;
		const int n = zone.polygonLatLon.size();
		for (int i = 0; i < n; ++i)
		{
			const auto& a = zone.polygonLatLon[i];
			const auto& b = zone.polygonLatLon[(i + 1) % n];
			bestKm = std::min(bestKm, distanceToSegmentKm(lat, lon, a.first, a.second, b.first, b.second));
		}
		return bestKm;
	}
	if (zone.hasCircle && zone.circleRadiusKm > 0.0)
	{
		const double d = greatCircleDistanceKm(lat, lon, zone.circleLatDeg, zone.circleLonDeg);
		inside = (d <= zone.circleRadiusKm);
		return std::fabs(d - zone.circleRadiusKm);
	}
	return -1.0;
}

// Parse compact ICAO NOTAM coordinate tokens like N3801E10729, 3801N10729E, 380112N1072930E
bool parseNotamCoordToken(const QString& token, double& latDeg, double& lonDeg)
{
	auto dmsToDeg = [](const QString& digits, bool isLat) -> double {
		const int degLen = isLat ? 2 : 3;
		if (digits.size() == degLen + 2)
		{
			const double d = digits.left(degLen).toDouble();
			const double m = digits.mid(degLen, 2).toDouble();
			return d + m / 60.0;
		}
		if (digits.size() == degLen + 4)
		{
			const double d = digits.left(degLen).toDouble();
			const double m = digits.mid(degLen, 2).toDouble();
			const double s = digits.mid(degLen + 2, 2).toDouble();
			return d + m / 60.0 + s / 3600.0;
		}
		return std::numeric_limits<double>::quiet_NaN();
	};

	// Format 1: N3801E10729 or N380112E1072930
	static const QRegularExpression reNSfirst(QStringLiteral("^([NS])(\\d{4}|\\d{6})\\s*([EW])(\\d{5}|\\d{7})$"));
	auto m1 = reNSfirst.match(token);
	if (m1.hasMatch())
	{
		double la = dmsToDeg(m1.captured(2), true);
		double lo = dmsToDeg(m1.captured(4), false);
		if (std::isfinite(la) && std::isfinite(lo))
		{
			latDeg = (m1.captured(1) == QLatin1String("S")) ? -la : la;
			lonDeg = (m1.captured(3) == QLatin1String("W")) ? -lo : lo;
			return true;
		}
	}

	// Format 2: 3801N10729E or 380112N1072930E
	static const QRegularExpression reNSlast(QStringLiteral("^(\\d{4}|\\d{6})([NS])\\s*(\\d{5}|\\d{7})([EW])$"));
	auto m2 = reNSlast.match(token);
	if (m2.hasMatch())
	{
		double la = dmsToDeg(m2.captured(1), true);
		double lo = dmsToDeg(m2.captured(3), false);
		if (std::isfinite(la) && std::isfinite(lo))
		{
			latDeg = (m2.captured(2) == QLatin1String("S")) ? -la : la;
			lonDeg = (m2.captured(4) == QLatin1String("W")) ? -lo : lo;
			return true;
		}
	}
	return false;
}

// Deterministic fast PRNG (xorshift64* + Box-Muller Gaussian) for Monte Carlo dispersion
struct FastRng
{
	uint64_t state = 0x9E3779B97F4A7C15ULL;
	explicit FastRng(uint64_t seed) { state = seed ? seed : 0x9E3779B97F4A7C15ULL; }
	double uniform01()
	{
		uint64_t x = state;
		x ^= x >> 12;
		x ^= x << 25;
		x ^= x >> 27;
		state = x;
		return static_cast<double>((x * 2685821657736338717ULL) >> 11) * (1.0 / 9007199254740992.0);
	}
	double normal01()
	{
		const double u1 = std::max(1e-12, uniform01());
		const double u2 = uniform01();
		return std::sqrt(-2.0 * std::log(u1)) * std::cos(2.0 * kPi * u2);
	}
};

// Independent 3-DOF ballistic debris re-entry integration
RocketDebrisTrack simulateDebrisFallback(
	const QString& kind,
	const QString& labelZh,
	const QString& labelEn,
	double sepTimeSec,
	double launchUnixSec,
	const Vec3& r0,
	const Vec3& v0,
	double massKg,
	double cd,
	double refAreaM2,
	const RocketLaunchSite& pad,
	const RocketNotamZone& notam,
	double windEastMS = 0.0,
	double windNorthMS = 0.0,
	bool recordArc = true)
{
	RocketDebrisTrack track;
	track.kind = kind;
	track.labelZh = labelZh;
	track.labelEn = labelEn;
	track.sepTimeSec = sepTimeSec;

	Vec3 r = r0;
	Vec3 v = v0;
	double t = sepTimeSec;
	const double dt = 1.0;
	const Vec3 omegaVec{0.0, 0.0, kEarthOmega};
	const double invMass = 1.0 / std::max(10.0, massKg);

	auto accel = [&](const Vec3& pos, const Vec3& vel) -> Vec3 {
		double la = 0.0, lo = 0.0, alt = 0.0;
		ecefToGeodetic(pos, la, lo, alt);
		Vec3 a = gravityJ2Ecef(pos);
		// Coriolis & centrifugal
		a = a - cross(omegaVec, vel) * 2.0 - cross(omegaVec, cross(omegaVec, pos));
		if (alt < 160000.0)
		{
			const AtmosSample atm = us76Atmosphere(alt);
			Vec3 e, n, u;
			localEnuBasis(la, lo, e, n, u);
			// Simple tropospheric/stratospheric wind attenuation
			const double windScale = (alt < 45000.0) ? std::exp(-std::pow((alt - 12000.0) / 14000.0, 2.0)) : 0.0;
			const Vec3 vWind = e * (windEastMS * windScale) + n * (windNorthMS * windScale);
			const Vec3 vRel = vel - vWind;
			const double spd = norm(vRel);
			if (spd > 1e-3 && atm.densityKgM3 > 1e-12)
			{
				const double q = 0.5 * atm.densityKgM3 * spd * spd;
				const double dragAcc = (q * cd * refAreaM2) * invMass;
				a = a - (vRel / spd) * dragAcc;
			}
		}
		return a;
	};

	double la = 0.0, lo = 0.0, alt = 0.0;
	ecefToGeodetic(r, la, lo, alt);
	track.maxAltKm = alt / 1000.0;
	if (recordArc)
		track.arcPoints.append({t, la, lo, alt / 1000.0});

	for (int step = 0; step < 2400; ++step)
	{
		const Vec3 k1r = v;
		const Vec3 k1v = accel(r, v);
		const Vec3 k2r = v + k1v * (0.5 * dt);
		const Vec3 k2v = accel(r + k1r * (0.5 * dt), k2r);
		const Vec3 k3r = v + k2v * (0.5 * dt);
		const Vec3 k3v = accel(r + k2r * (0.5 * dt), k3r);
		const Vec3 k4r = v + k3v * dt;
		const Vec3 k4v = accel(r + k3r * dt, k4r);

		const Vec3 rNext = r + (k1r + k2r * 2.0 + k3r * 2.0 + k4r) * (dt / 6.0);
		const Vec3 vNext = v + (k1v + k2v * 2.0 + k3v * 2.0 + k4v) * (dt / 6.0);
		const double tNext = t + dt;

		double laN = 0.0, loN = 0.0, altN = 0.0;
		ecefToGeodetic(rNext, laN, loN, altN);
		if (altN / 1000.0 > track.maxAltKm)
			track.maxAltKm = altN / 1000.0;

		if (altN <= 0.0)
		{
			const double frac = (alt > 0.0 && (alt - altN) > 1e-3) ? clampVal(alt / (alt - altN), 0.0, 1.0) : 1.0;
			const Vec3 rHit = r + (rNext - r) * frac;
			double hitLat = 0.0, hitLon = 0.0, hitAlt = 0.0;
			ecefToGeodetic(rHit, hitLat, hitLon, hitAlt);
			track.impactTimeSec = t + dt * frac;
			track.impactTimeUtc = unixSecToIsoUtc(launchUnixSec + track.impactTimeSec);
			track.impactLatDeg = hitLat;
			track.impactLonDeg = hitLon;
			track.downrangeKm = greatCircleDistanceKm(pad.latDeg, pad.lonDeg, hitLat, hitLon);
			track.distanceToNotamKm = distanceToNotamBoundaryKm(hitLat, hitLon, notam, track.insideNotam);
			if (recordArc)
				track.arcPoints.append({track.impactTimeSec, hitLat, hitLon, 0.0});
			return track;
		}

		r = rNext;
		v = vNext;
		t = tNext;
		la = laN;
		lo = loN;
		alt = altN;

		if (recordArc && (step % 5 == 0))
			track.arcPoints.append({t, la, lo, alt / 1000.0});
	}

	// Fallback if debris stays aloft (orbital / suborbital very long flight)
	track.impactTimeSec = t;
	track.impactTimeUtc = unixSecToIsoUtc(launchUnixSec + t);
	track.impactLatDeg = la;
	track.impactLonDeg = lo;
	track.downrangeKm = greatCircleDistanceKm(pad.latDeg, pad.lonDeg, la, lo);
	track.distanceToNotamKm = distanceToNotamBoundaryKm(la, lo, notam, track.insideNotam);
	return track;
}

// Compute propellant-specific twilight plume physical brightness, angular width & RGB color
void evaluatePlumePhysics(
	const QString& activePropellant,
	double altKm,
	double rangeKm,
	double obsAltDeg,
	double obsSunAltDeg,
	double shadowTangentAltKm,
	bool engineBurning,
	double& outWidthKm,
	double& outAngularDeg,
	double& outBrightness,
	double& outR,
	double& outG,
	double& outB)
{
	outWidthKm = 0.0;
	outAngularDeg = 0.0;
	outBrightness = 0.0;
	outR = 0.85;
	outG = 0.92;
	outB = 1.0;

	if (altKm < 1.0 || rangeKm < 1.0)
		return;

	const AtmosSample atm = us76Atmosphere(altKm * 1000.0);
	const bool isSolid = (activePropellant == QLatin1String("solid"));
	const bool isKerolox = (activePropellant == QLatin1String("kerolox"));
	const bool isMethalox = (activePropellant == QLatin1String("methalox"));
	const bool isHydrolox = (activePropellant == QLatin1String("hydrolox"));
	const bool isHypergolic = (activePropellant == QLatin1String("hypergolic"));

	// 1. Under-expanded plume physical width (km): scales with sqrt(P0/P(h)), capped in free-molecular regime
	const double pRatio = kP0 / std::max(atm.pressurePa, 1e-5);
	const double baseWidthKm = isSolid ? 0.14 : (isHydrolox ? 0.18 : 0.12);
	const double maxWidthKm = isSolid ? 14.0 : (isHydrolox ? 36.0 : (isMethalox ? 32.0 : 28.0));
	outWidthKm = clampVal(baseWidthKm * std::pow(pRatio, 0.36), 0.08, maxWidthKm);
	outAngularDeg = 2.0 * std::atan(outWidthKm * 0.5 / std::max(rangeKm, 1.0)) * kRad2Deg;

	// 2. Solar illumination factor based on Earth-shadow tangent height h_eff (km)
	double illumFactor = 0.0;
	double sunsetRedMix = 0.0;
	if (shadowTangentAltKm <= 0.0)
	{
		illumFactor = 0.0;
	}
	else if (shadowTangentAltKm < 25.0)
	{
		// Sunlight grazing troposphere / ozone layer -> golden-orange/pink-red glow
		illumFactor = 0.35 + 0.65 * (shadowTangentAltKm / 25.0);
		sunsetRedMix = 1.0 - (shadowTangentAltKm / 25.0);
	}
	else
	{
		illumFactor = 1.0;
		sunsetRedMix = 0.0;
	}

	// 3. Propellant altitude effectiveness curve
	double altFactor = 0.0;
	if (isSolid)
	{
		// Al2O3 solid particulates are intensely reflective from 10 km up to ~210 km
		// across multi-stage solid burns (Stage 1 ribbon + Stage 2/3 upper-stage plume)
		if (altKm >= 8.0 && altKm <= 220.0)
		{
			const double rise = clampVal((altKm - 8.0) / 14.0, 0.0, 1.0);
			const double fall = clampVal((220.0 - altKm) / 65.0, 0.0, 1.0);
			altFactor = rise * fall * 1.0;
		}
	}
	else if (isKerolox)
	{
		// Classic space jellyfish peaks strongly at 70..230 km during powered flight
		if (engineBurning && altKm >= 45.0 && altKm <= 280.0)
		{
			const double rise = clampVal((altKm - 45.0) / 35.0, 0.0, 1.0);
			const double fall = clampVal((280.0 - altKm) / 70.0, 0.0, 1.0);
			altFactor = rise * fall * 0.96;
		}
		else if (engineBurning && altKm >= 15.0 && altKm < 45.0)
		{
			altFactor = 0.18 * ((altKm - 15.0) / 30.0);
		}
	}
	else if (isMethalox)
	{
		// Clean icy-blue H2O/CO2 jellyfish, transparent low down, crisp at 75..260 km
		if (engineBurning && altKm >= 55.0 && altKm <= 290.0)
		{
			const double rise = clampVal((altKm - 55.0) / 30.0, 0.0, 1.0);
			const double fall = clampVal((290.0 - altKm) / 70.0, 0.0, 1.0);
			altFactor = rise * fall * 0.92;
		}
	}
	else if (isHydrolox)
	{
		// Pure H2O vapor: transparent low down, broad pearlescent veil at 80..270 km
		if (engineBurning && altKm >= 65.0 && altKm <= 300.0)
		{
			const double rise = clampVal((altKm - 65.0) / 30.0, 0.0, 1.0);
			const double fall = clampVal((300.0 - altKm) / 70.0, 0.0, 1.0);
			altFactor = rise * fall * 0.85;
		}
	}
	else if (isHypergolic)
	{
		// Low-alt NO2 reddish smoke (5..35 km) + high-alt H2O/N2O4 jellyfish (70..230 km)
		if (engineBurning && altKm >= 5.0 && altKm <= 38.0)
		{
			altFactor = 0.38 * clampVal((altKm - 5.0) / 8.0, 0.0, 1.0) * clampVal((38.0 - altKm) / 12.0, 0.0, 1.0);
		}
		else if (engineBurning && altKm >= 55.0 && altKm <= 250.0)
		{
			const double rise = clampVal((altKm - 55.0) / 28.0, 0.0, 1.0);
			const double fall = clampVal((250.0 - altKm) / 60.0, 0.0, 1.0);
			altFactor = rise * fall * 0.90;
		}
	}

	// 4. Observer sky-darkness contrast factor
	double skyContrast = 0.0;
	if (isSolid)
	{
		// Solid Al2O3 ribbons stand out even in bright civil twilight or low sun
		if (obsSunAltDeg <= -4.0) skyContrast = 1.0;
		else if (obsSunAltDeg <= 3.0) skyContrast = 1.0 - 0.55 * ((obsSunAltDeg + 4.0) / 7.0);
		else if (obsSunAltDeg <= 15.0) skyContrast = 0.45 * (1.0 - (obsSunAltDeg - 3.0) / 12.0);
		else skyContrast = 0.12;
	}
	else
	{
		// Liquid translucent jellyfish strictly requires twilight/dark sky background
		if (obsSunAltDeg <= -7.0) skyContrast = 1.0;
		else if (obsSunAltDeg <= -3.0) skyContrast = 0.30 + 0.70 * ((-3.0 - obsSunAltDeg) / 4.0);
		else if (obsSunAltDeg <= 0.0) skyContrast = 0.30 * (-obsSunAltDeg / 3.0);
		else skyContrast = 0.0;
	}

	// 5. Distance & atmospheric extinction attenuation
	const double distFactor = clampVal(1.0 / (1.0 + std::pow(rangeKm / 950.0, 1.6)), 0.08, 1.0);
	const double elevFactor = (obsAltDeg > 0.0) ? clampVal(std::sin(obsAltDeg * kDeg2Rad) * 4.5, 0.20, 1.0) : 0.0;

	outBrightness = clampVal(illumFactor * altFactor * skyContrast * distFactor * elevFactor, 0.0, 1.0);

	// 6. Physically-inspired base RGB tint per propellant + sunset reddening
	double baseR = 0.86, baseG = 0.95, baseB = 1.0;
	if (isSolid)
	{
		baseR = 1.0; baseG = 0.97; baseB = 0.92;
	}
	else if (isKerolox)
	{
		baseR = 0.80; baseG = 0.96; baseB = 1.0;
	}
	else if (isMethalox)
	{
		baseR = 0.72; baseG = 0.92; baseB = 1.0;
	}
	else if (isHydrolox)
	{
		baseR = 0.90; baseG = 0.95; baseB = 1.0;
	}
	else if (isHypergolic)
	{
		if (altKm < 45.0) { baseR = 0.92; baseG = 0.56; baseB = 0.34; }
		else { baseR = 0.95; baseG = 0.94; baseB = 0.88; }
	}
	// Blend toward warm sunset gold/orange/coral when grazing 0..25 km tangent shadow
	outR = baseR * (1.0 - sunsetRedMix) + 1.00 * sunsetRedMix;
	outG = baseG * (1.0 - sunsetRedMix) + 0.58 * sunsetRedMix;
	outB = baseB * (1.0 - sunsetRedMix) + 0.34 * sunsetRedMix;
}

} // namespace

RocketLaunchMgr::RocketLaunchMgr()
{
	setObjectName("RocketLaunchMgr");
}

RocketLaunchMgr::~RocketLaunchMgr()
{
}

void RocketLaunchMgr::init()
{
	// Catalogs are lazy-initialized on first access; zero startup cost.
}

void RocketLaunchMgr::update(double deltaTime)
{
	if (!previewActive || !previewPlaying)
		return;
	if (activePreview.trajectory.isEmpty())
		return;
	const double maxT = activePreview.trajectory.last().tSec;
	previewTimeSec += deltaTime * previewSpeed;
	if (previewTimeSec > maxT)
	{
		previewTimeSec = maxT;
		previewPlaying = false;
	}
	else if (previewTimeSec < 0.0)
	{
		previewTimeSec = 0.0;
	}
}

void RocketLaunchMgr::draw(StelCore* core)
{
	// Phase 3 will render the 3D ascent arc, live rocket glow, solid wind-sheared ribbon,
	// liquid under-expanded jellyfish plume, and camera framing rectangle here.
	Q_UNUSED(core)
}

double RocketLaunchMgr::getCallOrder(StelModuleActionName actionName) const
{
	if (actionName == StelModule::ActionDraw)
		return 105.0; // Draw after Landscape/Atmosphere/Satellites
	return 0.0;
}

const QVector<RocketLaunchSite>& RocketLaunchMgr::launchSites()
{
	static const QVector<RocketLaunchSite> kSites = {
		{QStringLiteral("tslc"), QStringLiteral("太原卫星发射中心"), QStringLiteral("Taiyuan Satellite Launch Center"), QStringLiteral("TSLC"), QStringLiteral("CN"), 38.8491, 111.6080, 1490.0, 200.0, false},
		{QStringLiteral("jslc"), QStringLiteral("酒泉卫星发射中心"), QStringLiteral("Jiuquan Satellite Launch Center"), QStringLiteral("JSLC"), QStringLiteral("CN"), 40.9606, 100.2983, 1000.0, 155.0, false},
		{QStringLiteral("xslc"), QStringLiteral("西昌卫星发射中心"), QStringLiteral("Xichang Satellite Launch Center"), QStringLiteral("XSLC"), QStringLiteral("CN"), 28.2460, 102.0266, 1820.0, 105.0, false},
		{QStringLiteral("wslc"), QStringLiteral("文昌航天发射场"), QStringLiteral("Wenchang Space Launch Site"), QStringLiteral("WSLC"), QStringLiteral("CN"), 19.6145, 110.9511, 20.0, 105.0, false},
		{QStringLiteral("hcsls"), QStringLiteral("海南商业航天发射场"), QStringLiteral("Hainan Commercial Spacecraft Launch Site"), QStringLiteral("HCSLS"), QStringLiteral("CN"), 19.5980, 110.9550, 15.0, 110.0, false},
		{QStringLiteral("ysla"), QStringLiteral("东方航天港（海阳海上）"), QStringLiteral("Haiyang Sea Launch (Oriental Spaceport)"), QStringLiteral("YSLA"), QStringLiteral("CN"), 36.6415, 121.2014, 5.0, 175.0, true},
		{QStringLiteral("ksc"), QStringLiteral("肯尼迪航天中心"), QStringLiteral("Kennedy Space Center"), QStringLiteral("KSC"), QStringLiteral("US"), 28.6084, -80.6043, 5.0, 90.0, false},
		{QStringLiteral("ccsfs"), QStringLiteral("卡纳维拉尔角太空军基地"), QStringLiteral("Cape Canaveral Space Force Station"), QStringLiteral("CCSFS"), QStringLiteral("US"), 28.5620, -80.5774, 5.0, 90.0, false},
		{QStringLiteral("vsfb"), QStringLiteral("范登堡太空军基地"), QStringLiteral("Vandenberg Space Force Base"), QStringLiteral("VSFB"), QStringLiteral("US"), 34.6321, -120.6106, 110.0, 185.0, false},
		{QStringLiteral("starbase"), QStringLiteral("SpaceX 星基地（博卡奇卡）"), QStringLiteral("SpaceX Starbase (Boca Chica)"), QStringLiteral("STARBASE"), QStringLiteral("US"), 25.9972, -97.1560, 5.0, 97.0, false},
		{QStringLiteral("baikonur"), QStringLiteral("拜科努尔航天发射场"), QStringLiteral("Baikonur Cosmodrome"), QStringLiteral("BAIK"), QStringLiteral("KZ"), 45.9646, 63.3052, 95.0, 65.0, false},
		{QStringLiteral("vostochny"), QStringLiteral("东方航天发射场"), QStringLiteral("Vostochny Cosmodrome"), QStringLiteral("VOST"), QStringLiteral("RU"), 51.8844, 128.3339, 250.0, 80.0, false},
		{QStringLiteral("kourou"), QStringLiteral("圭亚那库鲁航天中心"), QStringLiteral("Guiana Space Centre (Kourou)"), QStringLiteral("CSG"), QStringLiteral("GF"), 5.2390, -52.7680, 15.0, 90.0, false},
		{QStringLiteral("tanegashima"), QStringLiteral("种子岛宇宙中心"), QStringLiteral("Tanegashima Space Center"), QStringLiteral("TNSC"), QStringLiteral("JP"), 30.4009, 130.9751, 25.0, 95.0, false},
		{QStringLiteral("sdsc"), QStringLiteral("萨迪什·达万航天中心"), QStringLiteral("Satish Dhawan Space Centre"), QStringLiteral("SDSC"), QStringLiteral("IN"), 13.7199, 80.2304, 10.0, 102.0, false},
		{QStringLiteral("mahia"), QStringLiteral("玛希亚发射场（Rocket Lab）"), QStringLiteral("Rocket Lab Launch Complex 1 (Mahia)"), QStringLiteral("LC-1"), QStringLiteral("NZ"), -39.2615, 177.8649, 100.0, 160.0, false},
	};
	return kSites;
}

const QVector<RocketVehicleSpec>& RocketLaunchMgr::vehicles()
{
	static const QVector<RocketVehicleSpec> kVehicles = []() {
		QVector<RocketVehicleSpec> v;
		auto add = [&](RocketVehicleSpec spec) { v.append(spec); };

		// 1. CZ-6A (Long March 6A) — Hybrid Solid Boosters + Kerolox Core (flagship dual-mode plume!)
		{
			RocketVehicleSpec s;
			s.id = QStringLiteral("cz6a");
			s.nameZh = QStringLiteral("长征六号改 (CZ-6A)");
			s.nameEn = QStringLiteral("Long March 6A");
			s.family = QStringLiteral("Long March");
			s.propellantClass = QStringLiteral("hybrid_solid_liquid");
			s.plumeTypeZh = QStringLiteral("固液混合双形态（固体扭曲彩带 + 高空青白水母）");
			s.plumeTypeEn = QStringLiteral("Hybrid Dual-Mode (Solid Twisted Ribbon + High-Alt Jellyfish)");
			s.summaryZh = QStringLiteral("4台固体助推器 + 液氧煤油芯级，低中空留持久亮白固体烟带，高空接力绽放青白太空水母。");
			s.summaryEn = QStringLiteral("4 solid boosters + kerolox core: persistent twisted solid trail followed by high-altitude jellyfish plume.");
			s.payloadMassKg = 4500.0; s.fairingMassKg = 1400.0; s.fairingSepSec = 185.0; s.fairingAreaM2 = 16.0;
			s.kickStartSec = 9.0; s.kickDurationSec = 14.0; s.kickAngleDeg = 8.4; s.stage2TargetPitchDeg = 2.0;
			s.hasBoosters = true; s.boosterCount = 4;
			s.booster = {QStringLiteral("4×固体助推器"), QStringLiteral("4x Solid Boosters"), QStringLiteral("solid"), 24000.0, 152000.0, 4800e3, 5200e3, 114.0, 12.6, 1.15};
			s.stage1 = {QStringLiteral("芯一级 (2×YF-100)"), QStringLiteral("Core Stage 1 (2x YF-100)"), QStringLiteral("kerolox"), 22000.0, 235000.0, 2400e3, 2680e3, 234.0, 9.0, 1.05};
			s.stage2 = {QStringLiteral("芯二级 (YF-115)"), QStringLiteral("Stage 2 (YF-115)"), QStringLiteral("kerolox"), 5200.0, 46000.0, 175e3, 215e3, 565.0, 9.0, 1.0};
			add(s);
		}
		// 2. Kuaizhou-1A — 4-Stage Solid
		{
			RocketVehicleSpec s;
			s.id = QStringLiteral("kz1a");
			s.nameZh = QStringLiteral("快舟一号甲 (KZ-1A)");
			s.nameEn = QStringLiteral("Kuaizhou-1A");
			s.family = QStringLiteral("Kuaizhou");
			s.propellantClass = QStringLiteral("solid");
			s.plumeTypeZh = QStringLiteral("固体浓密扭曲白蛇 / 彩带");
			s.plumeTypeEn = QStringLiteral("Dense Wind-Sheared Solid Ribbon");
			s.summaryZh = QStringLiteral("固体运载火箭，氧化铝微粒丰富，暮光下极易在 20–90 km 留下持续 20–40 分钟的 S 形亮白彩带。");
			s.summaryEn = QStringLiteral("All-solid launcher producing persistent, bright wind-sheared Al2O3 ribbons for 20-40 minutes.");
			s.payloadMassKg = 300.0; s.fairingMassKg = 120.0; s.fairingSepSec = 145.0; s.fairingAreaM2 = 2.2;
			s.kickStartSec = 6.0; s.kickDurationSec = 10.0; s.kickAngleDeg = 5.5; s.stage2TargetPitchDeg = 8.0;
			s.stage1 = {QStringLiteral("一级固体"), QStringLiteral("Stage 1 Solid"), QStringLiteral("solid"), 2600.0, 17800.0, 620e3, 680e3, 72.0, 1.6, 1.1};
			s.stage2 = {QStringLiteral("二/三级固体"), QStringLiteral("Stage 2/3 Solid"), QStringLiteral("solid"), 1400.0, 7400.0, 180e3, 210e3, 120.0, 1.4, 1.0};
			s.hasStage3 = true;
			s.stage3 = {QStringLiteral("末级液体上面级"), QStringLiteral("Upper Stage"), QStringLiteral("hypergolic"), 350.0, 950.0, 15e3, 18e3, 160.0, 1.2, 1.0};
			add(s);
		}
		// 3. Ceres-1 (谷神星一号) — Solid
		{
			RocketVehicleSpec s;
			s.id = QStringLiteral("ceres1");
			s.nameZh = QStringLiteral("谷神星一号 (Ceres-1)");
			s.nameEn = QStringLiteral("Ceres-1");
			s.family = QStringLiteral("Galactic Energy");
			s.propellantClass = QStringLiteral("solid");
			s.plumeTypeZh = QStringLiteral("固体扭曲白蛇 / 金橙彩带");
			s.plumeTypeEn = QStringLiteral("Twisted Solid Exhaust Ribbon");
			s.summaryZh = QStringLiteral("高发射频次固体商业火箭，酒泉与海上发射常在华北/西北留下壮观扭曲火箭云。");
			s.summaryEn = QStringLiteral("High-cadence solid rocket well known for vivid twisted twilight trails.");
			s.payloadMassKg = 400.0; s.fairingMassKg = 140.0; s.fairingSepSec = 150.0; s.fairingAreaM2 = 2.4;
			s.kickStartSec = 6.0; s.kickDurationSec = 10.0; s.kickAngleDeg = 5.2; s.stage2TargetPitchDeg = 8.0;
			s.stage1 = {QStringLiteral("一级固体"), QStringLiteral("Stage 1 Solid"), QStringLiteral("solid"), 2800.0, 19500.0, 660e3, 725e3, 74.0, 1.6, 1.1};
			s.stage2 = {QStringLiteral("二/三级固体"), QStringLiteral("Stage 2/3 Solid"), QStringLiteral("solid"), 1500.0, 8200.0, 190e3, 225e3, 125.0, 1.5, 1.0};
			s.hasStage3 = true;
			s.stage3 = {QStringLiteral("四级液体上面级"), QStringLiteral("Stage 4 Upper"), QStringLiteral("hypergolic"), 380.0, 1100.0, 16e3, 20e3, 165.0, 1.2, 1.0};
			add(s);
		}
		// 4. Kinetica-1 / Lijian-1 (力箭一号) — 4-Stage Solid
		{
			RocketVehicleSpec s;
			s.id = QStringLiteral("kinetica1");
			s.nameZh = QStringLiteral("力箭一号 (Lijian-1)");
			s.nameEn = QStringLiteral("Kinetica-1 (Lijian-1)");
			s.family = QStringLiteral("CAS Space");
			s.propellantClass = QStringLiteral("solid");
			s.plumeTypeZh = QStringLiteral("大型固体浓密扭曲彩带");
			s.plumeTypeEn = QStringLiteral("Large Solid Twisted Ribbon");
			s.summaryZh = QStringLiteral("四级大型固体运载火箭，推力大、排烟量高，极易形成跨省可见的醒目固体尾迹。");
			s.summaryEn = QStringLiteral("Large 4-stage solid vehicle creating wide-area luminous twisted trails.");
			s.payloadMassKg = 2000.0; s.fairingMassKg = 550.0; s.fairingSepSec = 165.0; s.fairingAreaM2 = 8.8;
			s.kickStartSec = 8.0; s.kickDurationSec = 12.0; s.kickAngleDeg = 4.8; s.stage2TargetPitchDeg = 7.0;
			s.stage1 = {QStringLiteral("一级固体"), QStringLiteral("Stage 1 Solid"), QStringLiteral("solid"), 10500.0, 74000.0, 2000e3, 2200e3, 86.0, 5.5, 1.15};
			s.stage2 = {QStringLiteral("二级固体"), QStringLiteral("Stage 2 Solid"), QStringLiteral("solid"), 5200.0, 32000.0, 920e3, 1050e3, 85.0, 5.5, 1.05};
			s.hasStage3 = true;
			s.stage3 = {QStringLiteral("三/四级固体"), QStringLiteral("Stage 3/4 Solid"), QStringLiteral("solid"), 2200.0, 10500.0, 240e3, 285e3, 110.0, 3.8, 1.0};
			add(s);
		}
		// 5. Long March 11 (长征十一号) — Solid
		{
			RocketVehicleSpec s;
			s.id = QStringLiteral("cz11");
			s.nameZh = QStringLiteral("长征十一号 (CZ-11)");
			s.nameEn = QStringLiteral("Long March 11");
			s.family = QStringLiteral("Long March");
			s.propellantClass = QStringLiteral("solid");
			s.plumeTypeZh = QStringLiteral("固体扭曲烟柱 / 彩带");
			s.plumeTypeEn = QStringLiteral("Solid Twisted Plume Ribbon");
			s.summaryZh = QStringLiteral("四级固体快速响应火箭，支持陆地与海上发射，低中空烟带浓密清晰。");
			s.summaryEn = QStringLiteral("Quick-response 4-stage solid rocket for land and sea launches.");
			s.payloadMassKg = 700.0; s.fairingMassKg = 240.0; s.fairingSepSec = 155.0; s.fairingAreaM2 = 3.2;
			s.kickStartSec = 6.0; s.kickDurationSec = 10.0; s.kickAngleDeg = 5.0; s.stage2TargetPitchDeg = 7.0;
			s.stage1 = {QStringLiteral("一级固体"), QStringLiteral("Stage 1 Solid"), QStringLiteral("solid"), 5200.0, 34000.0, 1200e3, 1320e3, 72.0, 3.1, 1.15};
			s.stage2 = {QStringLiteral("二级固体"), QStringLiteral("Stage 2 Solid"), QStringLiteral("solid"), 2400.0, 13000.0, 420e3, 470e3, 80.0, 3.1, 1.05};
			s.hasStage3 = true;
			s.stage3 = {QStringLiteral("三/四级固体"), QStringLiteral("Stage 3/4 Solid"), QStringLiteral("solid"), 1000.0, 4200.0, 110e3, 130e3, 95.0, 2.0, 1.0};
			add(s);
		}
		// 6. Smart Dragon-3 (捷龙三号) — Solid
		{
			RocketVehicleSpec s;
			s.id = QStringLiteral("sd3");
			s.nameZh = QStringLiteral("捷龙三号 (SD-3)");
			s.nameEn = QStringLiteral("Smart Dragon-3");
			s.family = QStringLiteral("China Rocket");
			s.propellantClass = QStringLiteral("solid");
			s.plumeTypeZh = QStringLiteral("海上大型固体扭曲彩带");
			s.plumeTypeEn = QStringLiteral("Large Sea-Launch Solid Ribbon");
			s.summaryZh = QStringLiteral("四级固体商业运载火箭，高频海上发射，晨昏时段沿海地区极具观赏性。");
			s.summaryEn = QStringLiteral("4-stage solid commercial launcher frequently flying from sea platforms.");
			s.payloadMassKg = 1500.0; s.fairingMassKg = 500.0; s.fairingSepSec = 160.0; s.fairingAreaM2 = 8.8;
			s.kickStartSec = 7.0; s.kickDurationSec = 11.0; s.kickAngleDeg = 4.9; s.stage2TargetPitchDeg = 7.0;
			s.stage1 = {QStringLiteral("一级固体"), QStringLiteral("Stage 1 Solid"), QStringLiteral("solid"), 10200.0, 72000.0, 2000e3, 2200e3, 84.0, 5.5, 1.15};
			s.stage2 = {QStringLiteral("二级固体"), QStringLiteral("Stage 2 Solid"), QStringLiteral("solid"), 5000.0, 31000.0, 900e3, 1020e3, 82.0, 5.5, 1.05};
			s.hasStage3 = true;
			s.stage3 = {QStringLiteral("三/四级固体"), QStringLiteral("Stage 3/4 Solid"), QStringLiteral("solid"), 2000.0, 9800.0, 220e3, 265e3, 110.0, 3.8, 1.0};
			add(s);
		}
		// 7. Gravity-1 (引力一号) — Super-Heavy All-Solid
		{
			RocketVehicleSpec s;
			s.id = QStringLiteral("gravity1");
			s.nameZh = QStringLiteral("引力一号 (Gravity-1)");
			s.nameEn = QStringLiteral("Gravity-1");
			s.family = QStringLiteral("Orienspace");
			s.propellantClass = QStringLiteral("solid");
			s.plumeTypeZh = QStringLiteral("巨型固体云柱与超级彩带");
			s.plumeTypeEn = QStringLiteral("Heavy All-Solid Plume Column & Ribbon");
			s.summaryZh = QStringLiteral("全球最大推力固体运载火箭，4台大型固体助推+三级固体芯级，低高空尾迹均极其震撼。");
			s.summaryEn = QStringLiteral("World's highest-thrust all-solid orbital rocket with massive Al2O3 exhaust plumes.");
			s.payloadMassKg = 6500.0; s.fairingMassKg = 1800.0; s.fairingSepSec = 175.0; s.fairingAreaM2 = 13.8;
			s.kickStartSec = 9.0; s.kickDurationSec = 13.0; s.kickAngleDeg = 4.4; s.stage2TargetPitchDeg = 6.0;
			s.hasBoosters = true; s.boosterCount = 4;
			s.booster = {QStringLiteral("4×大型固体助推器"), QStringLiteral("4x Large Solid Boosters"), QStringLiteral("solid"), 28000.0, 175000.0, 5600e3, 6100e3, 78.0, 16.0, 1.2};
			s.stage1 = {QStringLiteral("芯一级固体"), QStringLiteral("Core Stage 1 Solid"), QStringLiteral("solid"), 16000.0, 110000.0, 2400e3, 2700e3, 110.0, 8.8, 1.15};
			s.stage2 = {QStringLiteral("芯二/三级固体"), QStringLiteral("Stage 2/3 Solid"), QStringLiteral("solid"), 8500.0, 52000.0, 1100e3, 1300e3, 135.0, 8.8, 1.0};
			add(s);
		}
		// 8. Long March 7 (长征七号) — Kerolox
		{
			RocketVehicleSpec s;
			s.id = QStringLiteral("cz7");
			s.nameZh = QStringLiteral("长征七号 (CZ-7)");
			s.nameEn = QStringLiteral("Long March 7");
			s.family = QStringLiteral("Long March");
			s.propellantClass = QStringLiteral("kerolox");
			s.plumeTypeZh = QStringLiteral("经典液氧煤油太空水母");
			s.plumeTypeEn = QStringLiteral("Classic Kerolox Space Jellyfish");
			s.summaryZh = QStringLiteral("天舟货运主力液氧煤油火箭，晨昏窗口高空 80–210 km 可展开极明亮青白发光水母。");
			s.summaryEn = QStringLiteral("Tianzhou cargo kerolox rocket capable of vivid cyan-white twilight jellyfish plumes.");
			s.payloadMassKg = 14000.0; s.fairingMassKg = 2200.0; s.fairingSepSec = 205.0; s.fairingAreaM2 = 13.8;
			s.kickStartSec = 15.0; s.kickDurationSec = 15.0; s.kickAngleDeg = 2.6; s.stage2TargetPitchDeg = 7.0;
			s.hasBoosters = true; s.boosterCount = 4;
			s.booster = {QStringLiteral("4×液氧煤油助推器"), QStringLiteral("4x Kerolox Boosters"), QStringLiteral("kerolox"), 26000.0, 280000.0, 5000e3, 5600e3, 173.0, 16.0, 1.1};
			s.stage1 = {QStringLiteral("芯一级 (2×YF-100)"), QStringLiteral("Core Stage 1"), QStringLiteral("kerolox"), 19000.0, 160000.0, 2500e3, 2800e3, 187.0, 9.0, 1.05};
			s.stage2 = {QStringLiteral("芯二级 (4×YF-115)"), QStringLiteral("Stage 2 (4x YF-115)"), QStringLiteral("kerolox"), 7800.0, 78000.0, 680e3, 780e3, 360.0, 9.0, 1.0};
			add(s);
		}
		// 9. Long March 7A (长征七号改) — Kerolox + Hydrolox Stage 3
		{
			RocketVehicleSpec s;
			s.id = QStringLiteral("cz7a");
			s.nameZh = QStringLiteral("长征七号改 (CZ-7A)");
			s.nameEn = QStringLiteral("Long March 7A");
			s.family = QStringLiteral("Long March");
			s.propellantClass = QStringLiteral("kerolox");
			s.plumeTypeZh = QStringLiteral("液氧煤油水母 + 液氢高空薄纱");
			s.plumeTypeEn = QStringLiteral("Kerolox Jellyfish + Hydrolox Upper Veil");
			s.summaryZh = QStringLiteral("高轨液氧煤油主力箭型，三级换装液氢液氧，高空段水母延展距离极远。");
			s.summaryEn = QStringLiteral("GTO kerolox launcher with hydrolox third stage for expansive high-altitude plumes.");
			s.payloadMassKg = 7000.0; s.fairingMassKg = 2000.0; s.fairingSepSec = 210.0; s.fairingAreaM2 = 13.8;
			s.kickStartSec = 11.0; s.kickDurationSec = 14.0; s.kickAngleDeg = 4.3; s.stage2TargetPitchDeg = 6.0;
			s.hasBoosters = true; s.boosterCount = 4;
			s.booster = {QStringLiteral("4×液氧煤油助推器"), QStringLiteral("4x Kerolox Boosters"), QStringLiteral("kerolox"), 26000.0, 290000.0, 4800e3, 5360e3, 173.0, 16.0, 1.1};
			s.stage1 = {QStringLiteral("芯一级 (2×YF-100)"), QStringLiteral("Core Stage 1"), QStringLiteral("kerolox"), 19000.0, 165000.0, 2400e3, 2680e3, 187.0, 9.0, 1.05};
			s.stage2 = {QStringLiteral("芯二级 (4×YF-115)"), QStringLiteral("Stage 2"), QStringLiteral("kerolox"), 7500.0, 62000.0, 600e3, 720e3, 300.0, 9.0, 1.0};
			s.hasStage3 = true;
			s.stage3 = {QStringLiteral("芯三级 (2×YF-75)"), QStringLiteral("Stage 3 Hydrolox"), QStringLiteral("hydrolox"), 3000.0, 18200.0, 140e3, 167e3, 380.0, 7.1, 1.0};
			add(s);
		}
		// 10. Long March 8 (长征八号) — Kerolox + Hydrolox Stage 2
		{
			RocketVehicleSpec s;
			s.id = QStringLiteral("cz8");
			s.nameZh = QStringLiteral("长征八号 (CZ-8)");
			s.nameEn = QStringLiteral("Long March 8");
			s.family = QStringLiteral("Long March");
			s.propellantClass = QStringLiteral("kerolox");
			s.plumeTypeZh = QStringLiteral("液氧煤油水母 + 二级液氢银白光罩");
			s.plumeTypeEn = QStringLiteral("Kerolox Booster + Hydrolox Upper Jellyfish");
			s.summaryZh = QStringLiteral("文昌/海南商发高频箭型，二级采用液氢液氧，暮光高空呈现通透银白羽流。");
			s.summaryEn = QStringLiteral("High-cadence Wenchang launcher with kerolox first stage and hydrolox second stage.");
			s.payloadMassKg = 5000.0; s.fairingMassKg = 1500.0; s.fairingSepSec = 195.0; s.fairingAreaM2 = 13.8;
			s.kickStartSec = 10.0; s.kickDurationSec = 13.0; s.kickAngleDeg = 4.3; s.stage2TargetPitchDeg = 5.5;
			s.hasBoosters = true; s.boosterCount = 2;
			s.booster = {QStringLiteral("2×液氧煤油助推器"), QStringLiteral("2x Kerolox Boosters"), QStringLiteral("kerolox"), 13000.0, 145000.0, 2400e3, 2680e3, 170.0, 8.0, 1.1};
			s.stage1 = {QStringLiteral("芯一级 (2×YF-100)"), QStringLiteral("Core Stage 1"), QStringLiteral("kerolox"), 17500.0, 155000.0, 2400e3, 2680e3, 185.0, 9.0, 1.05};
			s.stage2 = {QStringLiteral("芯二级 (2×YF-75)"), QStringLiteral("Stage 2 Hydrolox"), QStringLiteral("hydrolox"), 3500.0, 22000.0, 140e3, 167e3, 460.0, 7.1, 1.0};
			add(s);
		}
		// 11. Long March 6 (长征六号) — Kerolox
		{
			RocketVehicleSpec s;
			s.id = QStringLiteral("cz6");
			s.nameZh = QStringLiteral("长征六号 (CZ-6)");
			s.nameEn = QStringLiteral("Long March 6");
			s.family = QStringLiteral("Long March");
			s.propellantClass = QStringLiteral("kerolox");
			s.plumeTypeZh = QStringLiteral("液氧煤油轻盈水母云");
			s.plumeTypeEn = QStringLiteral("Kerolox Twilight Jellyfish");
			s.summaryZh = QStringLiteral("新一代小型液氧煤油火箭，暮光窗口可在 80–180 km 形成干净的青白水母。");
			s.summaryEn = QStringLiteral("Small kerolox launcher producing crisp twilight jellyfish at 80-180 km.");
			s.payloadMassKg = 1080.0; s.fairingMassKg = 450.0; s.fairingSepSec = 180.0; s.fairingAreaM2 = 5.3;
			s.kickStartSec = 9.0; s.kickDurationSec = 12.0; s.kickAngleDeg = 4.6; s.stage2TargetPitchDeg = 6.0;
			s.stage1 = {QStringLiteral("芯一级 (YF-100)"), QStringLiteral("Stage 1 (YF-100)"), QStringLiteral("kerolox"), 7600.0, 76000.0, 1200e3, 1340e3, 155.0, 8.8, 1.05};
			s.stage2 = {QStringLiteral("芯二级 (YF-115)"), QStringLiteral("Stage 2 (YF-115)"), QStringLiteral("kerolox"), 2200.0, 16000.0, 150e3, 180e3, 300.0, 4.0, 1.0};
			add(s);
		}
		// 12. Long March 12 (长征十二号) — Kerolox
		{
			RocketVehicleSpec s;
			s.id = QStringLiteral("cz12");
			s.nameZh = QStringLiteral("长征十二号 (CZ-12)");
			s.nameEn = QStringLiteral("Long March 12");
			s.family = QStringLiteral("Long March");
			s.propellantClass = QStringLiteral("kerolox");
			s.plumeTypeZh = QStringLiteral("大型单芯级液氧煤油水母");
			s.plumeTypeEn = QStringLiteral("Single-Stick Heavy Kerolox Jellyfish");
			s.summaryZh = QStringLiteral("3.8米直径两级液氧煤油主力商业箭型，海南商发高频发射，高空羽流明亮。");
			s.summaryEn = QStringLiteral("3.8m two-stage kerolox vehicle flying frequently from Hainan Commercial Spaceport.");
			s.payloadMassKg = 12000.0; s.fairingMassKg = 1800.0; s.fairingSepSec = 195.0; s.fairingAreaM2 = 13.8;
			s.kickStartSec = 10.0; s.kickDurationSec = 14.0; s.kickAngleDeg = 4.4; s.stage2TargetPitchDeg = 5.0;
			s.stage1 = {QStringLiteral("芯一级 (4×YF-100K)"), QStringLiteral("Stage 1 (4x YF-100K)"), QStringLiteral("kerolox"), 26000.0, 320000.0, 4900e3, 5400e3, 170.0, 11.3, 1.05};
			s.stage2 = {QStringLiteral("芯二级 (2×YF-115)"), QStringLiteral("Stage 2 (2x YF-115)"), QStringLiteral("kerolox"), 8000.0, 78000.0, 300e3, 360e3, 420.0, 11.3, 1.0};
			add(s);
		}
		// 13. Long March 5 (长征五号) — Hydrolox Core + Kerolox Boosters
		{
			RocketVehicleSpec s;
			s.id = QStringLiteral("cz5");
			s.nameZh = QStringLiteral("长征五号 (CZ-5)");
			s.nameEn = QStringLiteral("Long March 5");
			s.family = QStringLiteral("Long March");
			s.propellantClass = QStringLiteral("hydrolox");
			s.plumeTypeZh = QStringLiteral("液氢液氧巨型银白薄纱水母");
			s.plumeTypeEn = QStringLiteral("Hydrolox Giant Pearlescent Veil");
			s.summaryZh = QStringLiteral("5米直径液氢液氧重型芯级 + 4台液氧煤油助推，高空形成面积宏大的轻盈乳白/银蓝水母。");
			s.summaryEn = QStringLiteral("5m heavy hydrolox core with 4 kerolox boosters, forming expansive high-altitude veils.");
			s.payloadMassKg = 25000.0; s.fairingMassKg = 3500.0; s.fairingSepSec = 215.0; s.fairingAreaM2 = 21.2;
			s.kickStartSec = 12.0; s.kickDurationSec = 16.0; s.kickAngleDeg = 4.0; s.stage2TargetPitchDeg = 5.0;
			s.hasBoosters = true; s.boosterCount = 4;
			s.booster = {QStringLiteral("4×液氧煤油助推器"), QStringLiteral("4x Kerolox Boosters"), QStringLiteral("kerolox"), 48000.0, 540000.0, 9600e3, 10720e3, 174.0, 35.0, 1.15};
			s.stage1 = {QStringLiteral("芯一级 (2×YF-77 液氢液氧)"), QStringLiteral("Core Stage 1 Hydrolox"), QStringLiteral("hydrolox"), 22000.0, 158000.0, 1020e3, 1400e3, 465.0, 19.6, 1.05};
			s.stage2 = {QStringLiteral("芯二级 (2×YF-75D 液氢液氧)"), QStringLiteral("Stage 2 Hydrolox"), QStringLiteral("hydrolox"), 5000.0, 26500.0, 150e3, 176e3, 520.0, 19.6, 1.0};
			add(s);
		}
		// 14. Zhuque-2E (朱雀二号改进型) — Methalox
		{
			RocketVehicleSpec s;
			s.id = QStringLiteral("zq2e");
			s.nameZh = QStringLiteral("朱雀二号改进型 (ZQ-2E)");
			s.nameEn = QStringLiteral("Zhuque-2E");
			s.family = QStringLiteral("LandSpace");
			s.propellantClass = QStringLiteral("methalox");
			s.plumeTypeZh = QStringLiteral("液氧甲烷清澈冰蓝水母");
			s.plumeTypeEn = QStringLiteral("Crystal Ice-Blue Methalox Jellyfish");
			s.summaryZh = QStringLiteral("全箭液氧甲烷，低空火焰蓝紫干净近乎无烟，进入 80–230 km 暮光高空展开极其清澈的冰蓝水母。");
			s.summaryEn = QStringLiteral("All-methalox launcher producing crystal-clear ice-blue twilight plumes above 80 km.");
			s.payloadMassKg = 4000.0; s.fairingMassKg = 1100.0; s.fairingSepSec = 190.0; s.fairingAreaM2 = 9.0;
			s.kickStartSec = 10.0; s.kickDurationSec = 13.0; s.kickAngleDeg = 4.5; s.stage2TargetPitchDeg = 5.5;
			s.stage1 = {QStringLiteral("一级 (4×天鹊-12A)"), QStringLiteral("Stage 1 (4x TQ-12A)"), QStringLiteral("methalox"), 17000.0, 165000.0, 2820e3, 3200e3, 168.0, 9.0, 1.05};
			s.stage2 = {QStringLiteral("二级 (天鹊-15A)"), QStringLiteral("Stage 2 (TQ-15A)"), QStringLiteral("methalox"), 4800.0, 36000.0, 720e3, 836e3, 185.0, 9.0, 1.0};
			add(s);
		}
		// 15. Long March 2C (长征二号丙) — Hypergolic
		{
			RocketVehicleSpec s;
			s.id = QStringLiteral("cz2c");
			s.nameZh = QStringLiteral("长征二号丙 (CZ-2C)");
			s.nameEn = QStringLiteral("Long March 2C");
			s.family = QStringLiteral("Long March");
			s.propellantClass = QStringLiteral("hypergolic");
			s.plumeTypeZh = QStringLiteral("常温液体（低空橘褐烟 + 高空暖白水母）");
			s.plumeTypeEn = QStringLiteral("Hypergolic (Low Orange-Brown Trail + High Jellyfish)");
			s.summaryZh = QStringLiteral("偏二甲肼/四氧化二氮经典金牌火箭，低空略带红棕色烟迹，80–200 km 暮光段呈现明亮银白水母与热分离脉冲闪光。");
			s.summaryEn = QStringLiteral("UDMH/N2O4 workhorse with reddish low-altitude exhaust and bright high-altitude twilight plumes.");
			s.payloadMassKg = 4000.0; s.fairingMassKg = 1100.0; s.fairingSepSec = 195.0; s.fairingAreaM2 = 9.0;
			s.kickStartSec = 10.0; s.kickDurationSec = 13.0; s.kickAngleDeg = 4.6; s.stage2TargetPitchDeg = 5.5;
			s.stage1 = {QStringLiteral("一级 (4×YF-20C)"), QStringLiteral("Stage 1 Hypergolic"), QStringLiteral("hypergolic"), 13000.0, 163000.0, 2960e3, 3250e3, 130.0, 9.0, 1.1};
			s.stage2 = {QStringLiteral("二级 (YF-24E)"), QStringLiteral("Stage 2 Hypergolic"), QStringLiteral("hypergolic"), 4800.0, 54000.0, 680e3, 742e3, 220.0, 9.0, 1.0};
			add(s);
		}
		// 16. Long March 2D (长征二号丁) — Hypergolic
		{
			RocketVehicleSpec s;
			s.id = QStringLiteral("cz2d");
			s.nameZh = QStringLiteral("长征二号丁 (CZ-2D)");
			s.nameEn = QStringLiteral("Long March 2D");
			s.family = QStringLiteral("Long March");
			s.propellantClass = QStringLiteral("hypergolic");
			s.plumeTypeZh = QStringLiteral("常温液体（低空橘烟 + 高空亮白水母）");
			s.plumeTypeEn = QStringLiteral("Hypergolic Low Trail + High Jellyfish");
			s.summaryZh = QStringLiteral("酒泉/太原/西昌高频太阳同步轨道火箭，热分离瞬间光团非常显著。");
			s.summaryEn = QStringLiteral("High-cadence SSO hypergolic launcher known for bright hot-staging flashes.");
			s.payloadMassKg = 4000.0; s.fairingMassKg = 1100.0; s.fairingSepSec = 200.0; s.fairingAreaM2 = 9.0;
			s.kickStartSec = 10.0; s.kickDurationSec = 13.0; s.kickAngleDeg = 4.6; s.stage2TargetPitchDeg = 5.5;
			s.stage1 = {QStringLiteral("一级 (4×YF-20C)"), QStringLiteral("Stage 1 Hypergolic"), QStringLiteral("hypergolic"), 13500.0, 182000.0, 2960e3, 3250e3, 152.0, 9.0, 1.1};
			s.stage2 = {QStringLiteral("二级 (YF-24C)"), QStringLiteral("Stage 2 Hypergolic"), QStringLiteral("hypergolic"), 4500.0, 46000.0, 680e3, 742e3, 195.0, 9.0, 1.0};
			add(s);
		}
		// 17. Long March 2F (长征二号F) — Crewed Hypergolic
		{
			RocketVehicleSpec s;
			s.id = QStringLiteral("cz2f");
			s.nameZh = QStringLiteral("长征二号F (CZ-2F 神舟)");
			s.nameEn = QStringLiteral("Long March 2F");
			s.family = QStringLiteral("Long March");
			s.propellantClass = QStringLiteral("hypergolic");
			s.plumeTypeZh = QStringLiteral("载人常规液体（大推力高空银白水母）");
			s.plumeTypeEn = QStringLiteral("Crewed Hypergolic Bright Jellyfish");
			s.summaryZh = QStringLiteral("神舟载人飞船专属座驾，4台液体助推器推力充沛，晨昏发射时华北/西北高空极亮。");
			s.summaryEn = QStringLiteral("Shenzhou crewed launcher with 4 hypergolic boosters; spectacular in twilight.");
			s.payloadMassKg = 8600.0; s.fairingMassKg = 2400.0; s.fairingSepSec = 200.0; s.fairingAreaM2 = 11.3;
			s.kickStartSec = 11.0; s.kickDurationSec = 14.0; s.kickAngleDeg = 4.3; s.stage2TargetPitchDeg = 5.0;
			s.hasBoosters = true; s.boosterCount = 4;
			s.booster = {QStringLiteral("4×常温液体助推器"), QStringLiteral("4x Hypergolic Boosters"), QStringLiteral("hypergolic"), 15000.0, 151000.0, 2960e3, 3260e3, 153.0, 16.0, 1.15};
			s.stage1 = {QStringLiteral("芯一级 (4×YF-20B)"), QStringLiteral("Core Stage 1"), QStringLiteral("hypergolic"), 14500.0, 187000.0, 2960e3, 3260e3, 159.0, 9.0, 1.1};
			s.stage2 = {QStringLiteral("芯二级 (YF-24B)"), QStringLiteral("Stage 2"), QStringLiteral("hypergolic"), 6000.0, 86000.0, 680e3, 742e3, 300.0, 9.0, 1.0};
			add(s);
		}
		// 18. Long March 3B (长征三号乙) — Hypergolic + Hydrolox Stage 3
		{
			RocketVehicleSpec s;
			s.id = QStringLiteral("cz3b");
			s.nameZh = QStringLiteral("长征三号乙 (CZ-3B)");
			s.nameEn = QStringLiteral("Long March 3B");
			s.family = QStringLiteral("Long March");
			s.propellantClass = QStringLiteral("hypergolic");
			s.plumeTypeZh = QStringLiteral("常温主级 + 三级液氢高空羽流");
			s.plumeTypeEn = QStringLiteral("Hypergolic Core + Hydrolox Stage 3 Plume");
			s.summaryZh = QStringLiteral("西昌高轨主力火箭，4台助推+一二级常规液体，三级液氢液氧，南方多省夜空常可见。");
			s.summaryEn = QStringLiteral("Xichang GTO workhorse with hypergolic lower stages and hydrolox third stage.");
			s.payloadMassKg = 5500.0; s.fairingMassKg = 1800.0; s.fairingSepSec = 215.0; s.fairingAreaM2 = 12.6;
			s.kickStartSec = 11.0; s.kickDurationSec = 14.0; s.kickAngleDeg = 4.3; s.stage2TargetPitchDeg = 6.0;
			s.hasBoosters = true; s.boosterCount = 4;
			s.booster = {QStringLiteral("4×液体助推器"), QStringLiteral("4x Boosters"), QStringLiteral("hypergolic"), 14000.0, 150000.0, 2960e3, 3260e3, 140.0, 16.0, 1.15};
			s.stage1 = {QStringLiteral("芯一级"), QStringLiteral("Core Stage 1"), QStringLiteral("hypergolic"), 13500.0, 171000.0, 2960e3, 3260e3, 158.0, 9.0, 1.1};
			s.stage2 = {QStringLiteral("芯二级"), QStringLiteral("Stage 2"), QStringLiteral("hypergolic"), 4500.0, 49000.0, 680e3, 742e3, 185.0, 9.0, 1.0};
			s.hasStage3 = true;
			s.stage3 = {QStringLiteral("芯三级 (2×YF-75 液氢液氧)"), QStringLiteral("Stage 3 Hydrolox"), QStringLiteral("hydrolox"), 2800.0, 18200.0, 140e3, 167e3, 390.0, 7.1, 1.0};
			add(s);
		}
		// 19. Long March 4B (长征四号乙) — Hypergolic
		{
			RocketVehicleSpec s;
			s.id = QStringLiteral("cz4b");
			s.nameZh = QStringLiteral("长征四号乙 (CZ-4B)");
			s.nameEn = QStringLiteral("Long March 4B");
			s.family = QStringLiteral("Long March");
			s.propellantClass = QStringLiteral("hypergolic");
			s.plumeTypeZh = QStringLiteral("三级常温液体（高空水母与脉冲光团）");
			s.plumeTypeEn = QStringLiteral("3-Stage Hypergolic Twilight Plume");
			s.summaryZh = QStringLiteral("太原/酒泉经典太阳同步轨道三级常规火箭，三级关机高度高、暮光视野覆盖广。");
			s.summaryEn = QStringLiteral("3-stage hypergolic SSO launcher frequently flying from Taiyuan and Jiuquan.");
			s.payloadMassKg = 4200.0; s.fairingMassKg = 1100.0; s.fairingSepSec = 195.0; s.fairingAreaM2 = 9.0;
			s.kickStartSec = 10.0; s.kickDurationSec = 13.0; s.kickAngleDeg = 4.5; s.stage2TargetPitchDeg = 5.5;
			s.stage1 = {QStringLiteral("一级"), QStringLiteral("Stage 1"), QStringLiteral("hypergolic"), 13000.0, 183000.0, 2960e3, 3260e3, 155.0, 9.0, 1.1};
			s.stage2 = {QStringLiteral("二级"), QStringLiteral("Stage 2"), QStringLiteral("hypergolic"), 4200.0, 35500.0, 680e3, 742e3, 130.0, 9.0, 1.0};
			s.hasStage3 = true;
			s.stage3 = {QStringLiteral("三级 (2×YF-40)"), QStringLiteral("Stage 3"), QStringLiteral("hypergolic"), 1800.0, 14000.0, 90e3, 100e3, 320.0, 6.6, 1.0};
			add(s);
		}
		// 20. Long March 4C (长征四号丙) — Hypergolic
		{
			RocketVehicleSpec s;
			s.id = QStringLiteral("cz4c");
			s.nameZh = QStringLiteral("长征四号丙 (CZ-4C)");
			s.nameEn = QStringLiteral("Long March 4C");
			s.family = QStringLiteral("Long March");
			s.propellantClass = QStringLiteral("hypergolic");
			s.plumeTypeZh = QStringLiteral("三级常温液体（二次点火高空光团）");
			s.plumeTypeEn = QStringLiteral("3-Stage Hypergolic with Restartable Upper Stage");
			s.summaryZh = QStringLiteral("具备三级二次启动能力的太阳同步轨道主力箭型，暮光段可见明显羽流与光团。");
			s.summaryEn = QStringLiteral("Restartable 3-stage hypergolic SSO launcher.");
			s.payloadMassKg = 4200.0; s.fairingMassKg = 1100.0; s.fairingSepSec = 195.0; s.fairingAreaM2 = 9.0;
			s.kickStartSec = 10.0; s.kickDurationSec = 13.0; s.kickAngleDeg = 4.5; s.stage2TargetPitchDeg = 5.5;
			s.stage1 = {QStringLiteral("一级"), QStringLiteral("Stage 1"), QStringLiteral("hypergolic"), 13000.0, 183000.0, 2960e3, 3260e3, 155.0, 9.0, 1.1};
			s.stage2 = {QStringLiteral("二级"), QStringLiteral("Stage 2"), QStringLiteral("hypergolic"), 4200.0, 35500.0, 680e3, 742e3, 130.0, 9.0, 1.0};
			s.hasStage3 = true;
			s.stage3 = {QStringLiteral("三级 (YF-40A)"), QStringLiteral("Stage 3"), QStringLiteral("hypergolic"), 1850.0, 14200.0, 90e3, 101e3, 330.0, 6.6, 1.0};
			add(s);
		}
		// 21. Falcon 9 Block 5 — Kerolox (the iconic space jellyfish benchmark)
		{
			RocketVehicleSpec s;
			s.id = QStringLiteral("f9");
			s.nameZh = QStringLiteral("猎鹰 9 号 (Falcon 9)");
			s.nameEn = QStringLiteral("Falcon 9 Block 5");
			s.family = QStringLiteral("SpaceX");
			s.propellantClass = QStringLiteral("kerolox");
			s.plumeTypeZh = QStringLiteral("标杆级液氧煤油太空水母");
			s.plumeTypeEn = QStringLiteral("Iconic Kerolox Space Jellyfish");
			s.summaryZh = QStringLiteral("两级液氧煤油可回收火箭，范登堡/卡角日落后常制造全网刷屏的巨型发光水母与脉冲光环。");
			s.summaryEn = QStringLiteral("Two-stage kerolox launcher famous for massive twilight space jellyfish over California & Florida.");
			s.payloadMassKg = 17500.0; s.fairingMassKg = 1900.0; s.fairingSepSec = 195.0; s.fairingAreaM2 = 21.2;
			s.kickStartSec = 10.0; s.kickDurationSec = 14.0; s.kickAngleDeg = 4.4; s.stage2TargetPitchDeg = 5.0;
			s.stage1 = {QStringLiteral("一级 (9×Merlin 1D)"), QStringLiteral("Stage 1 (9x Merlin 1D)"), QStringLiteral("kerolox"), 27200.0, 411000.0, 7607e3, 8227e3, 162.0, 10.8, 1.05};
			s.stage2 = {QStringLiteral("二级 (MVac)"), QStringLiteral("Stage 2 (Merlin Vacuum)"), QStringLiteral("kerolox"), 4500.0, 107500.0, 820e3, 981e3, 360.0, 10.8, 1.0};
			add(s);
		}
		// 22. Starship / Super Heavy — Methalox
		{
			RocketVehicleSpec s;
			s.id = QStringLiteral("starship");
			s.nameZh = QStringLiteral("星舰 (Starship / Super Heavy)");
			s.nameEn = QStringLiteral("Starship / Super Heavy");
			s.family = QStringLiteral("SpaceX");
			s.propellantClass = QStringLiteral("methalox");
			s.plumeTypeZh = QStringLiteral("超重型液氧甲烷巨型冰蓝水母");
			s.plumeTypeEn = QStringLiteral("Super-Heavy Ice-Blue Methalox Jellyfish");
			s.summaryZh = QStringLiteral("超重型全液氧甲烷组合体，热分离与二级 6 台猛禽高空点火形成超大尺度冰蓝/珍珠白羽流。");
			s.summaryEn = QStringLiteral("Super-heavy all-methalox stack generating giant ice-blue high-altitude plumes.");
			s.payloadMassKg = 100000.0; s.fairingMassKg = 0.0; s.fairingSepSec = 9999.0; s.fairingAreaM2 = 0.0;
			s.kickStartSec = 12.0; s.kickDurationSec = 16.0; s.kickAngleDeg = 4.2; s.stage2TargetPitchDeg = 5.0;
			s.stage1 = {QStringLiteral("超重助推器 (33×Raptor)"), QStringLiteral("Super Heavy (33x Raptor)"), QStringLiteral("methalox"), 240000.0, 3400000.0, 74400e3, 80000e3, 165.0, 63.6, 1.1};
			s.stage2 = {QStringLiteral("星舰二级 (6×Raptor)"), QStringLiteral("Starship Upper Stage"), QStringLiteral("methalox"), 120000.0, 1200000.0, 12000e3, 14700e3, 360.0, 63.6, 1.0};
			add(s);
		}
		return v;
	}();
	return kVehicles;
}

const QVector<RocketLaunchPreset>& RocketLaunchMgr::presets()
{
	static const QVector<RocketLaunchPreset> kPresets = {
		{
			QStringLiteral("preset_cz6a_taiyuan_twilight"),
			QStringLiteral("长征六号改 · 太原暮光双形态火箭云"),
			QStringLiteral("CZ-6A · Taiyuan Twilight Hybrid Plume"),
			QStringLiteral("发射预演 · 固液混合"),
			QStringLiteral("Launch Sim · Hybrid Plume"),
			QStringLiteral("tslc"),
			QStringLiteral("cz6a"),
			QStringLiteral("2026-11-28T10:15:00Z"),
			255.4,
			8.4,
			QStringLiteral("SSO 500 km"),
			QStringLiteral("太原暮光发射窗口预演（附 A5283/26 助推器 NOTAM 落区模型）：前 114 秒 4 台固体助推器在低中空留出扭曲亮白烟带，助推分离后液氧煤油芯级跃出地影展开青白水母。"),
			QStringLiteral("Taiyuan twilight launch simulation with A5283/26 booster NOTAM: 4 solid boosters lay a luminous twisted ribbon before the kerolox core blooms into a high-altitude jellyfish."),
			QStringLiteral("A5283/26 NOTAMN\nQ) ZLHW/QRTCA/IV/BO/W/000/999/3800N10745E012\nA) ZLHW B) 2611281009 C) 2611281047\nE) A TEMPORARY RESTRICTED AREA ESTABLISHED BOUNDED BY:\nN3802E10729-N3808E10756-N3757E10800-N3751E10733 BACK TO START.")
		},
		{
			QStringLiteral("preset_kz1a_jiuquan_ribbon"),
			QStringLiteral("快舟一号甲 · 酒泉固体扭曲白蛇彩带"),
			QStringLiteral("KZ-1A · Jiuquan Solid Twisted Ribbon"),
			QStringLiteral("发射预演 · 固体彩带"),
			QStringLiteral("Launch Sim · Solid Ribbon"),
			QStringLiteral("jslc"),
			QStringLiteral("kz1a"),
			QStringLiteral("2026-11-30T09:50:00Z"),
			162.0,
			-1.0,
			QStringLiteral("SSO 520 km"),
			QStringLiteral("黄昏民用暮光窗口发射的典型固体箭案例：平流层高空风切变把氧化铝颗粒尾迹吹成耀眼的 S 形金白彩带，华北与西北大部可持续观测 20 分钟以上。"),
			QStringLiteral("Dusk civil-twilight solid rocket simulation demonstrating long-lived wind-sheared golden-white Al2O3 ribbons."),
			QString()
		},
		{
			QStringLiteral("preset_cz7_wenchang_jellyfish"),
			QStringLiteral("长征七号 · 文昌液氧煤油太空水母"),
			QStringLiteral("CZ-7 · Wenchang Kerolox Space Jellyfish"),
			QStringLiteral("发射预演 · 液氧煤油"),
			QStringLiteral("Launch Sim · Kerolox"),
			QStringLiteral("wslc"),
			QStringLiteral("cz7"),
			QStringLiteral("2026-12-03T10:20:00Z"),
			106.0,
			-1.0,
			QStringLiteral("LEO 390 km (CSS)"),
			QStringLiteral("文昌日落后约 40 分钟航海暮光发射：低空羽流相对克制，进入 85–210 km 跃出地球阴影后剧烈膨胀成半透明青白巨型水母。"),
			QStringLiteral("Nautical-twilight Wenchang launch showcasing dramatic under-expanded kerolox jellyfish illumination above 85 km."),
			QString()
		},
		{
			QStringLiteral("preset_zq2e_jiuquan_methalox"),
			QStringLiteral("朱雀二号改进型 · 酒泉液氧甲烷冰蓝水母"),
			QStringLiteral("Zhuque-2E · Jiuquan Methalox Ice-Blue Plume"),
			QStringLiteral("发射预演 · 液氧甲烷"),
			QStringLiteral("Launch Sim · Methalox"),
			QStringLiteral("jslc"),
			QStringLiteral("zq2e"),
			QStringLiteral("2026-12-08T10:32:00Z"),
			168.0,
			-1.0,
			QStringLiteral("SSO 500 km"),
			QStringLiteral("全液氧甲烷推进，低空尾焰蓝紫洁净无烟，进入高空阳光区后呈现极具通透感的冰蓝—银白色水母罩。"),
			QStringLiteral("All-methalox twilight ascent producing a crystal-clear ice-blue plume above 80 km."),
			QString()
		},
		{
			QStringLiteral("preset_cz5_wenchang_hydrolox"),
			QStringLiteral("长征五号 · 文昌液氢液氧高空银白薄纱"),
			QStringLiteral("CZ-5 · Wenchang Hydrolox Pearlescent Veil"),
			QStringLiteral("发射预演 · 液氢液氧"),
			QStringLiteral("Launch Sim · Hydrolox"),
			QStringLiteral("wslc"),
			QStringLiteral("cz5"),
			QStringLiteral("2026-12-14T22:12:00Z"),
			102.0,
			-1.0,
			QStringLiteral("GTO / High Orbit"),
			QStringLiteral("拂晓深暮光窗口：液氢液氧芯级纯水蒸气羽流在 100–250 km 极高空扩散成宽广轻盈的银白薄纱。"),
			QStringLiteral("Pre-dawn twilight heavy-lift launch illustrating wide pearlescent H2O vapor plumes at 100-250 km."),
			QString()
		},
		{
			QStringLiteral("preset_f9_vandenberg_jellyfish"),
			QStringLiteral("猎鹰 9 号 · 范登堡经典加州太空水母"),
			QStringLiteral("Falcon 9 · Vandenberg Iconic Space Jellyfish"),
			QStringLiteral("国际标杆 · 液氧煤油"),
			QStringLiteral("Benchmark · Kerolox"),
			QStringLiteral("vsfb"),
			QStringLiteral("f9"),
			QStringLiteral("2026-12-19T01:45:00Z"),
			178.0,
			-1.0,
			QStringLiteral("LEO 530 km"),
			QStringLiteral("太平洋日落后 35 分钟范登堡南向极轨发射，全球最著名的液氧煤油暮光太空水母基准案例。"),
			QStringLiteral("Post-sunset Vandenberg polar ascent — the global benchmark for twilight kerolox space jellyfish."),
			QString()
		},
	};
	return kPresets;
}

QJsonObject RocketLaunchMgr::catalogToJson()
{
	QJsonArray siteArr;
	for (const auto& s : launchSites())
	{
		QJsonObject o;
		o["id"] = s.id;
		o["nameZh"] = s.nameZh;
		o["nameEn"] = s.nameEn;
		o["code"] = s.code;
		o["country"] = s.country;
		o["latDeg"] = s.latDeg;
		o["lonDeg"] = s.lonDeg;
		o["altM"] = s.altM;
		o["defaultAzimuthDeg"] = s.defaultAzimuthDeg;
		o["isSeaLaunch"] = s.isSeaLaunch;
		siteArr.append(o);
	}

	QJsonArray vehicleArr;
	for (const auto& v : vehicles())
	{
		QJsonObject o;
		o["id"] = v.id;
		o["nameZh"] = v.nameZh;
		o["nameEn"] = v.nameEn;
		o["family"] = v.family;
		o["propellantClass"] = v.propellantClass;
		o["plumeTypeZh"] = v.plumeTypeZh;
		o["plumeTypeEn"] = v.plumeTypeEn;
		o["summaryZh"] = v.summaryZh;
		o["summaryEn"] = v.summaryEn;
		o["hasBoosters"] = v.hasBoosters;
		o["boosterCount"] = v.boosterCount;
		vehicleArr.append(o);
	}

	QJsonArray presetArr;
	for (const auto& p : presets())
	{
		QJsonObject o;
		o["id"] = p.id;
		o["titleZh"] = p.titleZh;
		o["titleEn"] = p.titleEn;
		o["badgeZh"] = p.badgeZh;
		o["badgeEn"] = p.badgeEn;
		o["siteId"] = p.siteId;
		o["vehicleId"] = p.vehicleId;
		o["launchTimeUtc"] = p.launchTimeUtc;
		o["azimuthDeg"] = p.azimuthDeg;
		o["targetOrbit"] = p.targetOrbit;
		o["descriptionZh"] = p.descriptionZh;
		o["descriptionEn"] = p.descriptionEn;
		o["hasNotam"] = !p.sampleNotam.isEmpty();
		presetArr.append(o);
	}

	QJsonObject out;
	out["ok"] = true;
	out["sites"] = siteArr;
	out["vehicles"] = vehicleArr;
	out["presets"] = presetArr;
	return out;
}

RocketNotamZone RocketLaunchMgr::parseNotamText(const QString& text, double padLatDeg, double padLonDeg, bool hasPad)
{
	RocketNotamZone zone;
	const QString upper = text.toUpper().trimmed();
	if (upper.isEmpty())
		return zone;

	// Extract NOTAM ID (e.g. A5283/26)
	static const QRegularExpression idRe(QStringLiteral("\\b([A-Z]\\d{4}/\\d{2})\\b"));
	auto idMatch = idRe.match(upper);
	if (idMatch.hasMatch())
		zone.notamId = idMatch.captured(1);

	// Extract B) / C) UTC timestamps YYMMDDHHMM
	auto parseNotamTime = [](const QString& yymmddhhmm) -> QString {
		if (yymmddhhmm.size() != 10) return QString();
		const int yy = yymmddhhmm.mid(0, 2).toInt();
		const int mo = yymmddhhmm.mid(2, 2).toInt();
		const int dd = yymmddhhmm.mid(4, 2).toInt();
		const int hh = yymmddhhmm.mid(6, 2).toInt();
		const int mi = yymmddhhmm.mid(8, 2).toInt();
		const QDateTime dt(QDate(2000 + yy, mo, dd), QTime(hh, mi, 0), QTimeZone::utc());
		return dt.isValid() ? dt.toString(Qt::ISODate) : QString();
	};
	static const QRegularExpression bRe(QStringLiteral("\\bB\\)\\s*(\\d{10})"));
	static const QRegularExpression cRe(QStringLiteral("\\bC\\)\\s*(\\d{10})"));
	auto bMatch = bRe.match(upper);
	if (bMatch.hasMatch()) zone.validFromUtc = parseNotamTime(bMatch.captured(1));
	auto cMatch = cRe.match(upper);
	if (cMatch.hasMatch()) zone.validToUtc = parseNotamTime(cMatch.captured(1));

	// Extract Q) line circle: e.g. 3800N10745E012 (lat DDMM[NS], lon DDDMM[EW], radius NNN NM)
	static const QRegularExpression qCircleRe(QStringLiteral("(\\d{4})([NS])(\\d{5})([EW])(\\d{3})\\b"));
	auto qMatch = qCircleRe.match(upper);
	if (qMatch.hasMatch())
	{
		double cLat = 0.0, cLon = 0.0;
		const QString coordStr = qMatch.captured(1) + qMatch.captured(2) + qMatch.captured(3) + qMatch.captured(4);
		if (parseNotamCoordToken(coordStr, cLat, cLon))
		{
			const int radiusNm = qMatch.captured(5).toInt();
			zone.hasCircle = true;
			zone.circleLatDeg = cLat;
			zone.circleLonDeg = cLon;
			zone.circleRadiusKm = radiusNm * 1.852;
		}
	}

	// Extract E) section polygon coordinates (exclude Q-line circle coordinates by slicing after E) if present)
	QString body = upper;
	const int eIdx = upper.indexOf(QStringLiteral("E)"));
	if (eIdx >= 0)
		body = upper.mid(eIdx + 2);

	static const QRegularExpression polyTokenRe(QStringLiteral("([NS](?:\\d{6}|\\d{4})\\s*[EW](?:\\d{7}|\\d{5})|(?:\\d{6}|\\d{4})[NS]\\s*(?:\\d{7}|\\d{5})[EW])"));
	auto it = polyTokenRe.globalMatch(body);
	while (it.hasNext())
	{
		const auto m = it.next();
		double la = 0.0, lo = 0.0;
		if (parseNotamCoordToken(m.captured(1).simplified(), la, lo))
		{
			if (!zone.polygonLatLon.isEmpty())
			{
				const auto& prev = zone.polygonLatLon.last();
				if (std::fabs(prev.first - la) < 1e-4 && std::fabs(prev.second - lo) < 1e-4)
					continue;
			}
			zone.polygonLatLon.append({la, lo});
		}
	}
	// Remove closing duplicate vertex if last == first
	if (zone.polygonLatLon.size() >= 4)
	{
		const auto& f = zone.polygonLatLon.first();
		const auto& l = zone.polygonLatLon.last();
		if (std::fabs(f.first - l.first) < 1e-4 && std::fabs(f.second - l.second) < 1e-4)
			zone.polygonLatLon.removeLast();
	}

	if (zone.polygonLatLon.size() >= 3)
	{
		double sumLat = 0.0, sumLon = 0.0;
		for (const auto& pt : zone.polygonLatLon)
		{
			sumLat += pt.first;
			sumLon += pt.second;
		}
		zone.centerLatDeg = sumLat / zone.polygonLatLon.size();
		zone.centerLonDeg = sumLon / zone.polygonLatLon.size();
		zone.valid = true;
	}
	else if (zone.hasCircle)
	{
		zone.centerLatDeg = zone.circleLatDeg;
		zone.centerLonDeg = zone.circleLonDeg;
		zone.valid = true;
	}

	if (zone.valid && hasPad)
	{
		zone.invertedAzimuthDeg = initialBearingDeg(padLatDeg, padLonDeg, zone.centerLatDeg, zone.centerLonDeg);
		zone.downrangeKm = greatCircleDistanceKm(padLatDeg, padLonDeg, zone.centerLatDeg, zone.centerLonDeg);
	}
	return zone;
}

RocketSimulationResult RocketLaunchMgr::simulate(
	const QJsonObject& request,
	double observerLatDeg,
	double observerLonDeg,
	double observerAltM,
	const std::function<double(double)>& horizonLookupDeg)
{
	QElapsedTimer timer;
	timer.start();

	RocketSimulationResult res;
	res.observerLatDeg = observerLatDeg;
	res.observerLonDeg = observerLonDeg;
	res.observerAltM = observerAltM;

	// 1. Resolve preset / site / vehicle / launch time / azimuth / NOTAM
	const QString presetId = request.value(QStringLiteral("presetId")).toString().trimmed();
	const RocketLaunchPreset* matchedPreset = nullptr;
	if (!presetId.isEmpty())
	{
		for (const auto& p : presets())
		{
			if (p.id == presetId)
			{
				matchedPreset = &p;
				break;
			}
		}
	}

	QString siteId = request.value(QStringLiteral("siteId")).toString().trimmed();
	QString vehicleId = request.value(QStringLiteral("vehicleId")).toString().trimmed();
	QString launchTimeUtc = request.value(QStringLiteral("launchTimeUtc")).toString().trimmed();
	QString notamText = request.value(QStringLiteral("notamText")).toString().trimmed();
	bool hasExplicitAz = request.contains(QStringLiteral("azimuthDeg")) && !request.value(QStringLiteral("azimuthDeg")).isNull();
	double azimuthDeg = request.value(QStringLiteral("azimuthDeg")).toDouble(90.0);
	const double timeOffsetMin = clampVal(request.value(QStringLiteral("timeOffsetMin")).toDouble(0.0), -180.0, 180.0);
	const int dispersionSamples = qBound(0, request.value(QStringLiteral("dispersionSamples")).toInt(0), 240);
	double kickAngleOverride = -1.0;

	if (matchedPreset)
	{
		if (siteId.isEmpty()) siteId = matchedPreset->siteId;
		if (vehicleId.isEmpty()) vehicleId = matchedPreset->vehicleId;
		if (launchTimeUtc.isEmpty()) launchTimeUtc = matchedPreset->launchTimeUtc;
		if (!hasExplicitAz) { azimuthDeg = matchedPreset->azimuthDeg; hasExplicitAz = true; }
		if (notamText.isEmpty()) notamText = matchedPreset->sampleNotam;
		kickAngleOverride = matchedPreset->kickAngleDeg;
		res.titleZh = matchedPreset->titleZh;
		res.titleEn = matchedPreset->titleEn;
	}

	// Lookup site
	bool foundSite = false;
	for (const auto& s : launchSites())
	{
		if (s.id == siteId)
		{
			res.site = s;
			foundSite = true;
			break;
		}
	}
	if (!foundSite)
	{
		if (request.contains(QStringLiteral("customSiteLat")) && request.contains(QStringLiteral("customSiteLon")))
		{
			res.site.id = QStringLiteral("custom");
			res.site.nameZh = request.value(QStringLiteral("customSiteName")).toString(QStringLiteral("自定义发射点"));
			res.site.nameEn = request.value(QStringLiteral("customSiteName")).toString(QStringLiteral("Custom Launch Pad"));
			res.site.code = QStringLiteral("CUSTOM");
			res.site.latDeg = request.value(QStringLiteral("customSiteLat")).toDouble();
			res.site.lonDeg = request.value(QStringLiteral("customSiteLon")).toDouble();
			res.site.altM = request.value(QStringLiteral("customSiteAltM")).toDouble(0.0);
			res.site.defaultAzimuthDeg = 90.0;
			foundSite = true;
		}
		else
		{
			res.site = launchSites().first();
			foundSite = true;
		}
	}

	// Lookup vehicle
	bool foundVehicle = false;
	for (const auto& v : vehicles())
	{
		if (v.id == vehicleId)
		{
			res.vehicle = v;
			foundVehicle = true;
			break;
		}
	}
	if (!foundVehicle)
		res.vehicle = vehicles().first();

	if (res.titleZh.isEmpty())
	{
		res.titleZh = QStringLiteral("%1 · %2 弹道仿真").arg(res.vehicle.nameZh, res.site.nameZh);
		res.titleEn = QStringLiteral("%1 · %2 Ascent Simulation").arg(res.vehicle.nameEn, res.site.nameEn);
	}

	// Parse NOTAM if supplied & invert launch azimuth when not explicitly locked
	if (!notamText.isEmpty())
	{
		res.notam = parseNotamText(notamText, res.site.latDeg, res.site.lonDeg, true);
		if (res.notam.valid && res.notam.invertedAzimuthDeg >= 0.0 && !hasExplicitAz)
		{
			azimuthDeg = res.notam.invertedAzimuthDeg;
			hasExplicitAz = true;
		}
	}
	if (!hasExplicitAz)
		azimuthDeg = res.site.defaultAzimuthDeg;
	azimuthDeg = wrap360(azimuthDeg);
	res.launchAzimuthDeg = azimuthDeg;

	// Resolve launch UTC time + timeOffsetMin
	double baseUnixSec = 0.0;
	if (!parseIsoUtcToUnixSec(launchTimeUtc, baseUnixSec))
	{
		if (res.notam.valid && parseIsoUtcToUnixSec(res.notam.validFromUtc, baseUnixSec))
		{
			// Default to 6 minutes into NOTAM window
			baseUnixSec += 360.0;
		}
		else
		{
			baseUnixSec = static_cast<double>(QDateTime::currentSecsSinceEpoch());
		}
	}
	const double launchUnixSec = baseUnixSec + timeOffsetMin * 60.0;
	res.launchTimeUtc = unixSecToIsoUtc(launchUnixSec);
	res.launchJd = unixSecToJd(launchUnixSec);
	res.timeOffsetMin = timeOffsetMin;
	res.simulationId = QStringLiteral("%1_%2_%3").arg(res.site.id, res.vehicle.id).arg(static_cast<qint64>(launchUnixSec));

	// Observer-to-pad distance & observer twilight conditions
	res.distanceToPadKm = greatCircleDistanceKm(observerLatDeg, observerLonDeg, res.site.latDeg, res.site.lonDeg);
	sunAzAltAtObserver(res.launchJd, observerLatDeg, observerLonDeg, res.observerSunAzDeg, res.observerSunAltDeg);
	res.twilightStage = classifyTwilight(res.observerSunAltDeg);

	// Precompute 360-degree horizon obstruction profile (every 2 degrees)
	QVector<double> horizonByAz(180, 0.0);
	for (int i = 0; i < 180; ++i)
	{
		const double az = i * 2.0;
		double hAlt = 0.0;
		if (horizonLookupDeg)
			hAlt = clampVal(horizonLookupDeg(az), 0.0, 60.0);
		horizonByAz[i] = hAlt;
		res.horizonProfile.append({az, hAlt});
	}
	auto lookupHorizon = [&](double azDeg) -> double {
		const double a = wrap360(azDeg) * 0.5;
		const int i0 = static_cast<int>(std::floor(a)) % 180;
		const int i1 = (i0 + 1) % 180;
		const double f = a - std::floor(a);
		return horizonByAz[i0] * (1.0 - f) + horizonByAz[i1] * f;
	};

	// Observer ECEF & local ENU basis
	const Vec3 obsEcef = geodeticToEcef(observerLatDeg, observerLonDeg, observerAltM);
	Vec3 obsE, obsN, obsU;
	localEnuBasis(observerLatDeg, observerLonDeg, obsE, obsN, obsU);

	// 2. Build 3-DOF ascent integration runner (reused cleanly for nominal + dispersion)
	const RocketVehicleSpec& veh = res.vehicle;
	const double nominalKickDeg = (kickAngleOverride > 0.0) ? kickAngleOverride : veh.kickAngleDeg;
	const double tBoosterBurn = veh.hasBoosters ? veh.booster.burnTimeSec : 0.0;
	const double tBoosterSep = veh.hasBoosters ? (tBoosterBurn + 2.0) : -1.0;
	const double tMeco = veh.stage1.burnTimeSec;
	const double tStageSep = tMeco + 2.0;
	const double tStage2End = tStageSep + veh.stage2.burnTimeSec;
	const double tStage3Start = veh.hasStage3 ? (tStage2End + 3.0) : -1.0;
	const double tSeco = veh.hasStage3 ? (tStage3Start + veh.stage3.burnTimeSec) : tStage2End;
	const double tSimEnd = std::min(1100.0, tSeco + 60.0);

	// Helper to run one ascent pass (nominal records full trajectory & all debris; dispersion only runs up to target separation!)
	struct AscentRunOut
	{
		Vec3 boosterSepR, boosterSepV;
		bool hasBoosterSepState = false;
		Vec3 fairingSepR, fairingSepV;
		bool hasFairingSepState = false;
		Vec3 stage1SepR, stage1SepV;
		bool hasStage1SepState = false;
		double maxQVal = 0.0;
		double maxQTime = 0.0;
		Vec3 maxQR, maxQV;
	};

	auto runAscent = [&](
		bool nominal,
		double azDegRun,
		double thrustScale,
		double kickDegRun,
		double boosterSepDeltaSec,
		double windEastMS,
		double windNorthMS,
		AscentRunOut& runOut)
	{
		Vec3 r = geodeticToEcef(res.site.latDeg, res.site.lonDeg, res.site.altM);
		Vec3 v{0.0, 0.0, 0.0};
		const Vec3 omegaVec{0.0, 0.0, kEarthOmega};

		// Compute initial stacked wet mass
		double mBoosterProp = veh.hasBoosters ? veh.booster.propMassKg : 0.0;
		double mBoosterDry = veh.hasBoosters ? veh.booster.dryMassKg : 0.0;
		double mS1Prop = veh.stage1.propMassKg;
		double mS1Dry = veh.stage1.dryMassKg;
		double mS2Prop = veh.stage2.propMassKg;
		double mS2Dry = veh.stage2.dryMassKg;
		double mS3Prop = veh.hasStage3 ? veh.stage3.propMassKg : 0.0;
		double mS3Dry = veh.hasStage3 ? veh.stage3.dryMassKg : 0.0;
		double mFairing = veh.fairingMassKg;
		double mPayload = veh.payloadMassKg;

		bool boostersAttached = veh.hasBoosters;
		bool stage1Attached = true;
		bool fairingAttached = (veh.fairingMassKg > 0.0 && veh.fairingSepSec < 5000.0);
		bool stage2Attached = true;

		const double tBEnd = veh.hasBoosters ? std::max(10.0, tBoosterBurn + boosterSepDeltaSec) : 0.0;
		const double tBSep = veh.hasBoosters ? (tBEnd + 2.0) : -1.0;
		const double stopTime = nominal ? tSimEnd : (veh.hasBoosters ? (tBSep + 1.0) : (tStageSep + 1.0));

		double stage2InitPitchDeg = 28.0;
		bool stage2InitCaptured = false;

		auto currentMass = [&]() -> double {
			return mPayload
				+ (fairingAttached ? mFairing : 0.0)
				+ (veh.hasStage3 ? (mS3Dry + mS3Prop) : 0.0)
				+ (stage2Attached ? (mS2Dry + mS2Prop) : 0.0)
				+ (stage1Attached ? (mS1Dry + mS1Prop) : 0.0)
				+ (boostersAttached ? (mBoosterDry + mBoosterProp) : 0.0);
		};

		auto computeThrustAndState = [&](
			double t,
			const Vec3& pos,
			const Vec3& vel,
			double mass,
			int& outPhase,
			QString& outProp,
			double& outQPa,
			double& outAccelG,
			bool& outBurning) -> Vec3
		{
			double la = 0.0, lo = 0.0, alt = 0.0;
			ecefToGeodetic(pos, la, lo, alt);
			Vec3 e, n, u;
			localEnuBasis(la, lo, e, n, u);
			const double azRad = azDegRun * kDeg2Rad;
			const Vec3 horiz = n * std::cos(azRad) + e * std::sin(azRad);

			const AtmosSample atm = us76Atmosphere(alt);
			const double pFrac = clampVal(atm.pressurePa / kP0, 0.0, 1.0);

			double thrustN = 0.0;
			double refArea = veh.stage1.refAreaM2;
			outPhase = 4;
			outProp = veh.stage2.propellant;
			outBurning = false;

			if (t < tMeco && mS1Prop > 0.0)
			{
				const double s1T = (veh.stage1.thrustVacN - (veh.stage1.thrustVacN - veh.stage1.thrustSLN) * pFrac) * thrustScale;
				thrustN += s1T;
				outBurning = true;
				if (veh.hasBoosters && t < tBEnd && mBoosterProp > 0.0)
				{
					const double bT = (veh.booster.thrustVacN - (veh.booster.thrustVacN - veh.booster.thrustSLN) * pFrac) * thrustScale;
					thrustN += bT;
					refArea = veh.stage1.refAreaM2 + veh.booster.refAreaM2;
					outPhase = 0;
					outProp = veh.booster.propellant; // solid for CZ-6A, kerolox for CZ-7, etc.
				}
				else
				{
					outPhase = 1;
					outProp = veh.stage1.propellant;
				}
			}
			else if (t >= tStageSep && t < tStage2End && mS2Prop > 0.0)
			{
				thrustN = (veh.stage2.thrustVacN - (veh.stage2.thrustVacN - veh.stage2.thrustSLN) * pFrac) * thrustScale;
				refArea = veh.stage2.refAreaM2;
				outPhase = 2;
				outProp = veh.stage2.propellant;
				outBurning = true;
			}
			else if (veh.hasStage3 && t >= tStage3Start && t < tSeco && mS3Prop > 0.0)
			{
				thrustN = (veh.stage3.thrustVacN - (veh.stage3.thrustVacN - veh.stage3.thrustSLN) * pFrac) * thrustScale;
				refArea = veh.stage3.refAreaM2;
				outPhase = 3;
				outProp = veh.stage3.propellant;
				outBurning = true;
			}

			// Thrust unit direction (gravity turn + smooth upper-stage orbital insertion pitch)
			Vec3 thrustDir = u;
			if (t < veh.kickStartSec)
			{
				thrustDir = u;
			}
			else if (t < veh.kickStartSec + veh.kickDurationSec)
			{
				const double frac = (t - veh.kickStartSec) / std::max(1.0, veh.kickDurationSec);
				const double tiltRad = (kickDegRun * frac) * kDeg2Rad;
				thrustDir = normalized(u * std::cos(tiltRad) + horiz * std::sin(tiltRad));
			}
			else if (t < tStageSep)
			{
				// Gravity turn following velocity projected onto launch plane, with minimum pitch floor
				const double vUp = dot(vel, u);
				const double vH = std::max(1.0, dot(vel, horiz));
				double pitchDeg = std::atan2(vUp, vH) * kRad2Deg;
				const double minPitch = (alt < 45000.0) ? 24.0 : 14.0;
				pitchDeg = clampVal(pitchDeg, minPitch, 86.0);
				const double pRad = pitchDeg * kDeg2Rad;
				thrustDir = normalized(u * std::sin(pRad) + horiz * std::cos(pRad));
			}
			else
			{
				// Smooth linear pitch-down in vacuum stage 2/3 toward orbital insertion
				const double prog = clampVal((t - tStageSep) / std::max(30.0, tSeco - tStageSep), 0.0, 1.0);
				double targetPitch = stage2InitPitchDeg * (1.0 - prog) + veh.stage2TargetPitchDeg * prog;
				// Gently level off if altitude already high (> 380 km)
				if (alt > 380000.0) targetPitch = std::min(targetPitch, 0.0);
				const double pRad = targetPitch * kDeg2Rad;
				thrustDir = normalized(u * std::sin(pRad) + horiz * std::cos(pRad));
			}

			// Wind + aerodynamic drag
			const double windScale = (alt < 45000.0) ? std::exp(-std::pow((alt - 12000.0) / 14000.0, 2.0)) : 0.0;
			const Vec3 vWind = e * (windEastMS * windScale) + n * (windNorthMS * windScale);
			const Vec3 vRel = vel - vWind;
			const double spd = norm(vRel);
			const double mach = spd / std::max(100.0, atm.soundSpeedMS);
			const double cd = rocketDragCoeff(mach);
			outQPa = 0.5 * atm.densityKgM3 * spd * spd;

			Vec3 dragAcc{0.0, 0.0, 0.0};
			if (spd > 1e-3 && outQPa > 1e-6)
				dragAcc = (vRel / spd) * (-(outQPa * cd * refArea) / mass);

			const Vec3 thrustAcc = thrustDir * (thrustN / mass);
			outAccelG = norm(thrustAcc + dragAcc) / kG0;

			// Total ECEF acceleration = gravity(J2) + thrust + drag - Coriolis - centrifugal
			return gravityJ2Ecef(pos) + thrustAcc + dragAcc
				- cross(omegaVec, vel) * 2.0
				- cross(omegaVec, cross(omegaVec, pos));
		};

		const double dt = 0.5;
		const int maxSteps = static_cast<int>(std::ceil(stopTime / dt));
		bool recordedBoosterCutoff = false;
		bool recordedBoosterSep = false;
		bool recordedFairingSep = false;
		bool recordedMeco = false;
		bool recordedStageSep = false;
		bool recordedSeco = false;

		auto recordSampleAndCheckEvents = [&](double t, const Vec3& pos, const Vec3& vel, int phase, const QString& prop, double qPa, double accelG, bool burning) {
			if (!nominal) return;
			double la = 0.0, lo = 0.0, alt = 0.0;
			ecefToGeodetic(pos, la, lo, alt);
			const double altKm = std::max(0.0, alt / 1000.0);
			const double speedKmS = norm(vel) / 1000.0;
			const double downrangeKm = greatCircleDistanceKm(res.site.latDeg, res.site.lonDeg, la, lo);

			// Observer ENU -> Az/Alt/Range
			const Vec3 rel = pos - obsEcef;
			const double rangeM = norm(rel);
			const double rangeKm = rangeM / 1000.0;
			const double re = dot(rel, obsE);
			const double rn = dot(rel, obsN);
			const double ru = dot(rel, obsU);
			const double azDeg = wrap360(std::atan2(re, rn) * kRad2Deg);
			const double altDeg = (rangeM > 1.0) ? (std::asin(clampVal(ru / rangeM, -1.0, 1.0)) * kRad2Deg) : 90.0;
			const double horAlt = lookupHorizon(azDeg);
			const bool aboveHor = (altDeg > horAlt);

			// Earth shadow tangent altitude h_eff
			const double curJd = res.launchJd + t / 86400.0;
			const Vec3 sunDir = sunDirectionEcef(curJd);
			const double proj = dot(pos, sunDir);
			double hEffKm = altKm;
			QString sunlitState = QStringLiteral("daylit");
			if (proj < 0.0)
			{
				const Vec3 perp = pos - sunDir * proj;
				hEffKm = (norm(perp) - kEarthMeanR) / 1000.0;
				if (hEffKm <= 0.0) sunlitState = QStringLiteral("umbra");
				else if (hEffKm <= 25.0) sunlitState = QStringLiteral("red_twilight");
				else sunlitState = QStringLiteral("sunlit");
			}

			double pW = 0.0, pAng = 0.0, pBright = 0.0, pR = 1.0, pG = 1.0, pB = 1.0;
			evaluatePlumePhysics(prop, altKm, rangeKm, altDeg, res.observerSunAltDeg, hEffKm, burning, pW, pAng, pBright, pR, pG, pB);

			// Stratospheric wind shear drift proxy (realistic S-curve drift for solid trails)
			const double shearFactor = std::sin(altKm * 0.14) * std::exp(-std::pow((altKm - 42.0) / 30.0, 2.0));
			const double driftEastKm = (prop == QLatin1String("solid")) ? (shearFactor * 8.5) : 0.0;
			const double driftNorthKm = (prop == QLatin1String("solid")) ? (std::cos(altKm * 0.11) * std::exp(-std::pow((altKm - 48.0) / 32.0, 2.0)) * 4.5) : 0.0;

			RocketTrajectorySample smp;
			smp.tSec = t;
			smp.phaseIndex = phase;
			smp.activePropellant = prop;
			smp.latDeg = la;
			smp.lonDeg = lo;
			smp.altKm = altKm;
			smp.speedKmS = speedKmS;
			smp.downrangeKm = downrangeKm;
			smp.dynamicPressureKPa = qPa / 1000.0;
			smp.accelG = accelG;
			smp.azDeg = azDeg;
			smp.altDeg = altDeg;
			smp.rangeKm = rangeKm;
			smp.horizonAltDeg = horAlt;
			smp.aboveHorizon = aboveHor;
			smp.shadowTangentAltKm = hEffKm;
			smp.sunlitState = sunlitState;
			smp.plumeWidthKm = pW;
			smp.plumeAngularDeg = pAng;
			smp.plumeBrightness = pBright;
			smp.plumeR = pR;
			smp.plumeG = pG;
			smp.plumeB = pB;
			smp.plumeVisible = aboveHor && (pBright >= 0.14);
			smp.windDriftEastKm = driftEastKm;
			smp.windDriftNorthKm = driftNorthKm;
			res.trajectory.append(smp);
		};

		auto pushEvent = [&](const QString& code, const QString& zh, const QString& en, double t, const Vec3& pos, const Vec3& vel) {
			if (!nominal) return;
			double la = 0.0, lo = 0.0, alt = 0.0;
			ecefToGeodetic(pos, la, lo, alt);
			const Vec3 rel = pos - obsEcef;
			const double rM = norm(rel);
			RocketFlightEvent ev;
			ev.code = code;
			ev.labelZh = zh;
			ev.labelEn = en;
			ev.tSec = t;
			ev.latDeg = la;
			ev.lonDeg = lo;
			ev.altKm = std::max(0.0, alt / 1000.0);
			ev.speedKmS = norm(vel) / 1000.0;
			ev.rangeKm = rM / 1000.0;
			ev.azDeg = wrap360(std::atan2(dot(rel, obsE), dot(rel, obsN)) * kRad2Deg);
			ev.altDeg = (rM > 1.0) ? (std::asin(clampVal(dot(rel, obsU) / rM, -1.0, 1.0)) * kRad2Deg) : 90.0;
			res.events.append(ev);
		};

		pushEvent(QStringLiteral("LIFTOFF"), QStringLiteral("点火起飞"), QStringLiteral("Liftoff"), 0.0, r, v);

		for (int step = 0; step <= maxSteps; ++step)
		{
			const double t = step * dt;
			const double m = currentMass();
			int phase = 0;
			QString prop;
			double qPa = 0.0, accelG = 0.0;
			bool burning = false;
			const Vec3 aNow = computeThrustAndState(t, r, v, m, phase, prop, qPa, accelG, burning);

			if (qPa > runOut.maxQVal)
			{
				runOut.maxQVal = qPa;
				runOut.maxQTime = t;
				runOut.maxQR = r;
				runOut.maxQV = v;
			}

			// Record trajectory at 2s cadence (and 1s during first 60s for crisp liftoff arc)
			const bool shouldSample = (t <= 60.0) ? (step % 2 == 0) : (step % 4 == 0);
			if (nominal && (shouldSample || step == maxSteps))
				recordSampleAndCheckEvents(t, r, v, phase, prop, qPa, accelG, burning);

			// Staging & separation events
			if (veh.hasBoosters && !recordedBoosterCutoff && t >= tBEnd)
			{
				recordedBoosterCutoff = true;
				mBoosterProp = 0.0;
				pushEvent(QStringLiteral("BOOSTER_CUTOFF"), QStringLiteral("助推器关机"), QStringLiteral("Booster Cutoff"), t, r, v);
			}
			if (veh.hasBoosters && !recordedBoosterSep && t >= tBSep)
			{
				recordedBoosterSep = true;
				boostersAttached = false;
				runOut.hasBoosterSepState = true;
				runOut.boosterSepR = r;
				runOut.boosterSepV = v;
				pushEvent(QStringLiteral("BOOSTER_SEP"), QStringLiteral("助推器分离"), QStringLiteral("Booster Separation"), t, r, v);
			}
			if (fairingAttached && !recordedFairingSep && t >= veh.fairingSepSec)
			{
				recordedFairingSep = true;
				fairingAttached = false;
				runOut.hasFairingSepState = true;
				runOut.fairingSepR = r;
				runOut.fairingSepV = v;
				pushEvent(QStringLiteral("FAIRING_SEP"), QStringLiteral("整流罩分离"), QStringLiteral("Fairing Separation"), t, r, v);
			}
			if (!recordedMeco && t >= tMeco)
			{
				recordedMeco = true;
				mS1Prop = 0.0;
				pushEvent(QStringLiteral("MECO"), QStringLiteral("一级关机 (MECO)"), QStringLiteral("MECO"), t, r, v);
			}
			if (!recordedStageSep && t >= tStageSep)
			{
				recordedStageSep = true;
				stage1Attached = false;
				runOut.hasStage1SepState = true;
				runOut.stage1SepR = r;
				runOut.stage1SepV = v;
				pushEvent(QStringLiteral("STAGE_SEP"), QStringLiteral("一二级分离"), QStringLiteral("Stage Separation"), t, r, v);

				// Capture pitch angle at stage-2 ignition for smooth continuation
				double la = 0.0, lo = 0.0, alt = 0.0;
				ecefToGeodetic(r, la, lo, alt);
				Vec3 e, n, u;
				localEnuBasis(la, lo, e, n, u);
				const Vec3 horiz = n * std::cos(azDegRun * kDeg2Rad) + e * std::sin(azDegRun * kDeg2Rad);
				stage2InitPitchDeg = clampVal(std::atan2(dot(v, u), std::max(1.0, dot(v, horiz))) * kRad2Deg, 10.0, 42.0);
				stage2InitCaptured = true;
				Q_UNUSED(stage2InitCaptured)
			}
			if (!recordedSeco && t >= tSeco)
			{
				recordedSeco = true;
				mS2Prop = 0.0;
				mS3Prop = 0.0;
				pushEvent(QStringLiteral("SECO"), QStringLiteral("入轨关机 (SECO)"), QStringLiteral("SECO / Orbit Insertion"), t, r, v);
			}

			if (step == maxSteps) break;

			// RK4 integration step
			int pTmp = 0; QString propTmp; double qTmp = 0.0, gTmp = 0.0; bool bTmp = false;
			const Vec3 k1r = v;
			const Vec3 k1v = aNow;
			const Vec3 k2r = v + k1v * (0.5 * dt);
			const Vec3 k2v = computeThrustAndState(t + 0.5 * dt, r + k1r * (0.5 * dt), k2r, m, pTmp, propTmp, qTmp, gTmp, bTmp);
			const Vec3 k3r = v + k2v * (0.5 * dt);
			const Vec3 k3v = computeThrustAndState(t + 0.5 * dt, r + k2r * (0.5 * dt), k3r, m, pTmp, propTmp, qTmp, gTmp, bTmp);
			const Vec3 k4r = v + k3v * dt;
			const Vec3 k4v = computeThrustAndState(t + dt, r + k3r * dt, k4r, m, pTmp, propTmp, qTmp, gTmp, bTmp);

			r = r + (k1r + k2r * 2.0 + k3r * 2.0 + k4r) * (dt / 6.0);
			v = v + (k1v + k2v * 2.0 + k3v * 2.0 + k4v) * (dt / 6.0);

			// Consume propellant for active stages
			if (t < tMeco && mS1Prop > 0.0)
				mS1Prop = std::max(0.0, mS1Prop - (veh.stage1.propMassKg / std::max(1.0, veh.stage1.burnTimeSec)) * dt);
			if (veh.hasBoosters && t < tBEnd && mBoosterProp > 0.0)
				mBoosterProp = std::max(0.0, mBoosterProp - (veh.booster.propMassKg / std::max(1.0, veh.booster.burnTimeSec)) * dt);
			if (t >= tStageSep && t < tStage2End && mS2Prop > 0.0)
				mS2Prop = std::max(0.0, mS2Prop - (veh.stage2.propMassKg / std::max(1.0, veh.stage2.burnTimeSec)) * dt);
			if (veh.hasStage3 && t >= tStage3Start && t < tSeco && mS3Prop > 0.0)
				mS3Prop = std::max(0.0, mS3Prop - (veh.stage3.propMassKg / std::max(1.0, veh.stage3.burnTimeSec)) * dt);

			// Stop early if vehicle ever falls below ground (impossible for nominal)
			double laChk = 0.0, loChk = 0.0, altChk = 0.0;
			ecefToGeodetic(r, laChk, loChk, altChk);
			if (t > 15.0 && altChk < -100.0) break;
		}
	};

	// Run NOTAM kick-angle auto-inversion if a valid NOTAM drop zone is supplied (5-step bisection, ~3 ms)
	double effectiveKickDeg = nominalKickDeg;
	if (res.notam.valid && res.notam.downrangeKm > 40.0 && res.notam.downrangeKm < 2200.0)
	{
		double loKick = 1.5;
		double hiKick = 24.0;
		auto probeDownrange = [&](double kDeg) -> double {
			AscentRunOut pOut;
			runAscent(false, azimuthDeg, 1.0, kDeg, 0.0, 0.0, 0.0, pOut);
			if (veh.hasBoosters && pOut.hasBoosterSepState)
			{
				const double mB = veh.booster.dryMassKg / std::max(1, veh.boosterCount);
				const double aB = veh.booster.refAreaM2 / std::max(1, veh.boosterCount);
				return simulateDebrisFallback(QStringLiteral("booster"), QString(), QString(),
					tBoosterSep, launchUnixSec, pOut.boosterSepR, pOut.boosterSepV,
					mB, veh.booster.debrisCd, aB * 1.4, res.site, res.notam, 0.0, 0.0, false).downrangeKm;
			}
			if (pOut.hasStage1SepState)
			{
				return simulateDebrisFallback(QStringLiteral("stage1"), QString(), QString(),
					tStageSep, launchUnixSec, pOut.stage1SepR, pOut.stage1SepV,
					veh.stage1.dryMassKg, veh.stage1.debrisCd, veh.stage1.refAreaM2 * 1.5,
					res.site, res.notam, 0.0, 0.0, false).downrangeKm;
			}
			return -1.0;
		};
		const double drLo = probeDownrange(loKick);
		const double drHi = probeDownrange(hiKick);
		if (drLo > 0.0 && drHi > drLo && res.notam.downrangeKm >= drLo * 0.85 && res.notam.downrangeKm <= drHi * 1.15)
		{
			for (int it = 0; it < 6; ++it)
			{
				const double mid = 0.5 * (loKick + hiKick);
				const double drMid = probeDownrange(mid);
				if (drMid < res.notam.downrangeKm)
					loKick = mid;
				else
					hiKick = mid;
			}
			effectiveKickDeg = 0.5 * (loKick + hiKick);
		}
	}

	// Run nominal ascent
	AscentRunOut nomOut;
	runAscent(true, azimuthDeg, 1.0, effectiveKickDeg, 0.0, 0.0, 0.0, nomOut);

	// Insert Max-Q event cleanly
	if (nomOut.maxQVal > 1000.0)
	{
		double la = 0.0, lo = 0.0, alt = 0.0;
		ecefToGeodetic(nomOut.maxQR, la, lo, alt);
		const Vec3 rel = nomOut.maxQR - obsEcef;
		const double rM = norm(rel);
		RocketFlightEvent mq;
		mq.code = QStringLiteral("MAX_Q");
		mq.labelZh = QStringLiteral("最大动压 (Max-Q)");
		mq.labelEn = QStringLiteral("Max-Q");
		mq.tSec = nomOut.maxQTime;
		mq.latDeg = la; mq.lonDeg = lo; mq.altKm = std::max(0.0, alt / 1000.0);
		mq.speedKmS = norm(nomOut.maxQV) / 1000.0;
		mq.rangeKm = rM / 1000.0;
		mq.azDeg = wrap360(std::atan2(dot(rel, obsE), dot(rel, obsN)) * kRad2Deg);
		mq.altDeg = (rM > 1.0) ? (std::asin(clampVal(dot(rel, obsU) / rM, -1.0, 1.0)) * kRad2Deg) : 90.0;
		res.events.append(mq);
	}

	// 3. Simulate independent debris re-entry arcs & impact points
	if (nomOut.hasBoosterSepState)
	{
		const double singleBoosterMass = veh.booster.dryMassKg / std::max(1, veh.boosterCount);
		const double singleBoosterArea = veh.booster.refAreaM2 / std::max(1, veh.boosterCount);
		res.debris.append(simulateDebrisFallback(
			QStringLiteral("booster"),
			QStringLiteral("助推器残骸落点"),
			QStringLiteral("Booster Impact Point"),
			tBoosterSep, launchUnixSec,
			nomOut.boosterSepR, nomOut.boosterSepV,
			singleBoosterMass, veh.booster.debrisCd, singleBoosterArea * 1.4,
			res.site, res.notam));
	}
	if (nomOut.hasFairingSepState && veh.fairingMassKg > 0.0)
	{
		res.debris.append(simulateDebrisFallback(
			QStringLiteral("fairing"),
			QStringLiteral("整流罩残骸落点"),
			QStringLiteral("Fairing Impact Point"),
			veh.fairingSepSec, launchUnixSec,
			nomOut.fairingSepR, nomOut.fairingSepV,
			veh.fairingMassKg * 0.5, 1.45, veh.fairingAreaM2 * 1.8,
			res.site, res.notam));
	}
	if (nomOut.hasStage1SepState)
	{
		res.debris.append(simulateDebrisFallback(
			QStringLiteral("stage1"),
			QStringLiteral("一级残骸落点"),
			QStringLiteral("First Stage Impact Point"),
			tStageSep, launchUnixSec,
			nomOut.stage1SepR, nomOut.stage1SepV,
			veh.stage1.dryMassKg, veh.stage1.debrisCd, veh.stage1.refAreaM2 * 1.5,
			res.site, res.notam));
	}

	// 4. Optional Monte-Carlo sensitivity dispersion for primary drop zone (booster if present, else stage 1)
	if (dispersionSamples > 0 && (nomOut.hasBoosterSepState || nomOut.hasStage1SepState))
	{
		FastRng rng(static_cast<uint64_t>(launchUnixSec) ^ 0x51A7F3C9ULL);
		res.dispersion.reserve(dispersionSamples);
		for (int i = 0; i < dispersionSamples; ++i)
		{
			const double dAz = rng.normal01() * 0.45;
			const double dThrust = 1.0 + rng.normal01() * 0.022;
			const double dKick = effectiveKickDeg + rng.normal01() * 0.65;
			const double dSep = rng.normal01() * 1.4;
			const double wE = rng.normal01() * 16.0;
			const double wN = rng.normal01() * 16.0;

			AscentRunOut mcOut;
			runAscent(false, wrap360(azimuthDeg + dAz), dThrust, dKick, dSep, wE, wN, mcOut);

			RocketDebrisTrack dtMc;
			if (veh.hasBoosters && mcOut.hasBoosterSepState)
			{
				const double mB = veh.booster.dryMassKg / std::max(1, veh.boosterCount);
				const double aB = veh.booster.refAreaM2 / std::max(1, veh.boosterCount);
				dtMc = simulateDebrisFallback(
					QStringLiteral("booster"), QString(), QString(),
					tBoosterSep + dSep, launchUnixSec,
					mcOut.boosterSepR, mcOut.boosterSepV,
					mB, veh.booster.debrisCd, aB * 1.4,
					res.site, res.notam, wE, wN, false);
			}
			else if (mcOut.hasStage1SepState)
			{
				dtMc = simulateDebrisFallback(
					QStringLiteral("stage1"), QString(), QString(),
					tStageSep, launchUnixSec,
					mcOut.stage1SepR, mcOut.stage1SepV,
					veh.stage1.dryMassKg, veh.stage1.debrisCd, veh.stage1.refAreaM2 * 1.5,
					res.site, res.notam, wE, wN, false);
			}
			res.dispersion.append({dtMc.impactLatDeg, dtMc.impactLonDeg, dtMc.insideNotam});
		}
	}

	// 5. Analyze observer visibility, sunlit entry, plume window & overall 0..100 score
	double azSinSum = 0.0, azCosSum = 0.0;
	double minVisAlt = 90.0, maxVisAlt = -90.0;
	QVector<double> visAzList;
	int plumeVisibleSamples = 0;

	for (const auto& smp : res.trajectory)
	{
		if (res.sunlitEntrySec < 0.0 && smp.shadowTangentAltKm > 0.0 && smp.tSec > 0.0)
		{
			res.sunlitEntrySec = smp.tSec;
			res.sunlitEntryAltKm = smp.altKm;
		}
		if (smp.aboveHorizon)
		{
			res.visibleFromObserver = true;
			if (res.firstVisibleSec < 0.0) res.firstVisibleSec = smp.tSec;
			res.lastVisibleSec = smp.tSec;
			if (smp.altDeg > res.maxAltDeg)
			{
				res.maxAltDeg = smp.altDeg;
				res.maxAltSec = smp.tSec;
				res.maxAltAzDeg = smp.azDeg;
			}
			minVisAlt = std::min(minVisAlt, smp.altDeg);
			maxVisAlt = std::max(maxVisAlt, smp.altDeg);
			visAzList.append(smp.azDeg);
			azSinSum += std::sin(smp.azDeg * kDeg2Rad);
			azCosSum += std::cos(smp.azDeg * kDeg2Rad);

			if (smp.plumeVisible)
			{
				if (res.plumeWindowStartSec < 0.0) res.plumeWindowStartSec = smp.tSec;
				res.plumeWindowEndSec = smp.tSec;
				++plumeVisibleSamples;
				if (smp.plumeBrightness > res.peakPlumeBrightness)
				{
					res.peakPlumeBrightness = smp.plumeBrightness;
					res.peakPlumeSec = smp.tSec;
					res.peakPlumeAzDeg = smp.azDeg;
					res.peakPlumeAltDeg = smp.altDeg;
				}
			}
		}
	}

	// Add observer visibility & sunlit milestones to events list
	auto findSampleNear = [&](double targetT) -> const RocketTrajectorySample* {
		const RocketTrajectorySample* best = nullptr;
		double bestDiff = 1e9;
		for (const auto& s : res.trajectory)
		{
			const double d = std::fabs(s.tSec - targetT);
			if (d < bestDiff) { bestDiff = d; best = &s; }
		}
		return best;
	};
	auto appendDerivedEvent = [&](const QString& code, const QString& zh, const QString& en, double t) {
		if (t < 0.0) return;
		if (const auto* s = findSampleNear(t))
		{
			RocketFlightEvent ev;
			ev.code = code; ev.labelZh = zh; ev.labelEn = en;
			ev.tSec = s->tSec; ev.latDeg = s->latDeg; ev.lonDeg = s->lonDeg;
			ev.altKm = s->altKm; ev.speedKmS = s->speedKmS;
			ev.azDeg = s->azDeg; ev.altDeg = s->altDeg; ev.rangeKm = s->rangeKm;
			res.events.append(ev);
		}
	};
	appendDerivedEvent(QStringLiteral("FIRST_VISIBLE"), QStringLiteral("观测点首次出现"), QStringLiteral("First Visible"), res.firstVisibleSec);
	appendDerivedEvent(QStringLiteral("MAX_ALT"), QStringLiteral("观测点最大仰角"), QStringLiteral("Max Elevation"), res.maxAltSec);
	appendDerivedEvent(QStringLiteral("LOST_VISIBLE"), QStringLiteral("观测点消失"), QStringLiteral("Lost Below Horizon"), res.lastVisibleSec);
	if (res.sunlitEntrySec > 2.0)
		appendDerivedEvent(QStringLiteral("SUNLIT_ENTRY"), QStringLiteral("跃出地球阴影"), QStringLiteral("Enters Sunlight"), res.sunlitEntrySec);

	std::sort(res.events.begin(), res.events.end(), [](const RocketFlightEvent& a, const RocketFlightEvent& b) {
		return a.tSec < b.tSec;
	});

	// Compute 0..100 Rocket Plume Viewing Score & Recommendation
	if (!res.visibleFromObserver || res.maxAltDeg <= 0.5)
	{
		res.plumeScore = 0;
		res.plumeGrade = QStringLiteral("invisible");
		res.plumeGradeZh = QStringLiteral("本地不可见");
		res.plumeGradeEn = QStringLiteral("Not Visible Locally");
		res.plumeAdviceZh = QStringLiteral("弹道全程低于本地地平线或被地形遮挡，无法从当前位置直接观测。");
		res.plumeAdviceEn = QStringLiteral("Trajectory stays below your local horizon or terrain obstruction.");
	}
	else if (plumeVisibleSamples == 0 || res.peakPlumeBrightness < 0.14)
	{
		res.plumeScore = static_cast<int>(std::round(clampVal(res.maxAltDeg * 0.45, 5.0, 22.0)));
		res.plumeGrade = QStringLiteral("flame_only");
		if (res.observerSunAltDeg > -1.0)
		{
			res.plumeGradeZh = QStringLiteral("白天背景过亮");
			res.plumeGradeEn = QStringLiteral("Daylight Sky Too Bright");
			res.plumeAdviceZh = QStringLiteral("火箭升空段在视野内，但天空背景过亮难以呈现暮光水母；固体箭近距离仍可见白色烟柱。");
			res.plumeAdviceEn = QStringLiteral("Sky is too bright for a twilight jellyfish; solid boosters may still leave visible smoke nearby.");
		}
		else
		{
			res.plumeGradeZh = QStringLiteral("仅可见发动机火光");
			res.plumeGradeEn = QStringLiteral("Engine Flame Only (In Shadow)");
			res.plumeAdviceZh = QStringLiteral("火箭在可视段内处于地球本影区，无法被阳光照亮成火箭云，但在暗夜中可见明亮橙红尾焰移动。");
			res.plumeAdviceEn = QStringLiteral("Rocket stays inside Earth's umbra while visible; watch for a bright moving orange engine flame.");
		}
	}
	else
	{
		const double peakPart = res.peakPlumeBrightness * 62.0;
		const double durPart = clampVal(std::sqrt(static_cast<double>(plumeVisibleSamples) / 22.0), 0.0, 1.0) * 20.0;
		const double altPart = clampVal(res.maxAltDeg / 30.0, 0.0, 1.0) * 18.0;
		res.plumeScore = qBound(25, static_cast<int>(std::round(peakPart + durPart + altPart)), 100);

		if (res.plumeScore >= 75)
		{
			res.plumeGrade = QStringLiteral("excellent");
			res.plumeGradeZh = QStringLiteral("火箭云极佳");
			res.plumeGradeEn = QStringLiteral("Excellent Plume");
			res.plumeAdviceZh = QStringLiteral("强烈推荐蹲守！暮光暗度、地影高度与仰角完美契合，%1预计将呈现极具震撼力的视觉效果。").arg(res.vehicle.plumeTypeZh);
			res.plumeAdviceEn = QStringLiteral("Prime twilight geometry! Expect a vivid %1 above your horizon.").arg(res.vehicle.plumeTypeEn);
		}
		else if (res.plumeScore >= 50)
		{
			res.plumeGrade = QStringLiteral("good");
			res.plumeGradeZh = QStringLiteral("火箭云较好");
			res.plumeGradeEn = QStringLiteral("Good Plume");
			res.plumeAdviceZh = QStringLiteral("值得提前架机位拍摄，建议寻找对应方位无遮挡的开阔视野，注意捕捉分离与高空羽流展开瞬间。");
			res.plumeAdviceEn = QStringLiteral("Good viewing opportunity; find a clear horizon in the launch azimuth to capture staging and plume expansion.");
		}
		else
		{
			res.plumeGrade = QStringLiteral("fair");
			res.plumeGradeZh = QStringLiteral("火箭云可见");
			res.plumeGradeEn = QStringLiteral("Fair / Faint Plume");
			res.plumeAdviceZh = QStringLiteral("具备一定火箭云可见条件，但可能仰角偏低或天空反差一般，建议配合中长焦与三脚架长曝光。");
			res.plumeAdviceEn = QStringLiteral("Moderate visibility (low elevation or marginal contrast); use a tripod and medium-telephoto lens.");
		}
	}

	// Recommend full-frame focal length from angular span of visible sky arc
	if (!visAzList.isEmpty())
	{
		const double meanAz = wrap360(std::atan2(azSinSum, azCosSum) * kRad2Deg);
		double maxAzSpread = 0.0;
		for (double az : visAzList)
		{
			double d = std::fabs(az - meanAz);
			if (d > 180.0) d = 360.0 - d;
			maxAzSpread = std::max(maxAzSpread, d * 2.0);
		}
		const double spanDeg = std::max(maxAzSpread, maxVisAlt - std::max(0.0, minVisAlt));
		if (spanDeg > 75.0) res.recommendedFocalMm = 14;
		else if (spanDeg > 52.0) res.recommendedFocalMm = 24;
		else if (spanDeg > 36.0) res.recommendedFocalMm = 35;
		else if (spanDeg > 24.0) res.recommendedFocalMm = 50;
		else if (spanDeg > 14.0) res.recommendedFocalMm = 85;
		else res.recommendedFocalMm = 200;
	}

	res.ok = true;
	res.computeMs = static_cast<double>(timer.nsecsElapsed()) / 1e6;
	return res;
}

QJsonObject RocketLaunchMgr::simulationToJson(const RocketSimulationResult& sim, bool includeFullTrack)
{
	QJsonObject out;
	out["ok"] = sim.ok;
	if (!sim.error.isEmpty()) out["error"] = sim.error;
	out["simulationId"] = sim.simulationId;
	out["titleZh"] = sim.titleZh;
	out["titleEn"] = sim.titleEn;
	out["launchTimeUtc"] = sim.launchTimeUtc;
	out["launchJd"] = sim.launchJd;
	out["timeOffsetMin"] = sim.timeOffsetMin;
	out["launchAzimuthDeg"] = sim.launchAzimuthDeg;
	out["computeMs"] = sim.computeMs;

	QJsonObject siteObj;
	siteObj["id"] = sim.site.id;
	siteObj["nameZh"] = sim.site.nameZh;
	siteObj["nameEn"] = sim.site.nameEn;
	siteObj["code"] = sim.site.code;
	siteObj["latDeg"] = sim.site.latDeg;
	siteObj["lonDeg"] = sim.site.lonDeg;
	siteObj["altM"] = sim.site.altM;
	out["site"] = siteObj;

	QJsonObject vehObj;
	vehObj["id"] = sim.vehicle.id;
	vehObj["nameZh"] = sim.vehicle.nameZh;
	vehObj["nameEn"] = sim.vehicle.nameEn;
	vehObj["propellantClass"] = sim.vehicle.propellantClass;
	vehObj["plumeTypeZh"] = sim.vehicle.plumeTypeZh;
	vehObj["plumeTypeEn"] = sim.vehicle.plumeTypeEn;
	vehObj["summaryZh"] = sim.vehicle.summaryZh;
	vehObj["summaryEn"] = sim.vehicle.summaryEn;
	out["vehicle"] = vehObj;

	QJsonObject obsObj;
	obsObj["latDeg"] = sim.observerLatDeg;
	obsObj["lonDeg"] = sim.observerLonDeg;
	obsObj["altM"] = sim.observerAltM;
	obsObj["sunAltDeg"] = sim.observerSunAltDeg;
	obsObj["sunAzDeg"] = sim.observerSunAzDeg;
	obsObj["twilightStage"] = sim.twilightStage;
	obsObj["distanceToPadKm"] = sim.distanceToPadKm;
	out["observer"] = obsObj;

	QJsonObject summaryObj;
	summaryObj["visibleFromObserver"] = sim.visibleFromObserver;
	summaryObj["firstVisibleSec"] = sim.firstVisibleSec;
	summaryObj["lastVisibleSec"] = sim.lastVisibleSec;
	summaryObj["maxAltDeg"] = sim.maxAltDeg;
	summaryObj["maxAltSec"] = sim.maxAltSec;
	summaryObj["maxAltAzDeg"] = sim.maxAltAzDeg;
	summaryObj["sunlitEntrySec"] = sim.sunlitEntrySec;
	summaryObj["sunlitEntryAltKm"] = sim.sunlitEntryAltKm;
	summaryObj["plumeScore"] = sim.plumeScore;
	summaryObj["plumeGrade"] = sim.plumeGrade;
	summaryObj["plumeGradeZh"] = sim.plumeGradeZh;
	summaryObj["plumeGradeEn"] = sim.plumeGradeEn;
	summaryObj["plumeAdviceZh"] = sim.plumeAdviceZh;
	summaryObj["plumeAdviceEn"] = sim.plumeAdviceEn;
	summaryObj["plumeWindowStartSec"] = sim.plumeWindowStartSec;
	summaryObj["plumeWindowEndSec"] = sim.plumeWindowEndSec;
	summaryObj["peakPlumeSec"] = sim.peakPlumeSec;
	summaryObj["peakPlumeBrightness"] = sim.peakPlumeBrightness;
	summaryObj["peakPlumeAzDeg"] = sim.peakPlumeAzDeg;
	summaryObj["peakPlumeAltDeg"] = sim.peakPlumeAltDeg;
	summaryObj["recommendedFocalMm"] = sim.recommendedFocalMm;
	out["summary"] = summaryObj;

	if (sim.notam.valid)
	{
		QJsonObject nObj;
		nObj["valid"] = true;
		nObj["notamId"] = sim.notam.notamId;
		nObj["validFromUtc"] = sim.notam.validFromUtc;
		nObj["validToUtc"] = sim.notam.validToUtc;
		nObj["hasCircle"] = sim.notam.hasCircle;
		nObj["circleLatDeg"] = sim.notam.circleLatDeg;
		nObj["circleLonDeg"] = sim.notam.circleLonDeg;
		nObj["circleRadiusKm"] = sim.notam.circleRadiusKm;
		nObj["centerLatDeg"] = sim.notam.centerLatDeg;
		nObj["centerLonDeg"] = sim.notam.centerLonDeg;
		nObj["invertedAzimuthDeg"] = sim.notam.invertedAzimuthDeg;
		nObj["downrangeKm"] = sim.notam.downrangeKm;
		QJsonArray polyArr;
		for (const auto& pt : sim.notam.polygonLatLon)
			polyArr.append(QJsonArray{pt.first, pt.second});
		nObj["polygon"] = polyArr;
		out["notam"] = nObj;
	}

	QJsonArray evArr;
	for (const auto& ev : sim.events)
	{
		QJsonObject o;
		o["code"] = ev.code;
		o["labelZh"] = ev.labelZh;
		o["labelEn"] = ev.labelEn;
		o["tSec"] = ev.tSec;
		o["latDeg"] = ev.latDeg;
		o["lonDeg"] = ev.lonDeg;
		o["altKm"] = ev.altKm;
		o["speedKmS"] = ev.speedKmS;
		o["azDeg"] = ev.azDeg;
		o["altDeg"] = ev.altDeg;
		o["rangeKm"] = ev.rangeKm;
		evArr.append(o);
	}
	out["events"] = evArr;

	QJsonArray debArr;
	for (const auto& d : sim.debris)
	{
		QJsonObject o;
		o["kind"] = d.kind;
		o["labelZh"] = d.labelZh;
		o["labelEn"] = d.labelEn;
		o["sepTimeSec"] = d.sepTimeSec;
		o["impactTimeSec"] = d.impactTimeSec;
		o["impactTimeUtc"] = d.impactTimeUtc;
		o["impactLatDeg"] = d.impactLatDeg;
		o["impactLonDeg"] = d.impactLonDeg;
		o["downrangeKm"] = d.downrangeKm;
		o["maxAltKm"] = d.maxAltKm;
		o["insideNotam"] = d.insideNotam;
		o["distanceToNotamKm"] = d.distanceToNotamKm;
		if (includeFullTrack)
		{
			QJsonArray arc;
			for (const auto& pt : d.arcPoints)
				arc.append(QJsonArray{pt[0], pt[1], pt[2], pt[3]});
			o["arc"] = arc;
		}
		debArr.append(o);
	}
	out["debris"] = debArr;

	if (!sim.dispersion.isEmpty())
	{
		QJsonArray dispArr;
		for (const auto& dp : sim.dispersion)
			dispArr.append(QJsonArray{dp.latDeg, dp.lonDeg, dp.insideNotam ? 1 : 0});
		out["dispersion"] = dispArr;
	}

	if (includeFullTrack)
	{
		// Compact packed arrays for fast zero-jank bridge transfer to ArkTS
		QJsonArray trackArr;
		for (const auto& s : sim.trajectory)
		{
			QJsonObject o;
			o["t"] = s.tSec;
			o["ph"] = s.phaseIndex;
			o["prop"] = s.activePropellant;
			o["lat"] = s.latDeg;
			o["lon"] = s.lonDeg;
			o["altKm"] = s.altKm;
			o["v"] = s.speedKmS;
			o["dr"] = s.downrangeKm;
			o["az"] = s.azDeg;
			o["alt"] = s.altDeg;
			o["rng"] = s.rangeKm;
			o["hor"] = s.horizonAltDeg;
			o["vis"] = s.aboveHorizon;
			o["hEff"] = s.shadowTangentAltKm;
			o["sun"] = s.sunlitState;
			o["pW"] = s.plumeWidthKm;
			o["pAng"] = s.plumeAngularDeg;
			o["pB"] = s.plumeBrightness;
			o["pVis"] = s.plumeVisible;
			trackArr.append(o);
		}
		out["trajectory"] = trackArr;

		QJsonArray horArr;
		for (const auto& hp : sim.horizonProfile)
			horArr.append(QJsonArray{hp.first, hp.second});
		out["horizonProfile"] = horArr;
	}
	return out;
}

void RocketLaunchMgr::setActivePreview(const RocketSimulationResult& sim, double playbackTimeSec, bool playing, double speed)
{
	activePreview = sim;
	previewActive = sim.ok && !sim.trajectory.isEmpty();
	previewTimeSec = std::max(0.0, playbackTimeSec);
	previewPlaying = playing;
	previewSpeed = clampVal(speed, 0.25, 40.0);
}

void RocketLaunchMgr::clearActivePreview()
{
	previewActive = false;
	previewPlaying = false;
	previewTimeSec = 0.0;
	previewFocalMm = 0;
}

void RocketLaunchMgr::setPreviewPlayback(double playbackTimeSec, bool playing, double speed)
{
	if (!previewActive) return;
	if (playbackTimeSec >= 0.0)
	{
		const double maxT = activePreview.trajectory.isEmpty() ? 0.0 : activePreview.trajectory.last().tSec;
		previewTimeSec = clampVal(playbackTimeSec, 0.0, maxT);
	}
	previewPlaying = playing;
	if (speed > 0.0)
		previewSpeed = clampVal(speed, 0.25, 40.0);
}

void RocketLaunchMgr::setPreviewFramingFocalMm(int focalMm)
{
	previewFocalMm = qBound(0, focalMm, 600);
}

QJsonObject RocketLaunchMgr::getPreviewStateJson() const
{
	QJsonObject o;
	o["active"] = previewActive;
	o["playing"] = previewPlaying;
	o["timeSec"] = previewTimeSec;
	o["speed"] = previewSpeed;
	o["focalMm"] = previewFocalMm;
	if (previewActive)
	{
		o["simulationId"] = activePreview.simulationId;
		o["titleZh"] = activePreview.titleZh;
		o["titleEn"] = activePreview.titleEn;
		o["maxTimeSec"] = activePreview.trajectory.isEmpty() ? 0.0 : activePreview.trajectory.last().tSec;
	}
	return o;
}
