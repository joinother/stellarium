#ifndef MIST_TERRAIN_HPP
#define MIST_TERRAIN_HPP

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <unordered_map>
#include <vector>

namespace MistTerrain
{
constexpr double pi = 3.14159265358979323846;
constexpr double eyeHeight = 48.;

inline bool sameViewSignature(const std::vector<double>& current, const std::vector<double>& prepared)
{
	if (current.empty() || current.size() != prepared.size()) return false;
	for (std::size_t index = 0; index < current.size(); ++index)
	{
		const double value = current[index], baseline = prepared[index];
		if (!std::isfinite(value) || !std::isfinite(baseline)) return false;
		const double tolerance = 1.e-10 * std::max({1., std::abs(value), std::abs(baseline)});
		if (std::abs(value - baseline) > tolerance) return false;
	}
	return true;
}

struct Point
{
	double east;
	double north;
	double up;
};

inline Point normalized(Point value)
{
	const double length = std::sqrt(value.east * value.east + value.north * value.north + value.up * value.up);
	return {value.east / length, value.north / length, value.up / length};
}

inline double smooth(double low, double high, double value)
{
	const double unit = std::max(0., std::min(1., (value - low) / (high - low)));
	return unit * unit * (3. - 2. * unit);
}

inline double wideFieldWeight(double fovDegrees)
{
	return smooth(130., 155., fovDegrees);
}

inline double portalTarget(double viewAltitude, double fovDegrees = 0.)
{
	const double narrow = smooth(-1.42, -.48, viewAltitude);
	return narrow + (1. - narrow) * wideFieldWeight(fovDegrees);
}

inline double flowAmount(double viewAltitude, double fovDegrees)
{
	return (1. - wideFieldWeight(fovDegrees)) * (1. - smooth(-.40, -.06, viewAltitude));
}

inline double advancePortal(double current, double target, double seconds)
{
	return current + (target - current) * (1. - std::exp(-std::max(0., std::min(.1, seconds)) / .22));
}

inline double advanceFlow(double current, double target, double seconds)
{
	return current + (target - current) * (1. - std::exp(-std::max(0., std::min(.1, seconds)) / .42));
}

struct LayerDesign
{
	double radius, height, width, phase;
};

inline const std::array<LayerDesign, 4>& layers()
{
	static const std::array<LayerDesign, 4> designs{{
		{210., 30., 82., .3}, {530., 50., 155., 2.1},
		{1250., 100., 340., 4.6}, {2600., 160., 670., 1.2}
	}};
	return designs;
}

inline std::array<double, 3> layerProfile(const LayerDesign& design, double angle)
{
	const double phase = design.phase;
	const double proximity = 1. - smooth(210., 1250., design.radius);
	const double radius = design.radius * (1. + .18 * std::cos(2. * angle + phase)
		+ .085 * std::sin(3. * angle - 1.7 * phase) + .035 * std::cos(5. * angle + .8 * phase)
		+ (.045 + .085 * proximity) * std::sin(4. * angle - 1.2 * phase)
		+ (.018 + .035 * proximity) * std::sin(7. * angle + 1.9 * phase));
	const double elevation = design.height * (1. + .24 * std::sin(2. * angle - phase)
		+ .13 * std::cos(3. * angle + 1.3 * phase)
		+ .16 * std::sin((proximity > .5 ? 4. : 6.) * angle + 1.6 * phase)
		+ .075 * std::cos((proximity > .5 ? 7. : 11.) * angle - .9 * phase)
		+ (design.radius > 2000. ? .035 * std::sin(18. * angle + .7) + .018 * std::cos(31. * angle - 1.1) : 0.));
	const double width = design.width * (1. + .18 * std::sin(angle + phase)
		+ .09 * std::cos(3. * angle - phase));
	return {{radius, elevation, width}};
}

struct LongCrest
{
	double bearing, width, height, onset, rise, fade, end;
	std::array<double, 5> radii;
	std::array<double, 5> offsets;
};

inline const std::array<LongCrest, 6>& longCrests()
{
	static const std::array<LongCrest, 6> designs{{
		{7., 1.05, 1., 25., 160., 1550., 2500., {{30., 240., 660., 1350., 2500.}}, {{-4., 14., -13., 12., -3.}}},
		{67., .86, .77, 95., 260., 1850., 2900., {{80., 410., 980., 1680., 2900.}}, {{8., -12., 15., -9., 2.}}},
		{129., 1.20, .88, 45., 190., 1700., 2700., {{40., 300., 830., 1530., 2700.}}, {{-7., 11., -16., 8., -2.}}},
		{194., .95, 1.08, 150., 330., 2050., 3200., {{130., 530., 1160., 2050., 3200.}}, {{5., -15., 12., -11., 3.}}},
		{254., 1.15, .80, 20., 140., 1450., 2350., {{25., 210., 560., 1180., 2350.}}, {{-3., 16., -10., 13., -4.}}},
		{316., .90, .94, 85., 230., 1800., 2800., {{70., 360., 900., 1770., 2800.}}, {{6., -11., 16., -13., 1.}}}
	}};
	return designs;
}

inline double longCrestBearing(const LongCrest& design, double radius)
{
	std::size_t section = 0;
	while (section < 3 && radius > design.radii[section + 1]) ++section;
	const double fraction = smooth(design.radii[section], design.radii[section + 1], radius);
	return (design.bearing + design.offsets[section]
		+ fraction * (design.offsets[section + 1] - design.offsets[section])) * pi / 180.;
}

inline double height(double east, double north)
{
	const double radius = std::hypot(east, north);
	const double angle = std::atan2(north, east);
	double elevation = -22.;
	for (const auto& design : layers())
	{
		const auto profile = layerProfile(design, angle);
		const double offset = radius - profile[0];
		const double flank = offset < 0. ? 1. : .60;
		const double across = std::abs(offset) / (profile[2] * flank);
		if (across >= 2.5) continue;
		const double rounded = std::sqrt(across * across + .0025) - .05;
		const double shape = std::exp(-1.25 * rounded - .45 * across * across)
			* (1. - smooth(2., 2.5, across));
		elevation += profile[1] * shape * smooth(0., .45 * profile[0], radius);
	}
	for (const auto& design : longCrests())
	{
		const double envelope = smooth(design.onset, design.onset + design.rise, radius)
			* (1. - smooth(design.fade, design.end, radius));
		if (envelope <= 0.) continue;
		const double bearing = longCrestBearing(design, radius);
		const double delta = std::atan2(std::sin(angle - bearing), std::cos(angle - bearing));
		const double signedDistance = radius * delta;
		const double width = design.width * (45. + .135 * radius);
		const double flank = signedDistance < 0. ? .64 : 1.;
		const double across = std::abs(signedDistance) / (width * flank);
		if (across >= 2.5) continue;
		const double rounded = std::sqrt(across * across + .04) - .2;
		const double shape = std::exp(-1.25 * rounded - .45 * across * across)
			* (1. - smooth(2., 2.5, across));
		const double crest = design.height * (48. + .045 * radius) * envelope * shape;
		const double existing = elevation + 22.;
		const double blend = std::max(0., 10. - std::abs(existing - crest)) / 10.;
		elevation = -22. + std::max(existing, crest)
			+ blend * blend * 2.5 * smooth(0., 10., std::min(existing, crest));
	}
	return elevation;
}
inline double flowCoordinate(double east, double north)
{
	return std::hypot(east, north) / layerProfile(layers()[0], std::atan2(north, east))[0];
}

struct Vertex
{
	float position[3];
	float normal[3];
	float flowCoordinate = 0.f;
};

inline Vertex midpoint(const Vertex& first, const Vertex& second)
{
	const Point normal = normalized({first.normal[0] + second.normal[0], first.normal[1] + second.normal[1], first.normal[2] + second.normal[2]});
	return {{(first.position[0] + second.position[0]) * .5f, (first.position[1] + second.position[1]) * .5f, (first.position[2] + second.position[2]) * .5f},
	        {static_cast<float>(normal.east), static_cast<float>(normal.north), static_cast<float>(normal.up)},
	        (first.flowCoordinate + second.flowCoordinate) * .5f};
}

inline Vertex midpointPosition(const Vertex& first, const Vertex& second)
{
	return {{(first.position[0] + second.position[0]) * .5f, (first.position[1] + second.position[1]) * .5f, (first.position[2] + second.position[2]) * .5f},
	        {0.f, 0.f, 0.f}};
}

struct Mesh
{
	std::vector<Vertex> vertices;
	std::vector<std::uint32_t> indices;
};

inline Mesh generate(int sectors = 384, int rings = 128)
{
	Mesh mesh;
	mesh.vertices.reserve(sectors * rings + 1);
	const auto append = [&](double east, double north) {
		const double elevation = height(east, north);
		mesh.vertices.push_back({{static_cast<float>(east), static_cast<float>(north), static_cast<float>(elevation - eyeHeight)},
		                         {0.f, 0.f, 1.f}, static_cast<float>(flowCoordinate(east, north))});
	};
	append(0., 0.);
	for (int ring = 0; ring < rings; ++ring)
	{
		const double logicalRing = static_cast<double>(ring) * 127. / (rings - 1);
		const auto radiusAt = [&](double angle) {
			const std::array<double, 6> knots{{0., 24., 48., 80., 112., 127.}};
			const std::array<double, 6> anchors{{3.,
				layerProfile(layers()[0], angle)[0], layerProfile(layers()[1], angle)[0],
				layerProfile(layers()[2], angle)[0], layerProfile(layers()[3], angle)[0], 4200.}};
			std::size_t interval = 0;
			while (interval < 4 && logicalRing > knots[interval + 1]) ++interval;
			const double fraction = (logicalRing - knots[interval]) / (knots[interval + 1] - knots[interval]);
			return anchors[interval] + fraction * (anchors[interval + 1] - anchors[interval]);
		};
		std::array<double, 7> bearings{};
		for (std::size_t crest = 0; crest < longCrests().size(); ++crest)
		{
			const auto& design = longCrests()[crest];
			double low = (design.bearing - 20.) * pi / 180.;
			double high = (design.bearing + 20.) * pi / 180.;
			for (int iteration = 0; iteration < 28; ++iteration)
			{
				const double angle = .5 * (low + high);
				if (angle < longCrestBearing(design, radiusAt(angle))) low = angle;
				else high = angle;
			}
			bearings[crest] = .5 * (low + high);
		}
		bearings.back() = bearings.front() + 2. * pi;
		std::size_t interval = 0;
		for (int sector = 0; sector < sectors; ++sector)
		{
			while (interval + 1 < longCrests().size()
				&& sector >= static_cast<int>((interval + 1) * sectors / longCrests().size())) ++interval;
			const int firstSector = static_cast<int>(interval * sectors / longCrests().size());
			const int lastSector = static_cast<int>((interval + 1) * sectors / longCrests().size());
			const double fraction = static_cast<double>(sector - firstSector) / (lastSector - firstSector);
			const double angle = bearings[interval] + fraction * (bearings[interval + 1] - bearings[interval]);
			const double radius = radiusAt(angle);
			append(radius * std::cos(angle), radius * std::sin(angle));
			const std::uint32_t current = 1 + ring * sectors + sector;
			const std::uint32_t next = 1 + ring * sectors + (sector + 1) % sectors;
			if (ring == 0) mesh.indices.insert(mesh.indices.end(), {0, current, next});
			else
			{
				mesh.indices.insert(mesh.indices.end(), {current - sectors, current, next});
				mesh.indices.insert(mesh.indices.end(), {current - sectors, next, next - sectors});
			}
		}
	}
	for (int ring = 0; ring < rings; ++ring)
		for (int sector = 0; sector < sectors; ++sector)
		{
			const int inner = std::max(0, ring - 1);
			const int outer = std::min(rings - 1, ring + 1);
			const int before = (sector + sectors - 1) % sectors;
			const int after = (sector + 1) % sectors;
			const auto& inward = mesh.vertices[1 + inner * sectors + sector];
			const auto& outward = mesh.vertices[1 + outer * sectors + sector];
			const auto& previous = mesh.vertices[1 + ring * sectors + before];
			const auto& next = mesh.vertices[1 + ring * sectors + after];
			const Point radial{outward.position[0] - inward.position[0], outward.position[1] - inward.position[1], outward.position[2] - inward.position[2]};
			const Point tangent{next.position[0] - previous.position[0], next.position[1] - previous.position[1], next.position[2] - previous.position[2]};
			const auto normal = normalized({radial.north * tangent.up - radial.up * tangent.north,
			                                radial.up * tangent.east - radial.east * tangent.up,
			                                radial.east * tangent.north - radial.north * tangent.east});
			auto& vertex = mesh.vertices[1 + ring * sectors + sector];
			vertex.normal[0] = static_cast<float>(normal.east);
			vertex.normal[1] = static_cast<float>(normal.north);
			vertex.normal[2] = static_cast<float>(normal.up);
		}
	return mesh;
}

struct ScreenPoint
{
	double horizontal;
	double vertical;
	bool valid;
};

struct ViewCone
{
	Point axis{0., 0., 1.};
	double radius = pi;
};

struct MeshBlock
{
	std::size_t begin;
	std::size_t end;
	ViewCone cone;
};

struct ViewWorkspace
{
	Mesh result;
	std::vector<ScreenPoint> screen;
	std::vector<unsigned char> projected;
	std::vector<std::uint32_t> refined;
	std::vector<MeshBlock> blocks;
	std::vector<std::array<std::uint32_t, 2>> baseEdges;
	std::vector<std::array<std::uint32_t, 2>> activeEdges;
	std::unordered_map<std::uint64_t, std::uint32_t> splits;
	std::size_t projectedCount = 0;
	std::size_t candidateTriangles = 0;
	std::size_t edgeChecks = 0;
	std::size_t midpointProjections = 0;
	std::size_t profileFrames = 0;
	int refinementRounds = 0;
	bool usedFastPath = false;
};

inline void initializeWorkspace(const Mesh& original, ViewWorkspace& workspace)
{
	workspace.result.vertices = original.vertices;
	workspace.result.vertices.reserve(original.vertices.size() + 8192);
	workspace.result.indices.reserve(original.indices.size() + 8192 * 6);
	workspace.refined.reserve(original.indices.size() + 8192 * 6);
	workspace.screen.reserve(original.vertices.size() + 8192);
	workspace.projected.resize(original.vertices.size());
	workspace.blocks.clear();
	workspace.baseEdges.clear();
	for (std::size_t index = 0; index < original.indices.size(); index += 3)
		for (int edge = 0; edge < 3; ++edge)
		{
			const auto first = original.indices[index + edge], second = original.indices[index + (edge + 1) % 3];
			workspace.baseEdges.push_back({std::min(first, second), std::max(first, second)});
		}
	std::sort(workspace.baseEdges.begin(), workspace.baseEdges.end());
	workspace.baseEdges.erase(std::unique(workspace.baseEdges.begin(), workspace.baseEdges.end()), workspace.baseEdges.end());
	workspace.activeEdges.reserve(workspace.baseEdges.size());
	for (std::size_t begin = 0; begin < original.indices.size(); begin += 32 * 3)
	{
		const std::size_t end = std::min(original.indices.size(), begin + 32 * 3);
		std::array<double, 3> low{{1.e30, 1.e30, 1.e30}}, high{{-1.e30, -1.e30, -1.e30}};
		for (std::size_t index = begin; index < end; ++index)
			for (int component = 0; component < 3; ++component)
			{
				const double value = original.vertices[original.indices[index]].position[component];
				low[component] = std::min(low[component], value);
				high[component] = std::max(high[component], value);
			}
		const Point center{(low[0] + high[0]) * .5, (low[1] + high[1]) * .5, (low[2] + high[2]) * .5};
		const double distance = std::sqrt(center.east * center.east + center.north * center.north + center.up * center.up);
		const double radius = .5 * std::sqrt(std::pow(high[0] - low[0], 2.) + std::pow(high[1] - low[1], 2.) + std::pow(high[2] - low[2], 2.));
		ViewCone cone;
		if (distance > radius + 1.e-6)
		{
			cone.axis = normalized(center);
			cone.radius = std::asin(std::min(1., radius / distance)) + 1.e-6;
		}
		workspace.blocks.push_back({begin, end, cone});
	}
}

inline bool conesOverlap(const ViewCone& first, const ViewCone& second)
{
	const double aperture = first.radius + second.radius;
	return aperture >= pi || first.axis.east * second.axis.east + first.axis.north * second.axis.north + first.axis.up * second.axis.up >= std::cos(aperture);
}

template<class Project, class CrossesSeam>
inline const Mesh& prepareVisibleMesh(const Mesh& original, ViewWorkspace& workspace, Project project, CrossesSeam crossesSeam,
                                     double width, double height, const ViewCone& cone = ViewCone{}, bool clipScreen = true,
                                     bool regularProjection = false)
{
	if (workspace.blocks.empty()) initializeWorkspace(original, workspace);
	auto& result = workspace.result;
	auto& screen = workspace.screen;
	result.vertices.resize(original.vertices.size());
	result.indices.clear();
	screen.resize(original.vertices.size());
	std::fill(workspace.projected.begin(), workspace.projected.end(), 0);
	workspace.projectedCount = 0;
	workspace.edgeChecks = 0;
	workspace.midpointProjections = 0;
	workspace.refinementRounds = 0;
	for (const auto& block : workspace.blocks)
	{
		if (!conesOverlap(cone, block.cone)) continue;
		result.indices.insert(result.indices.end(), original.indices.begin() + block.begin, original.indices.begin() + block.end);
		for (std::size_t index = block.begin; index < block.end; ++index)
		{
			const auto vertex = original.indices[index];
			if (workspace.projected[vertex]) continue;
			screen[vertex] = project(original.vertices[vertex]);
			workspace.projected[vertex] = 1;
			++workspace.projectedCount;
		}
	}
	workspace.candidateTriangles = result.indices.size() / 3;
	workspace.usedFastPath = regularProjection && cone.radius < pi * .5;
	if (workspace.usedFastPath)
	{
		for (std::size_t index = 0; index < original.vertices.size(); ++index)
			if (workspace.projected[index] && !screen[index].valid) workspace.usedFastPath = false;
	}
	workspace.activeEdges.clear();
	if (workspace.usedFastPath)
		for (const auto& edge : workspace.baseEdges)
			if (workspace.projected[edge[0]] && workspace.projected[edge[1]]) workspace.activeEdges.push_back(edge);
	const auto edgeKey = [](std::uint32_t first, std::uint32_t second) {
		return (static_cast<std::uint64_t>(std::min(first, second)) << 32) | std::max(first, second);
	};
	for (int iteration = 0; iteration < (workspace.usedFastPath ? 3 : 9); ++iteration)
	{
		++workspace.refinementRounds;
		const auto iterationVertices = result.vertices.size();
		auto& splits = workspace.splits;
		splits.clear();
		const auto mark = [&](std::uint32_t first, std::uint32_t second) {
			const auto key = edgeKey(first, second);
			if (splits.count(key) || result.vertices.size() >= original.vertices.size() + 8192) return;
			const auto middle = midpoint(result.vertices[first], result.vertices[second]);
			splits.emplace(key, static_cast<std::uint32_t>(result.vertices.size()));
			result.vertices.push_back(middle);
			screen.push_back(project(middle));
			++workspace.midpointProjections;
		};
		if (workspace.usedFastPath)
		{
			for (const auto& edge : workspace.activeEdges)
			{
				++workspace.edgeChecks;
				const auto first = edge[0], second = edge[1];
				const auto& start = screen[first];
				const auto& end = screen[second];
				const double deltaX = end.horizontal - start.horizontal, deltaY = end.vertical - start.vertical;
				const double lengthSquared = deltaX * deltaX + deltaY * deltaY;
				if (lengthSquared < 24. * 24.) continue;
				const auto middleVertex = midpointPosition(result.vertices[first], result.vertices[second]);
				const auto middle = project(middleVertex);
				++workspace.midpointProjections;
				if (!middle.valid)
					return prepareVisibleMesh(original, workspace, project, crossesSeam, width, height, cone, clipScreen, false);
				if (middle.valid)
				{
					if (std::max({start.horizontal, end.horizontal, middle.horizontal}) < -32. ||
					    std::min({start.horizontal, end.horizontal, middle.horizontal}) > width + 32. ||
					    std::max({start.vertical, end.vertical, middle.vertical}) < -32. ||
					    std::min({start.vertical, end.vertical, middle.vertical}) > height + 32.) continue;
					const double along = std::max(0., std::min(1., ((middle.horizontal - start.horizontal) * deltaX + (middle.vertical - start.vertical) * deltaY) / lengthSquared));
					if (std::hypot(middle.horizontal - start.horizontal - along * deltaX, middle.vertical - start.vertical - along * deltaY) <= .65) continue;
				}
				if (result.vertices.size() >= original.vertices.size() + 8192) continue;
				splits.emplace(edgeKey(first, second), static_cast<std::uint32_t>(result.vertices.size()));
				result.vertices.push_back(midpoint(result.vertices[first], result.vertices[second]));
				screen.push_back(middle);
			}
		}
		else
		{
		for (std::size_t index = 0; index < result.indices.size(); index += 3)
			for (int edge = 0; edge < 3; ++edge)
			{
				++workspace.edgeChecks;
				const auto first = result.indices[index + edge], second = result.indices[index + (edge + 1) % 3];
				if (screen[first].valid != screen[second].valid || crossesSeam(result.vertices[first], result.vertices[second]))
					mark(first, second);
			}
		if (iteration < 3)
			for (std::size_t index = 0; index < result.indices.size(); index += 3)
				for (int edge = 0; edge < 3; ++edge)
				{
					++workspace.edgeChecks;
					const auto first = result.indices[index + edge], second = result.indices[index + (edge + 1) % 3];
					const auto& start = screen[first];
					const auto& end = screen[second];
					if (!start.valid || !end.valid) continue;
					const double deltaX = end.horizontal - start.horizontal, deltaY = end.vertical - start.vertical;
					const double lengthSquared = deltaX * deltaX + deltaY * deltaY;
					if (lengthSquared < 24. * 24.) continue;
					const auto middle = project(midpointPosition(result.vertices[first], result.vertices[second]));
					++workspace.midpointProjections;
					if (!middle.valid) { mark(first, second); continue; }
					const double left = std::min({start.horizontal, end.horizontal, middle.horizontal});
					const double right = std::max({start.horizontal, end.horizontal, middle.horizontal});
					const double bottom = std::min({start.vertical, end.vertical, middle.vertical});
					const double top = std::max({start.vertical, end.vertical, middle.vertical});
					if (right < -32. || left > width + 32. || top < -32. || bottom > height + 32.) continue;
					const double along = std::max(0., std::min(1., ((middle.horizontal - start.horizontal) * deltaX + (middle.vertical - start.vertical) * deltaY) / lengthSquared));
					if (std::hypot(middle.horizontal - start.horizontal - along * deltaX, middle.vertical - start.vertical - along * deltaY) > .65)
						mark(first, second);
				}
		}
		if (splits.empty()) break;
		auto& refined = workspace.refined;
		refined.clear();
		refined.reserve(result.indices.size() + splits.size() * 6);
		const auto appendFace = [&](std::uint32_t first, std::uint32_t second, std::uint32_t third) {
			refined.insert(refined.end(), {first, second, third});
		};
		for (std::size_t index = 0; index < result.indices.size(); index += 3)
		{
			std::array<std::uint32_t, 3> corners{{result.indices[index], result.indices[index + 1], result.indices[index + 2]}};
			std::array<std::uint32_t, 3> middles{{0, 0, 0}};
			int count = 0;
			for (int edge = 0; edge < 3; ++edge)
			{
				const auto found = splits.find(edgeKey(corners[edge], corners[(edge + 1) % 3]));
				if (found != splits.end()) { middles[edge] = found->second; ++count; }
			}
			if (count == 0) appendFace(corners[0], corners[1], corners[2]);
			else if (count == 3)
			{
				appendFace(corners[0], middles[0], middles[2]);
				appendFace(middles[0], corners[1], middles[1]);
				appendFace(middles[2], middles[1], corners[2]);
				appendFace(middles[0], middles[1], middles[2]);
			}
			else
			{
				while ((count == 1 && !middles[0]) || (count == 2 && middles[2]))
				{
					std::rotate(corners.begin(), corners.begin() + 1, corners.end());
					std::rotate(middles.begin(), middles.begin() + 1, middles.end());
				}
				if (count == 1)
				{
					appendFace(corners[0], middles[0], corners[2]);
					appendFace(middles[0], corners[1], corners[2]);
				}
				else
				{
					appendFace(corners[1], middles[1], middles[0]);
					appendFace(corners[0], middles[0], corners[2]);
					appendFace(middles[0], middles[1], corners[2]);
				}
			}
		}
		result.indices.swap(refined);
		if (workspace.usedFastPath)
		{
			workspace.activeEdges.clear();
			for (std::size_t index = 0; index < result.indices.size(); index += 3)
				for (int edge = 0; edge < 3; ++edge)
				{
					const auto first = result.indices[index + edge], second = result.indices[index + (edge + 1) % 3];
					if (first >= iterationVertices || second >= iterationVertices)
						workspace.activeEdges.push_back({std::min(first, second), std::max(first, second)});
				}
			std::sort(workspace.activeEdges.begin(), workspace.activeEdges.end());
			workspace.activeEdges.erase(std::unique(workspace.activeEdges.begin(), workspace.activeEdges.end()), workspace.activeEdges.end());
		}
	}
	std::size_t retained = 0;
	for (std::size_t index = 0; index < result.indices.size(); index += 3)
	{
		const auto first = result.indices[index], second = result.indices[index + 1], third = result.indices[index + 2];
		if (!screen[first].valid || !screen[second].valid || !screen[third].valid ||
		    (!workspace.usedFastPath && (crossesSeam(result.vertices[first], result.vertices[second]) ||
		    crossesSeam(result.vertices[second], result.vertices[third]) ||
		    crossesSeam(result.vertices[third], result.vertices[first])))) continue;
		if (clipScreen && (std::max({screen[first].horizontal, screen[second].horizontal, screen[third].horizontal}) < -2. ||
		                   std::min({screen[first].horizontal, screen[second].horizontal, screen[third].horizontal}) > width + 2. ||
		                   std::max({screen[first].vertical, screen[second].vertical, screen[third].vertical}) < -2. ||
		                   std::min({screen[first].vertical, screen[second].vertical, screen[third].vertical}) > height + 2.)) continue;
		result.indices[retained++] = first;
		result.indices[retained++] = second;
		result.indices[retained++] = third;
	}
	result.indices.resize(retained);
	return result;
}

template<class Project, class CrossesSeam>
inline Mesh visibleMesh(const Mesh& original, Project project, CrossesSeam crossesSeam, double width, double height)
{
	ViewWorkspace workspace;
	prepareVisibleMesh(original, workspace, project, crossesSeam, width, height, ViewCone{}, false);
	return std::move(workspace.result);
}
}

#endif
