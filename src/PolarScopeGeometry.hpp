#pragma once

#include <cmath>
#include <initializer_list>

inline double polarScopeRadius(double centerX, double centerY, double starX, double starY)
{
	const double radius = std::hypot(starX - centerX, starY - centerY);
	return std::isfinite(radius) ? radius : 0.0;
}

inline int polarScopeLabelStep(double radius, double labelWidth)
{
	for (const int step : {1, 2, 3, 6})
	{
		if (2.0 * radius * std::sin(step * 3.141592653589793 / 24.0) >= labelWidth + 12.0)
			return step;
	}
	return 24;
}
