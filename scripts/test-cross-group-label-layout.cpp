#include "../src/core/ScreenLabelLayout.hpp"
#include <cassert>
#include <cmath>
#include <iostream>

using Layout = ScreenLabelLayout;

static Layout::Candidate candidate(const std::string& id, const std::string& owner = {})
{
	return {id, {0.f, 0.f, 100.f, 20.f}, 0, 1.f, 1.f, owner, false};
}

static void testSameFrameOrderAndReset()
{
	Layout nebulae, stars;
	Layout::Occupancy occupied;
	nebulae.beginFrame(0.02f);
	stars.beginFrame(0.02f);
	nebulae.add(candidate("dso"));
	nebulae.resolve(&occupied, "nebulae");
	auto bright = candidate("star");
	bright.magnitude = -5.f;
	bright.priority = 100;
	stars.add(bright);
	stars.resolve(&occupied, "stars");
	assert(nebulae.accepted("dso") && !stars.accepted("star"));
	occupied.clear();
	nebulae.beginFrame(0.02f);
	stars.beginFrame(0.02f);
	assert(nebulae.visibility("dso") == 0.f);
	auto moved = candidate("dso");
	moved.rect = {200.f, 0.f, 300.f, 20.f};
	nebulae.add(moved);
	nebulae.resolve(&occupied, "nebulae");
	stars.add(bright);
	stars.resolve(&occupied, "stars");
	assert(nebulae.accepted("dso") && stars.accepted("star"));
	occupied.clear();
	nebulae.beginFrame(0.02f);
	stars.beginFrame(0.02f);
	assert(nebulae.visibility("dso") == 0.f);
	stars.add(moved);
	stars.resolve(&occupied, "stars");
	assert(stars.accepted("dso"));
}

static void testOwnerNamespaces()
{
	Layout nebulae, stars;
	Layout::Occupancy occupied;
	nebulae.beginFrame(0.02f);
	nebulae.add(candidate("label", "42"));
	nebulae.add(candidate("hint", "42"));
	nebulae.resolve(&occupied, "nebulae");
	assert(nebulae.accepted("label") && nebulae.accepted("hint"));
	stars.beginFrame(0.02f);
	stars.add(candidate("label", "42"));
	stars.resolve(&occupied, "stars");
	assert(!stars.accepted("label"));
	occupied.clear();
	nebulae.beginFrame(0.02f);
	nebulae.add(candidate("first", "b:c"));
	nebulae.resolve(&occupied, "a");
	stars.beginFrame(0.02f);
	stars.add(candidate("second", "c"));
	stars.resolve(&occupied, "a:b");
	assert(!stars.accepted("second"));
	occupied.clear();
	nebulae.beginFrame(0.02f);
	nebulae.add(candidate("first"));
	nebulae.add(candidate("second"));
	nebulae.resolve(&occupied, "nebulae");
	assert(nebulae.accepted("first") && !nebulae.accepted("second"));
}

static void testSelectedException()
{
	Layout nebulae, stars, satellites;
	Layout::Occupancy occupied;
	nebulae.beginFrame(0.02f);
	nebulae.add(candidate("earlier"));
	nebulae.resolve(&occupied, "nebulae");
	stars.beginFrame(0.02f);
	auto selected = candidate("selected");
	selected.alwaysVisible = true;
	selected.priority = std::numeric_limits<int>::max();
	selected.opacity = 0.4f;
	stars.add(candidate("ordinary"));
	stars.add(selected);
	stars.resolve(&occupied, "stars");
	assert(nebulae.accepted("earlier"));
	assert(stars.accepted("selected") && stars.visibility("selected") == 0.4f);
	assert(!stars.accepted("ordinary"));
	satellites.beginFrame(0.02f);
	satellites.add(candidate("later"));
	satellites.resolve(&occupied, "satellites");
	assert(!satellites.accepted("later"));
	occupied.clear();
	stars.beginFrame(0.02f);
	selected.opacity = 0.f;
	stars.add(selected);
	stars.resolve(&occupied, "stars");
	assert(stars.visibility("selected") == 0.f);
	satellites.beginFrame(0.02f);
	satellites.add(candidate("later"));
	satellites.resolve(&occupied, "satellites");
	assert(satellites.accepted("later"));
}

static void testIndependentFadeAndCurrentGeometry()
{
	Layout nebulae, stars, satellites;
	Layout::Occupancy occupied;
	for (int frame = 0; frame < 9; ++frame)
	{
		occupied.clear();
		nebulae.beginFrame(0.02f);
		stars.beginFrame(0.02f);
		stars.add(candidate("star"));
		stars.resolve(&occupied, "stars");
		assert(std::abs(stars.visibility("star") - (frame + 1) / 9.f) < 1.e-6f);
	}
	for (int frame = 0; frame < 9; ++frame)
	{
		occupied.clear();
		nebulae.beginFrame(0.02f);
		stars.beginFrame(0.02f);
		satellites.beginFrame(0.02f);
		nebulae.add(candidate("dso"));
		nebulae.resolve(&occupied, "nebulae");
		auto wide = candidate("star");
		wide.rect.right = 200.f;
		stars.add(wide);
		stars.resolve(&occupied, "stars");
		assert(!stars.accepted("star"));
		assert(std::abs(stars.visibility("star") - (8 - frame) / 9.f) < 1.e-6f);
		assert(std::abs(nebulae.visibility("dso") - (frame + 1) / 9.f) < 1.e-6f);
		auto outsideAccepted = candidate("sat");
		outsideAccepted.rect = {120.f, 0.f, 180.f, 20.f};
		satellites.add(outsideAccepted);
		satellites.resolve(&occupied, "satellites");
		assert(satellites.accepted("sat"));
	}
}

int main()
{
	Layout unused;
	for (int frame = 0; frame < 121; ++frame) unused.beginFrame(0.02f);
	assert(unused.isDormant());
	unused.add(candidate("returned"));
	unused.resolve();
	assert(!unused.isDormant());
	const auto stats = unused.statistics();
	assert(stats.candidates == 1 && stats.accepted == 1 && stats.visible == 1);
	testSameFrameOrderAndReset();
	testOwnerNamespaces();
	testSelectedException();
	testIndependentFadeAndCurrentGeometry();
	std::cout << "Cross-group layout: 4 suites passed\n";
}
