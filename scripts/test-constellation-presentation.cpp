#include "../src/core/modules/ConstellationPresentation.hpp"
#include <cassert>
#include <cmath>
#include <iostream>

int main()
{
	using namespace ConstellationPresentation;
	for (const double span : {5., 20., 60., 120.})
	{
		assert(zoomOpacity(span * 0.20, span) == 0.);
		assert(zoomOpacity(span, span) == 1.);
		double previous = 0.;
		for (int step = 0; step <= 200; ++step)
		{
			const double opacity = zoomOpacity(span * step / 100., span);
			assert(std::isfinite(opacity) && opacity >= previous && opacity <= 1.);
			previous = opacity;
		}
		assert(std::abs(zoomOpacity(span * .575, span) - .5) < 1e-10);
	}
	for (const double fov : {1., 20., 60., 180.})
	{
		assert(centerWeight(1., fov) == 1.);
		assert(centerWeight(-1., fov) == 0.);
		double previous = 1.;
		for (int step = 0; step <= 180; ++step)
		{
			const double weight = centerWeight(std::cos(step * .017453292519943295), fov);
			assert(std::isfinite(weight) && weight <= previous && weight >= 0.);
			previous = weight;
		}
	}
	for (const double frameTime : {1. / 15., 1. / 30., 1. / 60., 1. / 120.})
	{
		CenterArrival arrival;
		assert(arrival.update(frameTime, 1., true) == 0.);
		double maximum = 0.;
		for (int frame = 0; frame < 5. / frameTime; ++frame)
			maximum = std::max(maximum, arrival.update(frameTime, 1., true));
		assert(maximum > .99);
		assert(arrival.elapsed == 1.6);
		assert(arrival.update(frameTime, .95, true) == 0.);
		assert(arrival.update(frameTime, 1., true) == 0.);
		arrival.update(frameTime, .5, true);
		arrival.update(frameTime, 1., true);
		assert(arrival.elapsed == 0.);
		assert(arrival.update(.8, 1., true) > .99);
		assert(arrival.update(10., 1., true) == 0.);
		assert(arrival.update(.1, 1., false) == 0.);
		assert(arrival.armed && arrival.elapsed == 1.6);
		assert(arrival.update(.1, 1., true) == 0.);
		assert(arrival.update(.8, 1., true) > .99);
		assert(arrival.update(.1, 1., false) == 0.);
	}
	// Center line-drawing animation & staggered segment waves
	{
		CenterLineAnimation lineAnim;
		assert(lineAnim.update(0.016, false, false, 0.0) == 1.0);
		assert(lineAnim.update(0.016, true, false, 0.0) == 0.0);
		double prev = 0.0;
		for (int step = 0; step < 90; ++step)
		{
			const double p = lineAnim.update(1.0 / 60.0, true, true, 0.5);
			assert(std::isfinite(p) && p >= prev && p <= 1.0);
			prev = p;
		}
		assert(prev == 1.0);
		// Leaving center keeps drawn lines while fading, then resets once invisible
		assert(lineAnim.update(0.016, true, false, 0.4) == 1.0);
		assert(lineAnim.update(0.016, true, false, 0.01) == 0.0);
		// Re-entering center replays from 0
		const double firstFrame = lineAnim.update(0.05, true, true, 0.01);
		assert(firstFrame > 0.0 && firstFrame < 0.1);
		// Staggered segments wave: early segments lead later segments, all finish at 1.0
		assert(segmentDrawFraction(0.0, 0, 6) == 0.0);
		assert(segmentDrawFraction(1.0, 5, 6) == 1.0);
		assert(segmentDrawFraction(0.35, 0, 6) > segmentDrawFraction(0.35, 5, 6));
		assert(segmentDrawFraction(0.5, 0, 1) == 0.5);
	}
	std::cout << "Zoom fade, center emphasis, single arrival turn and center line animation across 15–120 Hz passed\n";
}
