#include "MistTerrain.hpp"
#include <chrono>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <map>
#include <limits>

using MistTerrain::Point;
using MistTerrain::Vertex;
static double dot(Point first, Point second) { return first.east * second.east + first.north * second.north + first.up * second.up; }
static Point point(const Vertex& vertex) { return {vertex.position[0], vertex.position[1], vertex.position[2]}; }
static void require(bool condition, const char* message) { if (!condition) throw std::runtime_error(message); }

struct Camera
{
	double heading, pitch, fov;
	int width = 1280, height = 800;
	bool fisheye = false;
	Point local(const Vertex& vertex) const
	{
		const Point right{-std::sin(heading), std::cos(heading), 0.};
		const Point up{-std::sin(pitch) * std::cos(heading), -std::sin(pitch) * std::sin(heading), std::cos(pitch)};
		const Point forward{std::cos(pitch) * std::cos(heading), std::cos(pitch) * std::sin(heading), std::sin(pitch)};
		return {dot(point(vertex), right), dot(point(vertex), up), dot(point(vertex), forward)};
	}
	MistTerrain::ScreenPoint operator()(const Vertex& vertex) const
	{
		const auto camera = local(vertex);
		const double length = std::sqrt(dot(camera, camera));
		double horizontal, vertical;
		if (fisheye)
		{
			const double radius = std::hypot(camera.east, camera.north);
			if (radius < 1e-10 && camera.up <= 0.) return {0., 0., false};
			const double scale = radius > 0. ? std::atan2(radius, camera.up) / radius : 0.;
			horizontal = camera.east * scale;
			vertical = camera.north * scale;
		}
		else
		{
			const double divisor = .5 * (length + camera.up);
			if (divisor <= 1e-10) return {0., 0., false};
			horizontal = camera.east / divisor;
			vertical = camera.north / divisor;
		}
		const double pixelScale = .5 * height / (fisheye ? fov * .5 : 2. * std::tan(fov * .25));
		return {width * .5 + pixelScale * horizontal, height * .5 + pixelScale * vertical, true};
	}
};

static void preview(const MistTerrain::Mesh& mesh, const Camera& camera, const std::string& path, double sunAltitude)
{
	const auto projected = MistTerrain::visibleMesh(mesh, camera, [](const Vertex&, const Vertex&) { return false; }, camera.width, camera.height);
	const int width = camera.width * 2, height = camera.height * 2;
	std::vector<float> depth(width * height, 1.e10f);
	std::vector<std::array<double, 3>> image(width * height, {{.22, .33, .48}});
	const Point sun{std::cos(1.2) * std::cos(sunAltitude), std::sin(1.2) * std::cos(sunAltitude), std::sin(sunAltitude)};
	std::vector<MistTerrain::ScreenPoint> positions;
	for (const auto& vertex : projected.vertices)
	{
		auto position = camera(vertex);
		position.horizontal *= 2.; position.vertical *= 2.; positions.push_back(position);
	}
	const auto edge = [](const MistTerrain::ScreenPoint& first, const MistTerrain::ScreenPoint& second, double horizontal, double vertical) {
		return (second.horizontal - first.horizontal) * (vertical - first.vertical) - (second.vertical - first.vertical) * (horizontal - first.horizontal);
	};
	for (std::size_t index = 0; index < projected.indices.size(); index += 3)
	{
		const std::array<unsigned, 3> indices{{projected.indices[index], projected.indices[index + 1], projected.indices[index + 2]}};
		const auto& first = positions[indices[0]];
		const auto& second = positions[indices[1]];
		const auto& third = positions[indices[2]];
		const double area = edge(first, second, third.horizontal, third.vertical);
		if (std::abs(area) < 1e-8) continue;
		const int left = std::max(0, static_cast<int>(std::floor(std::min({first.horizontal, second.horizontal, third.horizontal}))));
		const int right = std::min(width - 1, static_cast<int>(std::ceil(std::max({first.horizontal, second.horizontal, third.horizontal}))));
		const int bottom = std::max(0, static_cast<int>(std::floor(std::min({first.vertical, second.vertical, third.vertical}))));
		const int top = std::min(height - 1, static_cast<int>(std::ceil(std::max({first.vertical, second.vertical, third.vertical}))));
		for (int row = bottom; row <= top; ++row)
			for (int column = left; column <= right; ++column)
			{
				std::array<double, 3> weights{{edge(second, third, column + .5, row + .5) / area,
				                              edge(third, first, column + .5, row + .5) / area,
				                              edge(first, second, column + .5, row + .5) / area}};
				if (*std::min_element(weights.begin(), weights.end()) < 0.) continue;
				double total = 0.;
				for (int corner = 0; corner < 3; ++corner) { weights[corner] /= std::sqrt(dot(point(projected.vertices[indices[corner]]), point(projected.vertices[indices[corner]]))); total += weights[corner]; }
				Point hit{0., 0., 0.}, normal{0., 0., 0.};
				for (int corner = 0; corner < 3; ++corner)
				{
					const double weight = weights[corner] / total;
					const auto& vertex = projected.vertices[indices[corner]];
					hit.east += vertex.position[0] * weight; hit.north += vertex.position[1] * weight; hit.up += vertex.position[2] * weight;
					normal.east += vertex.normal[0] * weight; normal.north += vertex.normal[1] * weight; normal.up += vertex.normal[2] * weight;
				}
				const double distance = std::sqrt(dot(hit, hit));
				const int pixel = row * width + column;
				if (distance >= depth[pixel]) continue;
				depth[pixel] = static_cast<float>(distance);
				const double haze = 1. - std::exp(-distance * (.00031 + .00000009 * distance));
				const double sideLight = std::max(0., dot(MistTerrain::normalized({normal.east * 2., normal.north * 2., normal.up}), sun));
				const double shade = .50 + .50 * sideLight;
				const double flow = MistTerrain::flowAmount(camera.pitch, camera.fov * 180. / MistTerrain::pi);
				const double lower = MistTerrain::smooth(-1.32, -.30, std::asin(hit.up / distance));
				const double alpha = (1. + (lower - 1.) * flow) * MistTerrain::portalTarget(camera.pitch, camera.fov * 180. / MistTerrain::pi);
				const double illumination = MistTerrain::smooth(-.30, .12, sun.up);
				const std::array<double, 3> surface{{.29, .34, .43}}, sky{{.37, .46, .58}};
				for (int channel = 0; channel < 3; ++channel)
					image[pixel][channel] = ((surface[channel] * shade * (1. - haze) + sky[channel] * haze) * illumination) * alpha + .015 * (1. - alpha);
			}
	}
	std::ofstream output(path, std::ios::binary);
	output << "P6\n" << camera.width << ' ' << camera.height << "\n255\n";
	for (int row = camera.height - 1; row >= 0; --row)
		for (int column = 0; column < camera.width; ++column)
			for (int channel = 0; channel < 3; ++channel)
			{
				double value = 0.;
				for (int vertical = 0; vertical < 2; ++vertical)
					for (int horizontal = 0; horizontal < 2; ++horizontal) value += image[(row * 2 + vertical) * width + column * 2 + horizontal][channel] * .25;
				output.put(static_cast<char>(std::max(0., std::min(255., value * 255.))));
			}
}

static std::vector<double> depthSamples(const MistTerrain::Mesh& mesh, const Camera& camera)
{
	const int sampleWidth = 160, sampleHeight = 100;
	std::vector<double> depths(sampleWidth * sampleHeight, 1.e30);
	std::vector<MistTerrain::ScreenPoint> projected;
	for (const auto& vertex : mesh.vertices) projected.push_back(camera(vertex));
	const double pixelScale = .5 * camera.height / (camera.fisheye ? camera.fov * .5 : 2. * std::tan(camera.fov * .25));
	for (std::size_t index = 0; index < mesh.indices.size(); index += 3)
	{
		const std::array<unsigned, 3> corners{{mesh.indices[index], mesh.indices[index + 1], mesh.indices[index + 2]}};
		const auto& first = projected[corners[0]];
		const auto& second = projected[corners[1]];
		const auto& third = projected[corners[2]];
		const double determinant = (second.vertical - third.vertical) * (first.horizontal - third.horizontal) + (third.horizontal - second.horizontal) * (first.vertical - third.vertical);
		if (std::abs(determinant) < 1.e-10) continue;
		const int left = static_cast<int>(std::max(0., std::min(double(sampleWidth), std::floor(std::min({first.horizontal, second.horizontal, third.horizontal}) * sampleWidth / camera.width))));
		const int right = static_cast<int>(std::max(-1., std::min(double(sampleWidth - 1), std::ceil(std::max({first.horizontal, second.horizontal, third.horizontal}) * sampleWidth / camera.width))));
		const int bottom = static_cast<int>(std::max(0., std::min(double(sampleHeight), std::floor(std::min({first.vertical, second.vertical, third.vertical}) * sampleHeight / camera.height))));
		const int top = static_cast<int>(std::max(-1., std::min(double(sampleHeight - 1), std::ceil(std::max({first.vertical, second.vertical, third.vertical}) * sampleHeight / camera.height))));
		for (int row = bottom; row <= top; ++row)
			for (int column = left; column <= right; ++column)
			{
				const double horizontal = (column + .5) * camera.width / sampleWidth;
				const double vertical = (row + .5) * camera.height / sampleHeight;
				const double firstWeight = ((second.vertical - third.vertical) * (horizontal - third.horizontal) + (third.horizontal - second.horizontal) * (vertical - third.vertical)) / determinant;
				const double secondWeight = ((third.vertical - first.vertical) * (horizontal - third.horizontal) + (first.horizontal - third.horizontal) * (vertical - third.vertical)) / determinant;
				std::array<double, 3> weights{{firstWeight, secondWeight, 1. - firstWeight - secondWeight}};
				if (*std::min_element(weights.begin(), weights.end()) < -1.e-10) continue;
				Point hit{0., 0., 0.};
				double total = 0.;
				for (int corner = 0; corner < 3; ++corner)
				{
					const auto position = point(mesh.vertices[corners[corner]]);
					const double weight = weights[corner] / std::sqrt(dot(position, position));
					hit.east += weight * position.east; hit.north += weight * position.north; hit.up += weight * position.up;
					total += weight;
				}
				hit.east /= total; hit.north /= total; hit.up /= total;
				const double horizontalRay = (horizontal - camera.width * .5) / pixelScale;
				const double verticalRay = (vertical - camera.height * .5) / pixelScale;
				const double squared = horizontalRay * horizontalRay + verticalRay * verticalRay;
				Point ray{4. * horizontalRay / (4. + squared), 4. * verticalRay / (4. + squared), (4. - squared) / (4. + squared)};
				if (camera.fisheye)
				{
					const double radius = std::sqrt(squared);
					if (radius > MistTerrain::pi) continue;
					const double scale = radius > 1.e-10 ? std::sin(radius) / radius : 1.;
					ray = {horizontalRay * scale, verticalRay * scale, std::cos(radius)};
				}
				const Vertex hitVertex{{float(hit.east), float(hit.north), float(hit.up)}, {0, 0, 1}};
				if (dot(MistTerrain::normalized(camera.local(hitVertex)), ray) < .995) continue;
				depths[row * sampleWidth + column] = std::min(depths[row * sampleWidth + column], std::sqrt(dot(hit, hit)));
			}
	}
	return depths;
}

static void checkTerrainFlow(const MistTerrain::Mesh& mesh, int sectors, int rings)
{
	require(mesh.vertices[0].flowCoordinate == 0.f, "flow starts at zero at the observer");
	for (int sector = 0; sector < sectors; ++sector)
	{
		double previousRadius = 0., closestCrest = 1.e30;
		for (int ring = 0; ring < rings; ++ring)
		{
			const auto& vertex = mesh.vertices[1 + ring * sectors + sector];
			const double radius = std::hypot(vertex.position[0], vertex.position[1]);
			const double angle = std::atan2(vertex.position[1], vertex.position[0]);
			const double crestRadius = MistTerrain::layerProfile(MistTerrain::layers()[0], angle)[0];
			require(std::isfinite(crestRadius) && crestRadius > 0., "first crest radius is finite and positive");
			require(radius > previousRadius, "curved mesh columns retain increasing radius");
			require(std::isfinite(vertex.flowCoordinate), "mesh flow is finite");
			require(std::abs(vertex.flowCoordinate - radius / crestRadius) < 2.e-5, "vertex flow follows first crest radius at its bearing");
			const double delta = std::abs(radius - crestRadius) / crestRadius;
			if (delta < 1.e-5) require(std::abs(vertex.flowCoordinate - 1.f) < 1.e-5, "first crest vertices carry flow one");
			closestCrest = std::min(closestCrest, delta);
			previousRadius = radius;
		}
		require(closestCrest < .15, "radial sampling resolves first crest vicinity");
	}
	for (int bearing = 0; bearing < 720; ++bearing)
	{
		const double angle = bearing * MistTerrain::pi / 360.;
		const double crestRadius = MistTerrain::layerProfile(MistTerrain::layers()[0], angle)[0];
		const double east = std::cos(angle), north = std::sin(angle);
		require(std::abs(MistTerrain::flowCoordinate(crestRadius * east, crestRadius * north) - 1.) < 1.e-12, "first crest maps to flow one at every sampled bearing");
		double previousFlow = -1.;
		for (int step = 0; step <= 256; ++step)
		{
			const double radius = crestRadius * step / 64.;
			const double value = MistTerrain::flowCoordinate(radius * east, radius * north);
			require(std::isfinite(value) && value > previousFlow, "fixed-bearing flow finite and strictly radial monotonic");
			previousFlow = value;
		}
		for (double radius : {3., crestRadius, 4200.})
		{
			const double value = MistTerrain::flowCoordinate(radius * east, radius * north);
			const double wrapped = MistTerrain::flowCoordinate(radius * std::cos(angle + 2. * MistTerrain::pi), radius * std::sin(angle + 2. * MistTerrain::pi));
			require(std::abs(value - wrapped) < 1.e-10, "flow has no angular wrap seam");
		}
	}
	for (std::size_t index = 0; index < mesh.indices.size(); index += 3)
		for (int edge = 0; edge < 3; ++edge)
		{
			const auto& first = mesh.vertices[mesh.indices[index + edge]];
			const auto& second = mesh.vertices[mesh.indices[index + (edge + 1) % 3]];
			const auto middle = MistTerrain::midpoint(first, second);
			const auto reverse = MistTerrain::midpoint(second, first);
			require(middle.flowCoordinate == (first.flowCoordinate + second.flowCoordinate) * .5f, "midpoint preserves linear flow interpolation");
			require(reverse.flowCoordinate == middle.flowCoordinate, "shared edge flow independent of triangle winding");
			const auto quarter = MistTerrain::midpoint(first, middle);
			require(std::abs(quarter.flowCoordinate - (.75 * first.flowCoordinate + .25 * second.flowCoordinate)) < 1.e-5, "repeated splits preserve continuous flow");
		}
}

int main(int argc, char** argv)
{
	const MistTerrain::Mesh curvedTriangle{{{{0.f, 0.f, 1.f}, {0.f, 0.f, 1.f}, .2f},
	                                      {{100.f, 0.f, 1.f}, {.6f, 0.f, .8f}, 1.4f},
	                                      {{0.f, 100.f, 1.f}, {0.f, .8f, .6f}, 2.f}}, {0, 1, 2}};
	const auto expectedMiddle = MistTerrain::midpoint(curvedTriangle.vertices[0], curvedTriangle.vertices[1]);
	for (bool fast : {false, true})
	{
		MistTerrain::ViewWorkspace curvedWorkspace;
		const auto& curved = MistTerrain::prepareVisibleMesh(curvedTriangle, curvedWorkspace,
			[](const Vertex& vertex) { return MistTerrain::ScreenPoint{vertex.position[0] + 200.,
				vertex.position[1] + .01 * vertex.position[0] * vertex.position[0] + 200., true}; },
			[](const Vertex&, const Vertex&) { return false; }, 800., 800., {{0., 0., 1.}, 1.4}, false, fast);
		bool foundMiddle = false;
		for (std::size_t index = 3; index < curved.vertices.size(); ++index)
		{
			const auto& vertex = curved.vertices[index];
			const double length = std::sqrt(vertex.normal[0] * vertex.normal[0] + vertex.normal[1] * vertex.normal[1] + vertex.normal[2] * vertex.normal[2]);
			require(std::abs(length - 1.) < 1.e-6, "curvature samples never replace normalized split normals");
			if (!std::equal(vertex.position, vertex.position + 3, expectedMiddle.position)) continue;
			foundMiddle = true;
			require(vertex.flowCoordinate == expectedMiddle.flowCoordinate, "both preparation paths interpolate actual split flow");
			require(std::equal(vertex.normal, vertex.normal + 3, expectedMiddle.normal), "actual split retains original midpoint normal exactly");
		}
		require(foundMiddle && curvedWorkspace.usedFastPath == fast, "curved edge split exercised in both preparation paths");
	}
	const auto viewSignature = [](double angle, double fov, double viewportX, double width) {
		std::vector<double> signature(44, 0.);
		for (int diagonal : {0, 5, 10, 15})
		{
			signature[2 * diagonal] = 1.;
			signature[2 * diagonal + 1] = 1.;
		}
		signature[0] = std::cos(angle);
		signature[2] = std::sin(angle);
		signature[8] = -std::sin(angle);
		signature[10] = std::cos(angle);
		signature[32] = 400. / std::tan(fov * MistTerrain::pi / 720.);
		signature[33] = viewportX + width * .5;
		signature[34] = 800.;
		signature[37] = signature[38] = 1.;
		signature[40] = viewportX;
		signature[42] = width;
		signature[43] = 1600.;
		return signature;
	};
	const auto preparedSignature = viewSignature(0., 60., 0., 2560.);
	require(!MistTerrain::sameViewSignature(preparedSignature, {}) && !MistTerrain::sameViewSignature({}, {}), "empty view cache never matches");
	auto noisySignature = preparedSignature;
	noisySignature[18] += 2.22045e-16;
	noisySignature[32] += 1.e-8;
	require(MistTerrain::sameViewSignature(noisySignature, preparedSignature), "device matrix tail noise and subpixel scale noise reuse prepared mesh");
	noisySignature[18] = 2.e-10;
	require(!MistTerrain::sameViewSignature(noisySignature, preparedSignature), "absolute tolerance does not swallow meaningful matrix changes");
	noisySignature = preparedSignature;
	noisySignature[32] += preparedSignature[32] * 2.e-10;
	require(!MistTerrain::sameViewSignature(noisySignature, preparedSignature), "relative tolerance invalidates scale changes beyond threshold");
	for (const auto& changed : {viewSignature(.000001, 60., 0., 2560.), viewSignature(0., 60.00001, 0., 2560.),
	                           viewSignature(0., 60., .25, 2560.), viewSignature(0., 60., 0., 2561.)})
		require(!MistTerrain::sameViewSignature(changed, preparedSignature), "real rotation FOV viewport origin and viewport size invalidate cache");
	for (int field : {35, 36, 37, 38, 39})
	{
		auto changed = preparedSignature;
		changed[field] += 1.;
		require(!MistTerrain::sameViewSignature(changed, preparedSignature), "flip stretch pixel ratio and mask changes invalidate cache");
	}
	for (double invalid : {std::numeric_limits<double>::infinity(), std::numeric_limits<double>::quiet_NaN()})
	{
		auto changed = preparedSignature;
		changed[18] = invalid;
		require(!MistTerrain::sameViewSignature(changed, changed), "invalid signatures cannot produce a false cache hit");
	}
	auto lastPrepared = preparedSignature;
	int tinyMotionPreparations = 0;
	for (int frame = 1; frame <= 1000; ++frame)
	{
		const auto moving = viewSignature(frame * 1.e-12, 60., 0., 2560.);
		if (!MistTerrain::sameViewSignature(moving, lastPrepared))
		{
			lastPrepared = moving;
			++tinyMotionPreparations;
		}
	}
	require(tinyMotionPreparations >= 9 && tinyMotionPreparations <= 10, "subthreshold motion accumulates against last prepared view rather than being swallowed frame by frame");
	const auto start = std::chrono::steady_clock::now();
	constexpr int sectors = 384, rings = 128;
	const auto mesh = MistTerrain::generate(sectors, rings);
	const double generateMs = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
	checkTerrainFlow(mesh, sectors, rings);
	require(mesh.vertices.size() >= 30000 && mesh.vertices.size() <= 60000, "base vertex budget");
	std::map<std::pair<unsigned, unsigned>, int> edges;
	for (std::size_t index = 0; index < mesh.indices.size(); index += 3)
		for (int edge = 0; edge < 3; ++edge)
		{
			const unsigned first = mesh.indices[index + edge], second = mesh.indices[index + (edge + 1) % 3];
			require(first < mesh.vertices.size() && second < mesh.vertices.size(), "valid indices");
			++edges[{std::min(first, second), std::max(first, second)}];
		}
	int boundary = 0;
	for (const auto& edge : edges) { require(edge.second == 1 || edge.second == 2, "manifold mesh"); if (edge.second == 1) ++boundary; }
	require(boundary == 384, "only outer boundary, no azimuth seam or center hole");
	for (const auto& vertex : mesh.vertices)
	{
		const Point normal{vertex.normal[0], vertex.normal[1], vertex.normal[2]};
		require(std::isfinite(dot(point(vertex), point(vertex))) && std::abs(dot(normal, normal) - 1.) < 1e-6, "finite mesh and unit normals");
		require(normal.up > 0., "heightfield normals face upward without folded sampling");
	}
	for (std::size_t index = 0; index < mesh.indices.size(); index += 3)
	{
		const auto first = point(mesh.vertices[mesh.indices[index]]);
		const auto second = point(mesh.vertices[mesh.indices[index + 1]]);
		const auto third = point(mesh.vertices[mesh.indices[index + 2]]);
		require((second.east - first.east) * (third.north - first.north) - (second.north - first.north) * (third.east - first.east) > 0., "crest-fitted grid has no inverted or degenerate triangles");
	}
	double maximumViewMs = 0.;
	double ordinaryViewMs = 0.;
	unsigned maximumVertices = 0;
	for (double fov : {75., 30., 12., 210.})
		for (double pitch : {-89., -8., 89.})
		{
			Camera camera{240. * MistTerrain::pi / 180., pitch * MistTerrain::pi / 180., fov * MistTerrain::pi / 180.};
			camera.fisheye = fov == 210.;
			const auto viewStart = std::chrono::steady_clock::now();
			const auto visible = MistTerrain::visibleMesh(mesh, camera, [](const Vertex&, const Vertex&) { return false; }, camera.width, camera.height);
			maximumViewMs = std::max(maximumViewMs, std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - viewStart).count());
			if (fov == 75. && pitch == -8.) ordinaryViewMs = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - viewStart).count();
			maximumVertices = std::max(maximumVertices, static_cast<unsigned>(visible.vertices.size()));
			require(visible.vertices.size() <= mesh.vertices.size() + 8192, "view subdivision budget");
			for (const auto index : visible.indices) require(index < visible.vertices.size(), "visible indices");
			for (const auto& vertex : visible.vertices) require(std::isfinite(vertex.flowCoordinate) && vertex.flowCoordinate >= 0.f, "prepared flow finite and nonnegative");
			if (pitch == -8.)
			{
				std::map<std::pair<unsigned, unsigned>, int> shared;
				for (std::size_t index = 0; index < visible.indices.size(); index += 3)
					for (int edge = 0; edge < 3; ++edge)
					{
						const auto first = visible.indices[index + edge], second = visible.indices[index + (edge + 1) % 3];
						++shared[{std::min(first, second), std::max(first, second)}];
					}
				for (const auto& edge : shared)
				{
					require(edge.second == 1 || edge.second == 2, "refinement remains manifold");
					if (edge.second != 1) continue;
					for (const auto endpoint : {edge.first.first, edge.first.second})
					{
						const auto& vertex = visible.vertices[endpoint];
						require(std::hypot(vertex.position[0], vertex.position[1]) >= std::hypot(mesh.vertices.back().position[0], mesh.vertices.back().position[1]) - 1., "no internal T junction or missing curved face");
					}
				}
			}
		}
	for (int ring = 0; ring < rings; ++ring)
	{
		double winding = 0.;
		for (int sector = 0; sector < sectors; ++sector)
		{
			const auto first = point(mesh.vertices[1 + ring * sectors + sector]);
			const auto next = point(mesh.vertices[1 + ring * sectors + (sector + 1) % sectors]);
			const double angle = std::atan2(first.east * next.north - first.north * next.east, first.east * next.east + first.north * next.north);
			require(angle > 0. && angle < MistTerrain::pi, "ring bearings remain ordered across wrap seam");
			winding += angle;
		}
		require(std::abs(winding - 2. * MistTerrain::pi) < 1.e-6, "each ring covers exactly one circle");
	}
	for (double east = -4200.; east < 4200.; east += 71.)
		for (double north = -4200.; north < 4200.; north += 83.)
		{
			const double elevation = MistTerrain::height(east, north);
			require(std::isfinite(elevation) && elevation > -1000. && elevation < 2000., "terrain elevation finite and within generous scene bounds");
			require(std::abs(elevation - MistTerrain::height(east + .0001, north + .0001)) < .01, "terrain height continuity");
		}
	const auto cylinder = [](const Vertex& vertex) { return MistTerrain::ScreenPoint{(std::atan2(vertex.position[1], vertex.position[0]) / (2. * MistTerrain::pi) + .5) * 1280., 400. + std::atan2(vertex.position[2], std::hypot(vertex.position[0], vertex.position[1])) * 200., true}; };
	const auto seam = [&](const Vertex& first, const Vertex& second) { return std::abs(cylinder(first).horizontal - cylinder(second).horizontal) > 640.; };
	const auto split = MistTerrain::visibleMesh(mesh, cylinder, seam, 1280., 800.);
	for (std::size_t index = 0; index < split.indices.size(); index += 3)
		for (int edge = 0; edge < 3; ++edge) require(!seam(split.vertices[split.indices[index + edge]], split.vertices[split.indices[index + (edge + 1) % 3]]), "no triangle spans projection seam");
	require(MistTerrain::portalTarget(-MistTerrain::pi / 2.) == 0. && MistTerrain::portalTarget(0.) == 1., "portal endpoint");
	for (double pitch : {-90., -70., -30., 0., 90.})
	{
		const double altitude = pitch * MistTerrain::pi / 180.;
		require(MistTerrain::portalTarget(altitude, 130.) == MistTerrain::portalTarget(altitude), "narrow field retains original portal");
		require(MistTerrain::portalTarget(altitude, 155.) == 1. && MistTerrain::portalTarget(altitude, 210.) == 1., "wide field keeps complete ground at any pitch");
		require(MistTerrain::flowAmount(altitude, 155.) == 0. && MistTerrain::flowAmount(altitude, 210.) == 0., "wide view disables flowing holes");
		double previous = MistTerrain::portalTarget(altitude, 130.);
		for (int step = 1; step <= 250; ++step)
		{
			const double current = MistTerrain::portalTarget(altitude, 130. + step * .1);
			require(current >= previous && current - previous < .007, "FOV transition continuous and monotonic");
			previous = current;
		}
	}
	require(MistTerrain::flowAmount(0., 75.) == 0. && MistTerrain::flowAmount(-MistTerrain::pi / 2., 75.) == 1., "pitch changes solid ground into spatial flow mask");
	double flowing = 0., portalHistory = 0.;
	for (int frame = 0; frame < 30; ++frame)
	{
		const double previous = flowing;
		flowing = MistTerrain::advanceFlow(flowing, 1., 1. / 60.);
		portalHistory = MistTerrain::advancePortal(portalHistory, 1., 1. / 60.);
		require(flowing > previous && flowing - previous < .04, "flow history enters continuously");
	}
	require(flowing > .69 && flowing < .71 && portalHistory - flowing > .15, "flow has independent 420ms inertia");
	for (int frame = 0; frame < 30; ++frame) flowing = MistTerrain::advanceFlow(flowing, 0., 1. / 60.);
	require(flowing > .20 && flowing < .22, "looking up closes ribbons gradually rather than snapping");
	require(flowing * (1. - MistTerrain::wideFieldWeight(155.)) == 0., "wide field suppresses residual flow history immediately");
	require(MistTerrain::advanceFlow(flowing, 0., 0.) == flowing && MistTerrain::advanceFlow(flowing, 0., -1.) == flowing, "flow rejects backwards elapsed time");
	for (double pitch : {-90., 90.})
	{
		Camera camera{0., pitch * MistTerrain::pi / 180., 210. * MistTerrain::pi / 180.};
		camera.fisheye = true;
		const auto visible = MistTerrain::visibleMesh(mesh, camera, [](const Vertex&, const Vertex&) { return false; }, camera.width, camera.height);
		if (pitch < 0.)
		{
			require(std::count(visible.indices.begin(), visible.indices.end(), 0) == 384, "nadir fan remains complete in wide field");
			const auto center = camera(visible.vertices[0]);
			require(center.valid && std::hypot(center.horizontal - camera.width * .5, center.vertical - camera.height * .5) < 1e-8, "ground center covers wide nadir center");
		}
		require(!visible.indices.empty(), "wide zenith and nadir retain terrain");
	}
	double fade = 1.;
	for (int frame = 0; frame < 120; ++frame) fade = MistTerrain::advancePortal(fade, 0., 1. / 60.);
	require(fade < .001, "portal fully disappears after settling");
	for (int frame = 0; frame < 120; ++frame) fade = MistTerrain::advancePortal(fade, 1., 1. / 60.);
	require(fade > .999, "portal returns continuously");
	MistTerrain::ViewWorkspace workspace;
	MistTerrain::initializeWorkspace(mesh, workspace);
	MistTerrain::ViewWorkspace referenceWorkspace;
	MistTerrain::initializeWorkspace(mesh, referenceWorkspace);
	double optimizedMaximumMs = 0.;
	double referenceTotalMs = 0., optimizedTotalMs = 0.;
	double narrowReferenceMs = 0., narrowOptimizedMs = 0.;
	std::size_t narrowProjected = 0, narrowIndices = 0;
	std::size_t comparedPixels = 0;
	std::size_t fastEdgeChecks = 0, referenceEdgeChecks = 0;
	std::size_t benchmarkViews = 0, narrowViews = 0;
	for (double fov : {12., 30., 75., 100., 210.})
		for (double heading : {0., 55.44, 120., 240.})
		{
			++benchmarkViews;
			Camera camera{heading * MistTerrain::pi / 180., (heading == 55.44 ? -13.02 : -8.) * MistTerrain::pi / 180., fov * MistTerrain::pi / 180.};
			camera.fisheye = fov == 210.;
			const auto referenceStart = std::chrono::steady_clock::now();
			const auto& reference = MistTerrain::prepareVisibleMesh(mesh, referenceWorkspace, camera, [](const Vertex&, const Vertex&) { return false; }, camera.width, camera.height, MistTerrain::ViewCone{}, false);
			const double referenceMs = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - referenceStart).count();
			referenceTotalMs += referenceMs;
			MistTerrain::ViewCone cone;
			if (fov <= 100.)
			{
				cone.axis = {std::cos(camera.pitch) * std::cos(camera.heading), std::cos(camera.pitch) * std::sin(camera.heading), std::sin(camera.pitch)};
				cone.radius = 2. * std::atan(std::tan(camera.fov * .25) * std::hypot(double(camera.width) / camera.height, 1.)) + 3. * MistTerrain::pi / 180.;
			}
			const auto viewStart = std::chrono::steady_clock::now();
			const auto& optimized = MistTerrain::prepareVisibleMesh(mesh, workspace, camera, [](const Vertex&, const Vertex&) { return false; }, camera.width, camera.height, cone, true, fov <= 100.);
			const double viewMs = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - viewStart).count();
			optimizedMaximumMs = std::max(optimizedMaximumMs, viewMs);
			optimizedTotalMs += viewMs;
			if (fov <= 100.)
			{
				require(workspace.usedFastPath && workspace.refinementRounds <= 3, "regular narrow views use bounded unique-edge refinement");
				fastEdgeChecks += workspace.edgeChecks;
				referenceEdgeChecks += referenceWorkspace.edgeChecks;
			}
			if (fov == 12.)
			{
				++narrowViews;
				narrowReferenceMs += referenceMs;
				narrowOptimizedMs += viewMs;
				narrowProjected = std::max(narrowProjected, workspace.projectedCount);
				narrowIndices = std::max(narrowIndices, optimized.indices.size());
				require(workspace.projectedCount < mesh.vertices.size() * .45, "narrow view skips most base projections");
				require(optimized.indices.size() < mesh.indices.size() * .15, "narrow view avoids offscreen index upload");
			}
			const auto expectedDepth = depthSamples(reference, camera);
			const auto actualDepth = depthSamples(optimized, camera);
			for (std::size_t pixel = 0; pixel < expectedDepth.size(); ++pixel)
			{
				require((expectedDepth[pixel] < 1.e20) == (actualDepth[pixel] < 1.e20), "culling preserves raster coverage");
				if (expectedDepth[pixel] < 1.e20)
				{
					require(std::abs(expectedDepth[pixel] - actualDepth[pixel]) / expectedDepth[pixel] < .005, "culling preserves nearest surface depth");
					++comparedPixels;
				}
			}
			const auto* vertices = optimized.vertices.data();
			const auto* screen = workspace.screen.data();
			const auto repeatedIndices = optimized.indices;
			const auto& repeated = MistTerrain::prepareVisibleMesh(mesh, workspace, camera, [](const Vertex&, const Vertex&) { return false; }, camera.width, camera.height, cone, true, fov <= 100.);
			require(repeated.vertices.data() == vertices && workspace.screen.data() == screen, "workspace retains base and screen storage");
			require(repeated.indices == repeatedIndices, "cached workspace deterministic on same view");
		}
	require(fastEdgeChecks < referenceEdgeChecks * .35, "unique-edge path substantially reduces repeated edge checks");
	std::size_t fastProjectionPixels = 0;
	for (bool fisheye : {false, true})
		for (double pitch : {-89., -13.02, 89.})
			for (double fov : {12., 70., 100.})
			{
				Camera camera{55.44 * MistTerrain::pi / 180., pitch * MistTerrain::pi / 180., fov * MistTerrain::pi / 180.};
				camera.fisheye = fisheye;
				MistTerrain::ViewCone cone;
				cone.axis = {std::cos(camera.pitch) * std::cos(camera.heading), std::cos(camera.pitch) * std::sin(camera.heading), std::sin(camera.pitch)};
				cone.radius = (fisheye ? camera.fov * .5 * std::hypot(double(camera.width) / camera.height, 1.)
				                       : 2. * std::atan(std::tan(camera.fov * .25) * std::hypot(double(camera.width) / camera.height, 1.))) + 3. * MistTerrain::pi / 180.;
				if (cone.radius >= MistTerrain::pi * .5) cone = MistTerrain::ViewCone{};
				const auto& reference = MistTerrain::prepareVisibleMesh(mesh, referenceWorkspace, camera, [](const Vertex&, const Vertex&) { return false; }, camera.width, camera.height, MistTerrain::ViewCone{}, false);
				const auto expected = depthSamples(reference, camera);
				std::size_t seamCalls = 0;
				const auto& optimized = MistTerrain::prepareVisibleMesh(mesh, workspace, camera, [&](const Vertex&, const Vertex&) { ++seamCalls; return false; }, camera.width, camera.height, cone, true, true);
				const auto actual = depthSamples(optimized, camera);
				require(workspace.usedFastPath == (cone.radius < MistTerrain::pi * .5), "wide fisheye cap falls back while regular polar views remain fast");
				if (workspace.usedFastPath) require(seamCalls == 0, "regular projection performs no seam callbacks");
				for (std::size_t pixel = 0; pixel < expected.size(); ++pixel)
				{
					require((expected[pixel] < 1.e20) == (actual[pixel] < 1.e20), "fast path preserves polar and fisheye coverage");
					if (expected[pixel] < 1.e20)
					{
						require(std::abs(expected[pixel] - actual[pixel]) / expected[pixel] < .005, "fast path preserves polar and fisheye depth");
						++fastProjectionPixels;
					}
				}
			}
	if (argc > 1)
	{
		for (double fov : {75., 30., 12.})
		{
			Camera camera{240. * MistTerrain::pi / 180., -8. * MistTerrain::pi / 180., fov * MistTerrain::pi / 180.};
			preview(mesh, camera, std::string(argv[1]) + "-" + std::to_string(static_cast<int>(fov)) + ".ppm", .73);
		}
		for (double pitch : {-90., 90.})
		{
			Camera camera{240. * MistTerrain::pi / 180., pitch * MistTerrain::pi / 180., 210. * MistTerrain::pi / 180.};
			camera.fisheye = true;
			preview(mesh, camera, std::string(argv[1]) + (pitch < 0. ? "-nadir210" : "-zenith210") + ".ppm", .73);
			if (pitch < 0.) preview(mesh, camera, std::string(argv[1]) + "-nadir210-night.ppm", -.6);
		}
	}
	std::cout << "{\"generateMs\":" << generateMs << ",\"maximumViewMs\":" << maximumViewMs << ",\"vertices\":" << mesh.vertices.size()
	          << ",\"ordinaryViewMs\":" << ordinaryViewMs << ",\"triangles\":" << mesh.indices.size()/3 << ",\"maximumVertices\":" << maximumVertices << ",\"seamTriangles\":" << split.indices.size()/3
	          << ",\"optimizedMaximumMs\":" << optimizedMaximumMs << ",\"narrowProjected\":" << narrowProjected << ",\"narrowIndexBytes\":" << narrowIndices * 4
	          << ",\"referenceMeanMs\":" << referenceTotalMs / benchmarkViews << ",\"optimizedMeanMs\":" << optimizedTotalMs / benchmarkViews
	          << ",\"narrowReferenceMs\":" << narrowReferenceMs / narrowViews << ",\"narrowOptimizedMs\":" << narrowOptimizedMs / narrowViews
	          << ",\"fastEdgeChecks\":" << fastEdgeChecks << ",\"referenceEdgeChecks\":" << referenceEdgeChecks
	          << ",\"fastProjectionPixels\":" << fastProjectionPixels
	          << ",\"comparedPixels\":" << comparedPixels << ",\"flowVertices\":" << mesh.vertices.size() << "}\n";
	return 0;
}
