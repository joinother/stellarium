#include "VecMath.hpp"
#include <QMap>
#include <QSet>
#include <QScopedValueRollback>
#include <QString>
#include <array>
#include <cassert>
#include <functional>
#include <iostream>

struct TestCore
{
	double jd = 2461361.2;
	double utcOffset = 8.;
	int algorithm = 1;
	double deltaT = 70., year = 1820., customNDot = -26., nDot = -25.8;
	Vec3d coefficients = Vec3d(-20., 0., 32.);
	double getJD() const { return jd; }
	double getUTCOffset(double) const { return utcOffset; }
	int getCurrentDeltaTAlgorithm() const { return algorithm; }
	double getDeltaT() const { return deltaT; }
	double getDeltaTCustomYear() const { return year; }
	double getDeltaTCustomNDot() const { return customNDot; }
	double getDeltaTnDot() const { return nDot; }
	Vec3d getDeltaTCustomEquationCoefficients() const { return coefficients; }
};

struct TestScriptMgr
{
	bool running = false;
	bool scriptIsRunning() const { return running; }
};

struct StelApp
{
	TestCore core;
	TestScriptMgr scripts;
	static StelApp& getInstance() { static StelApp app; return app; }
	TestCore* getCore() { return &core; }
	TestScriptMgr& getScriptMgr() { return scripts; }
};

struct Calendar
{
	double jd = 0.;
	int conversions = 0;
	bool base = false;
	std::function<void()> partsChanged;
	double getJD() const { return jd; }
	void setJD(double value)
	{
		++conversions;
		if (!base) jd = value;
		if (partsChanged) partsChanged();
	}
};

struct TestDialog
{
	bool shown = false;
	bool visible() const { return shown; }
};

class Calendars
{
public:
	QMap<QString, Calendar*> calendars;
	std::array<double, 10> lastConversionInputs{};
	bool conversionInputsValid = false;
	QSet<Calendar*> currentCalendars;
	bool updatingCalendar = false;
	TestDialog* configDialog = nullptr;
	Calendar* getCal(const QString& name);
	void refreshConversionInputs();
	void updateCalendar(Calendar* calendar);
	void update(double);
};

#include "calendars-demand.inc"

int main()
{
	Calendars module;
	TestDialog dialog;
	module.configDialog = &dialog;
	Calendar gregorian, chinese, base;
	base.base = true;
	module.calendars.insert("Gregorian", &gregorian);
	module.calendars.insert("Chinese", &chinese);
	module.calendars.insert("Calendar", &base);
	TestCore& core = StelApp::getInstance().core;
	for (int frame = 0; frame < 1000; ++frame)
	{
		core.jd += .125;
		module.update(.016);
	}
	assert(gregorian.conversions == 0 && chinese.conversions == 0 && base.conversions == 0);
	assert(module.getCal("missing") == nullptr);
	assert(!module.conversionInputsValid);
	assert(module.getCal("Gregorian") == &gregorian && gregorian.jd == core.jd);
	assert(gregorian.conversions == 1 && chinese.conversions == 0);
	module.getCal("Gregorian");
	assert(gregorian.conversions == 1);
	module.getCal("Calendar");
	module.getCal("Calendar");
	assert(base.conversions == 1);
	for (double timeStep : {1. / 86400., 60. / 86400., .5, 365., -730., 1e-8})
	{
		core.jd += timeStep;
		const int before = gregorian.conversions;
		module.update(.016);
		assert(gregorian.conversions == before);
		module.getCal("Gregorian");
		assert(gregorian.jd == core.jd && gregorian.conversions == before + 1);
		assert(chinese.conversions == 0);
	}
	module.getCal("Chinese");
	assert(chinese.conversions == 1 && chinese.jd == core.jd);
	for (int input = 0; input < 10; ++input)
	{
		const int before = gregorian.conversions;
		switch (input)
		{
		case 0: core.jd += .01; break;
		case 1: core.utcOffset += 1.; break;
		case 2: ++core.algorithm; break;
		case 3: core.deltaT += 1.; break;
		case 4: core.year += 1.; break;
		case 5: core.customNDot += 1.; break;
		case 6: core.nDot += 1.; break;
		default: core.coefficients[input - 7] += 1.; break;
		}
		module.getCal("Gregorian");
		assert(gregorian.conversions == before + 1);
		module.getCal("Gregorian");
		assert(gregorian.conversions == before + 1);
	}
	for (int invalidation = 0; invalidation < 8; ++invalidation)
	{
		const int before = gregorian.conversions;
		module.conversionInputsValid = false;
		module.getCal("Gregorian");
		assert(gregorian.conversions == before + 1);
	}
	gregorian.jd -= 10.;
	const int beforeDrift = gregorian.conversions;
	module.getCal("Gregorian");
	assert(gregorian.jd == core.jd && gregorian.conversions == beforeDrift + 1);
	gregorian.partsChanged = [&]() { assert(module.getCal("Gregorian") == &gregorian); };
	core.jd += .1;
	module.getCal("Gregorian");
	assert(gregorian.conversions == beforeDrift + 2);
	gregorian.partsChanged = {};
	const int beforeFeedback = gregorian.conversions;
	gregorian.partsChanged = [&]() {
		module.conversionInputsValid = false;
		core.jd += .25;
		assert(module.getCal("Gregorian") == &gregorian);
		module.update(0.);
	};
	core.jd += .1;
	module.getCal("Gregorian");
	assert(gregorian.conversions == beforeFeedback + 1);
	assert(!module.updatingCalendar && !module.conversionInputsValid);
	gregorian.partsChanged = {};
	module.getCal("Gregorian");
	assert(gregorian.conversions == beforeFeedback + 2 && gregorian.jd == core.jd);
#ifndef NO_GUI
	dialog.shown = true;
	module.conversionInputsValid = false;
	const int beforeShow = chinese.conversions;
	module.update(0.);
	assert(chinese.conversions == beforeShow + 1 && chinese.jd == core.jd);
	module.update(.016);
	assert(chinese.conversions == beforeShow + 1);
	core.jd -= .5;
	module.update(.016);
	assert(chinese.conversions == beforeShow + 2 && chinese.jd == core.jd);
	dialog.shown = false;
	core.jd += 1.;
	module.update(.016);
	assert(chinese.conversions == beforeShow + 2);
#endif
#ifdef ENABLE_SCRIPTING
	StelApp::getInstance().scripts.running = true;
	core.jd += .1;
	module.update(.016);
	assert(chinese.jd == core.jd && gregorian.jd == core.jd);
	const int beforeScript = chinese.conversions;
	module.update(.016);
	assert(chinese.conversions == beforeScript);
	StelApp::getInstance().scripts.running = false;
	core.jd += .1;
	module.update(.016);
	assert(chinese.conversions == beforeScript);
#endif
	module.configDialog = nullptr;
	core.jd += 1.;
	const int beforeNullDialog = chinese.conversions;
	module.update(.016);
	assert(chinese.conversions == beforeNullDialog);
	module.getCal("Chinese");
	assert(chinese.conversions == beforeNullDialog + 1 && chinese.jd == core.jd);
	std::cout << "Hidden frames, lazy reads, exact inputs, invalidation, GUI/script and reentrancy passed\n";
}
