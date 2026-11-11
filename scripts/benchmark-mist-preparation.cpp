#define main terrainRegressionMain
#include "test-mist-terrain.cpp"
#undef main

int main(int argc, char** argv)
{
	const auto mesh = MistTerrain::generate();
	MistTerrain::ViewWorkspace workspace;
	MistTerrain::initializeWorkspace(mesh, workspace);
	std::ofstream samples;
	if (argc > 1) samples.open(argv[1], std::ios::binary);
	std::cout << "[";
	bool firstResult = true;
	for (bool fisheye : {false, true})
		for (double degrees : {12., 30., 60., 75., 100.})
		{
			double elapsed = 0.;
			std::size_t candidates = 0, midpoints = 0, projected = 0, triangles = 0;
			for (int frame = -12; frame < 72; ++frame)
			{
				const double heading = (55.44 + frame * 4.731) * MistTerrain::pi / 180.;
				const double pitch = (-13.02 + 6. * std::sin(frame * .17)) * MistTerrain::pi / 180.;
				Camera camera{heading, pitch, degrees * MistTerrain::pi / 180., 2560, 1600, fisheye};
				MistTerrain::ViewCone cone;
				cone.axis = {std::cos(pitch) * std::cos(heading), std::cos(pitch) * std::sin(heading), std::sin(pitch)};
				cone.radius = (fisheye ? camera.fov * .5 * std::hypot(1.6, 1.)
				                       : 2. * std::atan(std::tan(camera.fov * .25) * std::hypot(1.6, 1.))) + 3. * MistTerrain::pi / 180.;
				if (cone.radius >= MistTerrain::pi * .5) cone = MistTerrain::ViewCone{};
				const auto start = std::chrono::steady_clock::now();
				const auto& visible = MistTerrain::prepareVisibleMesh(mesh, workspace, camera,
					[](const Vertex&, const Vertex&) { return false; }, camera.width, camera.height, cone, true, true);
				const double milliseconds = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
				if (frame < 0) continue;
				elapsed += milliseconds;
				candidates += workspace.candidateTriangles;
				midpoints += workspace.midpointProjections;
				projected += workspace.projectedCount;
				triangles += visible.indices.size() / 3;
				if (samples.is_open() && frame % 12 == 0)
				{
					const auto depth = depthSamples(visible, camera);
					samples.write(reinterpret_cast<const char*>(depth.data()), depth.size() * sizeof(double));
				}
			}
			if (!firstResult) std::cout << ',';
			firstResult = false;
			std::cout << "{\"fisheye\":" << fisheye << ",\"fov\":" << degrees << ",\"meanMs\":" << elapsed / 72.
			          << ",\"candidates\":" << candidates / 72. << ",\"midpoints\":" << midpoints / 72.
			          << ",\"projected\":" << projected / 72. << ",\"triangles\":" << triangles / 72.
			          << ",\"blockBytes\":" << workspace.blocks.size() * sizeof(MistTerrain::MeshBlock) << '}';
		}
	std::cout << "]\n";
	return 0;
}
