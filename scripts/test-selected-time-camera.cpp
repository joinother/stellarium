#include "VecMath.hpp"
#include <cassert>
#include <cmath>
#include <iostream>
#include <limits>

class StelMovementMgr
{
public:
	static bool solveMountFrameAnchor(const Vec3d&, const Vec3d&, Vec3d&, Vec3d&);
};

#include "selected-time-camera.inc"

static Vec3d direction(double longitude, double latitude)
{
	return Vec3d(std::cos(longitude) * std::cos(latitude), std::sin(longitude) * std::cos(latitude), std::sin(latitude));
}

static Vec3d vertical(double longitude, double latitude)
{
	return Vec3d(-std::cos(longitude) * std::sin(latitude), -std::sin(longitude) * std::sin(latitude), std::cos(latitude));
}

static Vec3d ray(const Vec3d& view, const Vec3d& up, const Vec3d& local)
{
	return view * local[0] + up * local[1] + (up ^ view) * local[2];
}

static void checkFrame(const Vec3d& view, const Vec3d& up)
{
	assert(std::abs(view.normSquared() - 1.) < 1e-12);
	assert(std::abs(up.normSquared() - 1.) < 1e-12);
	assert(std::abs(view.dot(up)) < 1e-12);
	assert(up[2] > 0.);
	assert(((up ^ view) ^ Vec3d(0., 0., 1.)).normSquared() > .99);
}

int main()
{
	int exactCases = 0;
	for (double longitude : {-3., -1., 0., 1., 3.})
	for (double latitude : {-1.55, -.8, 0., .8, 1.55})
	for (double screenUp : {-.7, 0., .7})
	for (double screenSide : {-.7, 0., .7})
	for (double initialRoll : {0., .7, 2.8})
	{
		Vec3d local(1., screenUp, screenSide);
		local.normalize();
		Vec3d view = direction(.3, .2);
		Vec3d up = vertical(.3, .2) * std::cos(initialRoll) + Vec3d(-std::sin(.3), std::cos(.3), 0.) * std::sin(initialRoll);
		const Vec3d target = ray(direction(longitude, latitude), vertical(longitude, latitude), local);
		assert(StelMovementMgr::solveMountFrameAnchor(ray(view, up, local), target, view, up));
		checkFrame(view, up);
		assert((ray(view, up, local) - target).normSquared() < 1e-20);
		const Vec3d solvedView = view;
		const Vec3d solvedUp = up;
		for (int repeat = 0; repeat < 10; ++repeat)
			assert(StelMovementMgr::solveMountFrameAnchor(ray(view, up, local), target, view, up));
		assert((view - solvedView).normSquared() < 1e-20);
		assert((up - solvedUp).normSquared() < 1e-20);
		++exactCases;
	}
	int timeFrames = 0;
	for (double observerLatitude : {-1.5, -.6, 0., .6, 1.5})
	for (double declination : {-1.4, -.6, 0., .6, 1.4})
	for (double hourStep : {-.7, -.005, .005, .7, M_PI})
	for (double screenOffset : {0., .35, -.6})
	{
		Vec3d view(1., 0., 0.), up(0., 0., 1.);
		Vec3d local(1., screenOffset, screenOffset);
		local.normalize();
		for (int frame = 0; frame < 500; ++frame)
		{
			const double hourAngle = frame * hourStep;
			const double equatorialX = std::cos(declination) * std::cos(hourAngle);
			const Vec3d target(std::sin(observerLatitude) * equatorialX - std::cos(observerLatitude) * std::sin(declination),
				std::cos(declination) * std::sin(hourAngle),
				std::cos(observerLatitude) * equatorialX + std::sin(observerLatitude) * std::sin(declination));
			assert(StelMovementMgr::solveMountFrameAnchor(ray(view, up, local), target, view, up));
			checkFrame(view, up);
			const Vec3d solvedView = view;
			assert(StelMovementMgr::solveMountFrameAnchor(ray(view, up, local), target, view, up));
			assert((view - solvedView).normSquared() < 1e-18);
			++timeFrames;
		}
	}
	for (double pole : {-1., 1.})
	{
		Vec3d view = direction(.4, 1.2 * pole), up = vertical(.4, 1.2 * pole);
		Vec3d local(1., .3, .5);
		local.normalize();
		const Vec3d target(0., 0., pole);
		assert(StelMovementMgr::solveMountFrameAnchor(ray(view, up, local), target, view, up));
		checkFrame(view, up);
		const Vec3d solved = view;
		for (int repeat = 0; repeat < 100; ++repeat)
		{
			assert(StelMovementMgr::solveMountFrameAnchor(ray(view, up, local), target, view, up));
			assert((view - solved).normSquared() < 1e-20);
		}
	}
	for (const Vec3d invalid : {Vec3d(0.), Vec3d(std::numeric_limits<double>::quiet_NaN(), 0., 0.),
		Vec3d(std::numeric_limits<double>::infinity(), 0., 0.)})
	{
		Vec3d view(1., 0., 0.), up(0., 0., 1.);
		assert(!StelMovementMgr::solveMountFrameAnchor(view, invalid, view, up));
		assert(view == Vec3d(1., 0., 0.) && up == Vec3d(0., 0., 1.));
	}
	std::cout << exactCases << " exact screen-anchor cases; " << timeFrames << " forward/reverse time frames; pole/invalid cases passed\n";
}
