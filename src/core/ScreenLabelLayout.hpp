#ifndef SCREEN_LABEL_LAYOUT_HPP
#define SCREEN_LABEL_LAYOUT_HPP

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <numeric>
#include <limits>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

class ScreenLabelLayout
{
public:
	struct Rect
	{
		float left, bottom, right, top;
		bool intersects(const Rect& other) const
		{
			return left < other.right && right > other.left && bottom < other.top && top > other.bottom;
		}
	};
	struct Candidate
	{
		std::string id;
		Rect rect;
		int priority;
		float magnitude;
		float opacity = 1.f;
		std::string owner;
		bool alwaysVisible = false;
	};
	class Occupancy
	{
	public:
		void clear() { entries.clear(); cells.clear(); }
	private:
		friend class ScreenLabelLayout;
		struct Entry { Rect rect; std::string owner; std::string group; };
		std::vector<Entry> entries;
		std::unordered_map<std::uint64_t, std::vector<std::size_t>> cells;
	};

	void beginFrame()
	{
		const auto current = std::chrono::steady_clock::now();
		const float elapsed = std::chrono::duration<float>(current - lastFrame).count();
		lastFrame = current;
		beginFrame(elapsed);
	}

	void beginFrame(float elapsed)
	{
		if (!std::isfinite(elapsed) || elapsed > 1.f)
			states.clear();
		frameDelta = std::isfinite(elapsed) ? std::clamp(elapsed, 0.f, 0.1f) : 0.f;
		time += frameDelta;
		++generation;
		++unusedFrames;
		candidates.clear();
	}

	void add(const Candidate& candidate) { candidates.push_back(candidate); unusedFrames = 0; }
	bool isDormant() const { return unusedFrames > 120; }
	struct Stats { int candidates = 0; int accepted = 0; int visible = 0; };
	Stats statistics() const
	{
		Stats result;
		result.candidates = static_cast<int>(candidates.size());
		for (const auto& candidate : candidates)
		{
			result.accepted += accepted(candidate.id);
			result.visible += visibility(candidate.id) > 0.05f;
		}
		return result;
	}
	float visibility(const std::string& id) const
	{
		const auto found = states.find(id);
		return found != states.end() && found->second.generation == generation ? found->second.visibleAlpha : 0.f;
	}
	bool accepted(const std::string& id) const
	{
		const auto found = states.find(id);
		return found != states.end() && found->second.generation == generation && found->second.accepted;
	}
	bool isRecent() const
	{
		return std::chrono::duration<float>(std::chrono::steady_clock::now() - lastFrame).count() < 0.5f;
	}
	void clear() { states.clear(); candidates.clear(); }

	std::vector<float> resolve(Occupancy* shared = nullptr, const std::string& group = {})
	{
		Occupancy local;
		auto& occupancy = shared ? *shared : local;
		std::vector<float> result(candidates.size(), 0.f);
		std::vector<std::size_t> order(candidates.size());
		std::iota(order.begin(), order.end(), 0);
		std::stable_sort(order.begin(), order.end(), [&](std::size_t first, std::size_t second)
		{
			const auto& lhs = candidates[first];
			const auto& rhs = candidates[second];
			if (lhs.priority != rhs.priority) return lhs.priority > rhs.priority;
			const float lhsMag = (std::isfinite(lhs.magnitude) ? lhs.magnitude : 99.f) - (wasAccepted(lhs.id) ? 0.1f : 0.f);
			const float rhsMag = (std::isfinite(rhs.magnitude) ? rhs.magnitude : 99.f) - (wasAccepted(rhs.id) ? 0.1f : 0.f);
			if (lhsMag != rhsMag) return lhsMag < rhsMag;
			return lhs.id < rhs.id;
		});
		std::unordered_set<std::string> seen;
		const float step = frameDelta / 0.18f;
		for (const auto index : order)
		{
			const auto& candidate = candidates[index];
			const auto& rect = candidate.rect;
			if (!seen.insert(candidate.id).second || !valid(rect) || !std::isfinite(candidate.opacity) || candidate.opacity <= 0.f) continue;
			const int left = cell(rect.left), right = cell(rect.right);
			const int bottom = cell(rect.bottom), top = cell(rect.top);
			bool blocked = false;
			for (int row = bottom; row <= top && !blocked && !candidate.alwaysVisible; ++row)
				for (int column = left; column <= right && !blocked; ++column)
				{
					const auto found = occupancy.cells.find(cellKey(column, row));
					if (found != occupancy.cells.end())
						for (const auto other : found->second)
							if ((candidate.owner.empty() || candidate.owner != occupancy.entries[other].owner
								|| group != occupancy.entries[other].group)
								&& rect.intersects(occupancy.entries[other].rect)) { blocked = true; break; }
				}
			if (!blocked)
			{
				const auto occupiedIndex = occupancy.entries.size();
				occupancy.entries.push_back({rect, candidate.owner, group});
				for (int row = bottom; row <= top; ++row)
					for (int column = left; column <= right; ++column)
						occupancy.cells[cellKey(column, row)].push_back(occupiedIndex);
			}
			auto& state = states[candidate.id];
			if (state.generation + 1 != generation) state.alpha = 0.f;
			state.alpha = std::clamp(state.alpha + (blocked ? -step : step), 0.f, 1.f);
			if (candidate.alwaysVisible) state.alpha = 1.f;
			state.lastSeen = time;
			state.visibleAlpha = state.alpha * std::clamp(candidate.opacity, 0.f, 1.f);
			state.generation = generation;
			state.accepted = !blocked;
			result[index] = state.alpha;
		}
		for (auto entry = states.begin(); entry != states.end();)
			if (time - entry->second.lastSeen > 2.f) entry = states.erase(entry);
			else ++entry;
		return result;
	}

private:
	bool wasAccepted(const std::string& id) const
	{
		const auto found = states.find(id);
		return found != states.end() && found->second.generation + 1 == generation && found->second.accepted;
	}
	struct State
	{
		float alpha = 0.f;
		float visibleAlpha = 0.f;
		double lastSeen = 0.;
		std::uint64_t generation = 0;
		bool accepted = false;
	};
	static int cell(float coordinate) { return static_cast<int>(std::floor(coordinate / 64.f)); }
	static std::uint64_t cellKey(int column, int row)
	{
		return (std::uint64_t(static_cast<std::uint32_t>(column)) << 32) | static_cast<std::uint32_t>(row);
	}
	static bool valid(const Rect& rect)
	{
		return std::isfinite(rect.left) && std::isfinite(rect.right) && std::isfinite(rect.bottom) && std::isfinite(rect.top)
			&& rect.left < rect.right && rect.bottom < rect.top
			&& std::abs(rect.left) < 1.e7f && std::abs(rect.right) < 1.e7f
			&& std::abs(rect.bottom) < 1.e7f && std::abs(rect.top) < 1.e7f
			&& rect.right - rect.left < 16384.f && rect.top - rect.bottom < 16384.f;
	}
	std::vector<Candidate> candidates;
	std::unordered_map<std::string, State> states;
	std::chrono::steady_clock::time_point lastFrame = std::chrono::steady_clock::now();
	float frameDelta = 0.f;
	double time = 0.;
	std::uint64_t generation = 0;
	unsigned int unusedFrames = 0;
};

#endif
