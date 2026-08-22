/*
 * Stellarium
 * Copyright (C) 2019 Alexander Wolf
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

#include "tests/testStelSkyCultureMgr.hpp"

#include <QObject>
#include <QDebug>

#include "StelSkyCultureMgr.hpp"
#include "StelFileMgr.hpp"

QTEST_GUILESS_MAIN(TestStelSkyCultureMgr)

void TestStelSkyCultureMgr::testStelSkyCultureMgr()
{
	StelFileMgr::init();

	StelSkyCultureMgr scMgr;

	QVERIFY(scMgr.getDefaultSkyCultureID().isEmpty()); // Should be true, because sky culture is not set! (StelSkyCultureMgr::init() isn't called)
	QVERIFY(scMgr.setCurrentSkyCultureID("arabic_al-sufi"));
	QVERIFY(scMgr.getCurrentSkyCultureID()=="arabic_al-sufi");
	QVERIFY(scMgr.setCurrentSkyCultureID("modern"));
	QVERIFY(scMgr.getCurrentSkyCultureID()=="modern");
	QVERIFY(scMgr.getCurrentSkyCultureEnglishName()=="Modern");
	QVERIFY(scMgr.getCurrentSkyCultureBoundariesType()==StelSkyCulture::BoundariesType::IAU);
	QVERIFY(scMgr.getCurrentSkyCultureClassificationIdx()==StelSkyCulture::TRADITIONAL);
	QVERIFY(scMgr.getSkyCultureListEnglish().contains("modern", Qt::CaseInsensitive));
	QVERIFY(scMgr.getDirToNameMap().contains("modern"));
	QVERIFY(!scMgr.setDefaultSkyCultureID(""));
	QVERIFY(scMgr.getSkyCultureListIDs().contains("modern", Qt::CaseInsensitive));
}

void TestStelSkyCultureMgr::testCultureMetadataAndNameKeysStayAligned()
{
	StelFileMgr::init();

	StelSkyCultureMgr scMgr;
	const QMap<QString, StelSkyCulture> cultures = scMgr.getDirToNameMap();
	const QMap<QString, QString> namesById = scMgr.getDirToI18Map();

	QCOMPARE(cultures.value("maya").region.first().toString(), QStringLiteral("Central America"));
	QCOMPARE(cultures.value("macedonian").region.first().toString(), QStringLiteral("Southern Europe"));
	QCOMPARE(cultures.value("chinese_yuan_dynasty").region.first().toString(), QStringLiteral("Eastern Asia"));

	for (const QString& id : scMgr.getSkyCultureListIDs())
	{
		QVERIFY2(namesById.contains(id), qPrintable(QStringLiteral("missing localized name for %1").arg(id)));
		QCOMPARE(cultures.value(id).id, id);
	}
}
