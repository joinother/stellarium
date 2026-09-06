#pragma once

#include <QJsonObject>
#include <QVariantMap>
#include <cmath>

inline QJsonObject ohosObjectDistance(const QString& type, const QVariantMap& info)
{
	QJsonObject result{{"distanceStatus", info.value("distance-status", "unavailable").toString()}};
	const auto positive = [&info](const QString& key) {
		bool valid = false;
		const double value = info.value(key).toDouble(&valid);
		return valid && std::isfinite(value) && value > 0. ? value : 0.;
	};
	QString unit = info.value("distance-unit").toString();
	QString method = info.value("distance-method", "catalog").toString();
	QString status = "catalog";
	double value = positive("distance");
	double error = positive("distance-error");
	if (type == QLatin1String("Satellite"))
	{
		result["distanceReference"] = "observer";
		if (!info.value("orbit-valid").toBool())
		{
			result["distanceStatus"] = "invalid_orbit";
			return result;
		}
		value = positive("range");
		unit = "km";
		method = "orbital_range";
		status = "computed";
	}
	else if (positive("distance-ly") > 0.)
	{
		value = positive("distance-ly");
		error = positive("distance-error-ly");
		unit = "ly";
	}
	else if (type == QLatin1String("Planet"))
	{
		unit = "AU";
		method = "ephemeris";
		status = "computed";
		result["distanceReference"] = "observer";
	}
	else if (unit.isEmpty())
	{
		if (type == QLatin1String("Exoplanet")) unit = "pc";
		else if (type == QLatin1String("Nova") || type == QLatin1String("Supernova")) unit = "kly";
		else if (type == QLatin1String("Pulsar"))
		{
			unit = "kpc";
			method = "electron_density_model";
			if (value <= 0.)
			{
				value = positive("adistance");
				method = "catalog_estimate";
			}
			status = "estimated";
		}
	}
	if (method == QLatin1String("inverse_parallax")) status = "estimated";
	if (value <= 0.)
	{
		bool valid = false;
		const double redshift = info.value("redshift").toDouble(&valid);
		if (valid && std::isfinite(redshift) && redshift != 99. &&
			(type != QLatin1String("Quasar") || redshift > 0.))
		{
			result["distanceStatus"] = "redshift_only";
			result["redshift"] = redshift;
		}
		return result;
	}
	constexpr double parsecLightYears = 3.261563777;
	constexpr double lightYearAu = 63241.07708426628;
	double factor = 0.;
	if (unit == QLatin1String("ly")) factor = 1.;
	else if (unit == QLatin1String("kly")) factor = 1000.;
	else if (unit == QLatin1String("pc")) factor = parsecLightYears;
	else if (unit == QLatin1String("kpc")) factor = parsecLightYears * 1000.;
	else if (unit == QLatin1String("Mpc")) factor = parsecLightYears * 1000000.;
	else if (unit == QLatin1String("AU")) factor = 1. / lightYearAu;
	else if (unit == QLatin1String("km")) factor = 1. / 9460730472580.8;
	const double lightYears = value * factor;
	if (factor <= 0. || !std::isfinite(lightYears))
	{
		result["distanceStatus"] = "unsupported_unit";
		return result;
	}
	result["distanceStatus"] = status;
	result["distanceMethod"] = method;
	result["distanceValue"] = value;
	result["distanceUnit"] = unit;
	result["distanceLightYears"] = lightYears;
	if (error > 0. && std::isfinite(error * factor)) result["distanceErrorLightYears"] = error * factor;
	if (unit == QLatin1String("km"))
	{
		result["distanceKm"] = value;
		result["distance"] = QString::number(value, 'f', 1) + " km";
	}
	else if (unit == QLatin1String("AU") && value < 1000.)
		result["distance"] = QString::number(value, 'f', 4) + " AU";
	else
	{
		const double scale = lightYears >= 1e9 ? 1e9 : lightYears >= 1e6 ? 1e6 : 1.;
		const QString suffix = scale == 1e9 ? " G ly" : scale == 1e6 ? " M ly" : " ly";
		QString display = QString::number(lightYears / scale, 'f', 2);
		if (error > 0. && std::isfinite(error * factor))
			display += QStringLiteral(" ± ") + QString::number(error * factor / scale, 'f', 2);
		result["distance"] = display + suffix;
		result["distanceCompact"] = QString::number(lightYears / scale, 'f', 2) + suffix;
	}
	return result;
}
