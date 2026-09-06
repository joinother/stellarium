#include "../src/OhosObjectDistance.hpp"
#include <cassert>
#include <iostream>
#include <limits>

int main()
{
	const auto close = [](double actual, double expected) { assert(std::abs(actual - expected) < 1e-6 * std::max(1., std::abs(expected))); };
	const auto stellar = ohosObjectDistance("Star", {{"distance-ly", 8.6}, {"distance-error-ly", 0.1}, {"distance-method", "inverse_parallax"}});
	close(stellar["distanceLightYears"].toDouble(), 8.6);
	assert(stellar["distanceStatus"] == "estimated");
	assert(stellar["distance"].toString().contains(QChar(0x00b1)));
	assert(!stellar["distanceCompact"].toString().contains(QChar(0x00b1)));
	const auto nebula = ohosObjectDistance("Nebula", {{"distance", 780.}, {"distance-unit", "kpc"}, {"distance-error", 20.}});
	close(nebula["distanceLightYears"].toDouble(), 780000. * 3.261563777);
	close(nebula["distanceErrorLightYears"].toDouble(), 20000. * 3.261563777);
	assert(nebula["distance"].toString().endsWith(" M ly"));
	for (const auto& type : {"Nova", "Supernova"})
	{
		const auto transient = ohosObjectDistance(type, {{"distance", 1.2}});
		close(transient["distanceLightYears"].toDouble(), 1200.);
		assert(transient["distanceUnit"] == "kly");
	}
	const auto pulsar = ohosObjectDistance("Pulsar", {{"distance", 0.157}});
	close(pulsar["distanceLightYears"].toDouble(), 157. * 3.261563777);
	assert(pulsar["distanceStatus"] == "estimated");
	const auto adopted = ohosObjectDistance("Pulsar", {{"distance", 0.}, {"adistance", 0.25}});
	close(adopted["distanceLightYears"].toDouble(), 250. * 3.261563777);
	assert(adopted["distanceMethod"] == "catalog_estimate");
	close(ohosObjectDistance("Exoplanet", {{"distance", 100.}})["distanceLightYears"].toDouble(), 326.1563777);
	const auto planet = ohosObjectDistance("Planet", {{"distance", 1.}});
	assert(planet["distance"] == "1.0000 AU");
	assert(planet["distanceReference"] == "observer");
	const auto satellite = ohosObjectDistance("Satellite", {{"range", 1200.}, {"height", 400.}, {"orbit-valid", true}});
	assert(satellite["distance"] == "1200.0 km");
	assert(satellite["distanceKm"] == 1200.);
	const auto invalid = ohosObjectDistance("Satellite", {{"range", 1200.}, {"orbit-valid", false}});
	assert(!invalid.contains("distance"));
	assert(invalid["distanceStatus"] == "invalid_orbit");
	const auto quasar = ohosObjectDistance("Quasar", {{"redshift", 0.158}});
	assert(quasar["distanceStatus"] == "redshift_only");
	assert(!quasar.contains("distance"));
	assert(quasar["redshift"] == 0.158);
	assert(ohosObjectDistance("Quasar", {{"redshift", 0.}})["distanceStatus"] == "unavailable");
	assert(ohosObjectDistance("Star", {{"distance-status", "low_confidence"}})["distanceStatus"] == "low_confidence");
	for (double value : {-1., 0., std::numeric_limits<double>::infinity(), std::numeric_limits<double>::quiet_NaN()})
		assert(!ohosObjectDistance("Planet", {{"distance", value}}).contains("distance"));
	assert(!ohosObjectDistance("FuturePlugin", {{"distance", 123.}}).contains("distance"));
	assert(ohosObjectDistance("FuturePlugin", {{"distance", 123.}})["distanceStatus"] == "unsupported_unit");
	close(ohosObjectDistance("FuturePlugin", {{"distance", 2.}, {"distance-unit", "Mpc"}})["distanceLightYears"].toDouble(), 6523127.554);
	assert(!ohosObjectDistance("Constellation", {}).contains("distance"));
	std::cout << "Distance adapter: all assertions passed\n";
}
