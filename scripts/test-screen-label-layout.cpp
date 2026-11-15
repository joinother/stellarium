#include "../src/core/ScreenLabelLayout.hpp"
#include <cassert>
#include <iostream>
#include <random>

using Layout = ScreenLabelLayout;

static Layout::Candidate candidate(const std::string& id, Layout::Rect rect = {0, 0, 100, 20},
                                   int priority = 0, float magnitude = 1.f)
{
	return {id, rect, priority, magnitude, 1.f, {}, false};
}

static void testPriorityAndFade()
{
	Layout layout;
	for (int frame = 0; frame < 12; ++frame)
	{
		layout.beginFrame(1.f / 60.f);
		layout.add(candidate("dim", {0, 0, 100, 20}, 0, 5.f));
		layout.add(candidate("bright", {50, 0, 150, 20}, 0, 1.f));
		const auto alpha = layout.resolve();
		assert(alpha[0] == 0.f && alpha[1] > 0.f);
		assert(!layout.accepted("dim") && layout.accepted("bright"));
	}
	assert(layout.visibility("bright") == 1.f);
	layout.beginFrame(1.f / 60.f);
	layout.add(candidate("dim", {0, 0, 100, 20}, 10, 5.f));
	layout.add(candidate("bright", {50, 0, 150, 20}, 0, 1.f));
	const auto switched = layout.resolve();
	assert(switched[0] > 0.f && switched[0] < 0.2f);
	assert(switched[1] < 1.f && switched[1] > 0.8f);
	assert(layout.accepted("dim") && !layout.accepted("bright"));
	for (int frame = 0; frame < 12; ++frame)
	{
		layout.beginFrame(1.f / 60.f);
		layout.add(candidate("dim", {0, 0, 100, 20}, 10, 5.f));
		layout.add(candidate("bright", {50, 0, 150, 20}, 0, 1.f));
		layout.resolve();
	}
	assert(layout.visibility("dim") == 1.f && layout.visibility("bright") == 0.f);
	layout.beginFrame(0.f);
	layout.resolve();
	assert(layout.visibility("dim") == 0.f && !layout.accepted("dim"));
}

static void testIdentityOpacityAndOwners()
{
	Layout layout;
	layout.beginFrame(0.1f);
	auto label = candidate("dso:1:label");
	label.owner = "dso:1";
	label.opacity = 0.25f;
	auto hint = candidate("dso:1:hint");
	hint.owner = "dso:1";
	layout.add(label);
	layout.add(hint);
	layout.add(candidate("other"));
	auto alpha = layout.resolve();
	assert(alpha[0] > 0.f && alpha[1] > 0.f && alpha[2] == 0.f);
	assert(std::abs(layout.visibility(label.id) - alpha[0] * 0.25f) < 1.e-6f);
	layout.beginFrame(0.1f);
	auto selected = candidate("selected", {0, 0, 100, 20}, 100);
	selected.alwaysVisible = true;
	layout.add(selected);
	layout.add(label);
	layout.resolve();
	assert(layout.visibility("selected") == 1.f);
	assert(!layout.accepted(label.id));
	layout.beginFrame(0.1f);
	auto disabled = candidate("disabled", {0, 0, 100, 20}, 100);
	disabled.opacity = 0.f;
	layout.add(disabled);
	layout.add(candidate("visible"));
	layout.resolve();
	assert(layout.accepted("visible") && !layout.accepted("disabled"));
	layout.clear();
	assert(layout.visibility("visible") == 0.f);
}

static void testTimingAndMissingFrames()
{
	auto advance = [](float dt, int count)
	{
		Layout layout;
		for (int frame = 0; frame < count; ++frame)
		{
			layout.beginFrame(dt);
			layout.add(candidate("star"));
			layout.resolve();
		}
		return layout.visibility("star");
	};
	assert(std::abs(advance(1.f / 60.f, 6) - advance(1.f / 30.f, 3)) < 1.e-6f);
	Layout layout;
	for (int frame = 0; frame < 3; ++frame)
	{
		layout.beginFrame(0.1f);
		layout.add(candidate("star"));
		layout.resolve();
	}
	layout.beginFrame(0.f);
	layout.resolve();
	layout.beginFrame(0.01f);
	layout.add(candidate("star"));
	layout.resolve();
	assert(layout.visibility("star") < 0.1f);
	layout.beginFrame(10.f);
	layout.add(candidate("star"));
	layout.resolve();
	assert(layout.visibility("star") < 0.6f);
}

static void testGridAgainstBruteForce()
{
	std::mt19937 random(17);
	std::uniform_real_distribution<float> position(-500.f, 500.f);
	std::uniform_real_distribution<float> length(1.f, 180.f);
	for (int trial = 0; trial < 20; ++trial)
	{
		Layout layout;
		std::vector<Layout::Candidate> labels;
		for (int index = 0; index < 200; ++index)
		{
			const float left = position(random), bottom = position(random);
			labels.push_back(candidate(std::to_string(index), {left, bottom, left + length(random), bottom + length(random)},
			                           index % 3, static_cast<float>(index % 7)));
		}
		auto sorted = labels;
		std::sort(sorted.begin(), sorted.end(), [](const auto& lhs, const auto& rhs)
		{
			if (lhs.priority != rhs.priority) return lhs.priority > rhs.priority;
			if (lhs.magnitude != rhs.magnitude) return lhs.magnitude < rhs.magnitude;
			return lhs.id < rhs.id;
		});
		std::vector<Layout::Rect> occupied;
		std::unordered_set<std::string> expected;
		for (const auto& label : sorted)
		{
			const bool blocked = std::any_of(occupied.begin(), occupied.end(), [&](const auto& rect) { return rect.intersects(label.rect); });
			if (!blocked) { occupied.push_back(label.rect); expected.insert(label.id); }
		}
		std::shuffle(labels.begin(), labels.end(), random);
		layout.beginFrame(0.1f);
		for (const auto& label : labels) layout.add(label);
		layout.resolve();
		for (const auto& label : labels) assert(layout.accepted(label.id) == (expected.count(label.id) != 0));
	}
}

static void testInvalidAndEdges()
{
	Layout layout;
	layout.beginFrame(0.1f);
	layout.add(candidate("left", {-64, -64, 0, 0}));
	layout.add(candidate("right", {0, -64, 64, 0}));
	layout.add(candidate("invalid", {0, 0, std::numeric_limits<float>::infinity(), 20}, 100));
	layout.add(candidate("empty", {0, 0, 0, 0}, 100));
	layout.resolve();
	assert(layout.accepted("left") && layout.accepted("right"));
	assert(!layout.accepted("invalid") && !layout.accepted("empty"));
	assert(layout.visibility("unknown") == 0.f);
}

static void testHysteresis()
{
	Layout layout;
	layout.beginFrame(0.1f);
	layout.add(candidate("incumbent", {0, 0, 100, 20}, 0, 1.f));
	layout.resolve();
	layout.beginFrame(0.1f);
	layout.add(candidate("incumbent", {0, 0, 100, 20}, 0, 1.f));
	layout.add(candidate("challenger", {0, 0, 100, 20}, 0, 0.95f));
	layout.resolve();
	assert(layout.accepted("incumbent") && !layout.accepted("challenger"));
	layout.beginFrame(0.1f);
	layout.add(candidate("incumbent", {0, 0, 100, 20}, 0, 1.f));
	layout.add(candidate("challenger", {0, 0, 100, 20}, 0, 0.8f));
	layout.resolve();
	assert(!layout.accepted("incumbent") && layout.accepted("challenger"));
	layout.beginFrame(0.1f);
	layout.add(candidate("incumbent", {0, 0, 100, 20}, 1, 5.f));
	layout.add(candidate("challenger", {0, 0, 100, 20}, 0, 0.8f));
	layout.resolve();
	assert(layout.accepted("incumbent") && !layout.accepted("challenger"));
}

int main()
{
	testPriorityAndFade();
	testIdentityOpacityAndOwners();
	testTimingAndMissingFrames();
	testGridAgainstBruteForce();
	testInvalidAndEdges();
	testHysteresis();
	std::cout << "ScreenLabelLayout: 6 suites passed (including 4000 grid/brute-force comparisons)\n";
}
