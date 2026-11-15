#include "../src/core/ScreenLabelLayout.hpp"
#include "../src/core/MarkerVisibility.hpp"
#include <cassert>
#include <cmath>

static ScreenLabelLayout::Candidate marker(const std::string& owner, bool label, int priority, float magnitude,
                                          float opacity = 1.f, bool selected = false)
{
	return {owner + (label ? ":label" : ":hint"), {0.f, 0.f, 40.f, 30.f}, priority, magnitude, opacity, owner, selected};
}

int main()
{
	ScreenLabelLayout layout;
	const auto named = marker("dso:42", false, 1, 9.f);
	const auto bright = marker("dso:43", false, 0, 2.f);
	for (int frame = 0; frame < 12; ++frame)
	{
		layout.beginFrame(0.02f);
		layout.add(bright);
		layout.add(named);
		layout.resolve();
		assert(layout.accepted(named.id));
		assert(!layout.accepted(bright.id));
	}
	assert(layout.visibility(named.id) == 1.f);
	assert(layout.visibility(bright.id) == 0.f);
	const auto selected = marker("dso:43", false, 100, 2.f, 1.f, true);
	float previous = 1.f;
	for (int frame = 0; frame < 12; ++frame)
	{
		layout.beginFrame(0.02f);
		layout.add(named);
		layout.add(selected);
		layout.resolve();
		assert(layout.visibility(selected.id) == 1.f);
		assert(layout.visibility(named.id) <= previous);
		assert(previous - layout.visibility(named.id) <= 0.112f);
		assert(!layout.accepted(named.id));
		previous = layout.visibility(named.id);
	}
	assert(previous == 0.f);
	layout.clear();
	const float thresholdAlpha = MarkerVisibility::magnitudeOpacity(9.625f, 10.f) * 0.4f;
	const auto hint = marker("dso:42", false, 1, 9.625f, thresholdAlpha);
	const auto label = marker("dso:42", true, 1, 9.625f, thresholdAlpha);
	for (int frame = 0; frame < 12; ++frame)
	{
		layout.beginFrame(0.02f);
		layout.add(hint);
		layout.add(label);
		layout.resolve();
		assert(layout.accepted(hint.id) && layout.accepted(label.id));
	}
	assert(std::abs(layout.visibility(hint.id) - 0.2f) < 1e-6f);
	assert(std::abs(layout.visibility(label.id) - 0.2f) < 1e-6f);
	layout.beginFrame(0.f);
	layout.add(hint);
	layout.resolve();
	assert(layout.visibility(label.id) == 0.f);
	assert(layout.visibility(hint.id) > 0.f);
	layout.beginFrame(0.02f);
	layout.add(hint);
	layout.add(label);
	layout.resolve();
	assert(layout.visibility(hint.id) > layout.visibility(label.id));
	layout.clear();
	for (int frame = 0; frame < 12; ++frame)
	{
		layout.beginFrame(0.02f);
		layout.add(marker("dso:2", false, 0, 5.f));
		layout.add(marker("dso:1", false, 0, 5.f));
		layout.resolve();
		assert(layout.accepted("dso:1:hint"));
		assert(!layout.accepted("dso:2:hint"));
	}
	layout.beginFrame(0.02f);
	layout.resolve();
	assert(layout.visibility("dso:1:hint") == 0.f);
}
