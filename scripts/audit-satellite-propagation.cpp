#include "gsatellite/gSatTEME.hpp"
#include <QCoreApplication>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <iostream>

int main(int argc, char** argv)
{
	QCoreApplication app(argc, argv);
	if (argc != 3) return 2;
	QFile file(QString::fromLocal8Bit(argv[1]));
	if (!file.open(QIODevice::ReadOnly)) return 2;
	const QJsonObject catalog = QJsonDocument::fromJson(file.readAll()).object().value("satellites").toObject();
	const double jd = QString::fromLocal8Bit(argv[2]).toDouble();
	QJsonArray rows;
	int anomalous = 0;
	int assertions = 0;
	QByteArray regressionFirst("1 00000U 26114Q   26175.25002315 -.02505361  00000+0 -34872-1 0  9991");
	QByteArray regressionSecond("2 00000  53.1588 167.0283 0001142  53.0104  63.4268 15.60085695  5953");
	regressionFirst.resize(130, ' ');
	regressionSecond.resize(130, ' ');
	gSatTEME regression("STARLINK-36933 old TLE", regressionFirst.data(), regressionSecond.data());
	regression.setEpoch(2461289.883);
	if (QString::fromLatin1(regression.getPropagationStatus()) != "divergent_extrapolation") return 4;
	regression.setEpoch(regression.getTleEpochJD());
	if (QString::fromLatin1(regression.getPropagationStatus()) != "valid" || regression.getPos().norm() < 6700. || regression.getPos().norm() > 6900.) return 5;
	assertions += 2;
	for (auto entry = catalog.begin(); entry != catalog.end(); ++entry)
	{
		const QJsonObject record = entry.value().toObject();
		QByteArray first = record.value("tle1").toString().toLatin1();
		QByteArray second = record.value("tle2").toString().toLatin1();
		first.resize(130, ' ');
		second.resize(130, ' ');
		gSatTEME satellite(record.value("name").toString().toUtf8().constData(), first.data(), second.data());
		satellite.setEpoch(jd);
		const Vec3d position = satellite.getPos();
		const double speed = satellite.getVel().norm();
		const double radius = position.norm();
		const int error = satellite.getErrorCode();
		const QString status = QString::fromLatin1(satellite.getPropagationStatus());
		const double maximumRadius = 2. * (EARTH_RADIUS + satellite.getPerigeeApogee()[1]);
		const bool implausible = error != 0 || !std::isfinite(radius) || radius < EARTH_RADIUS + 80.
			|| !std::isfinite(speed) || radius > maximumRadius;
		satellite.setEpoch(jd + 1. / 86400.);
		const double angularRate = position.angle(satellite.getPos()) * 180. / M_PI;
		if ((status != "valid") != implausible) return 3;
		++assertions;
		const double epochJD = satellite.getTleEpochJD();
		satellite.setEpoch(epochJD);
		const QString epochStatus = QString::fromLatin1(satellite.getPropagationStatus());
		satellite.setEpoch(jd);
		if (QString::fromLatin1(satellite.getPropagationStatus()) != status) return 6;
		++assertions;
		if (implausible) ++anomalous;
		rows.append(QJsonObject{{"id", entry.key()}, {"name", record.value("name")},
			{"sgp4Error", error}, {"radiusKm", radius}, {"speedKmS", speed},
			{"geocentricDegreesPerSecond", angularRate}, {"epochApogeeKm", satellite.getPerigeeApogee()[1]},
			{"anomalous", implausible}, {"tleEpoch", record.value("tle1").toString().mid(18, 14)}});
		QJsonObject row = rows.last().toObject();
		row["propagationStatus"] = status;
		row["epochStatus"] = epochStatus;
		row["tleAgeDays"] = jd - epochJD;
		rows.replace(rows.size() - 1, row);
	}
	const QJsonObject report{{"jd", jd}, {"count", rows.size()}, {"anomalous", anomalous}, {"assertions", assertions}, {"satellites", rows}};
	std::cout << QJsonDocument(report).toJson().constData();
}
