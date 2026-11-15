#ifndef ATMOSPHERE_GRID_STRIP_HPP
#define ATMOSPHERE_GRID_STRIP_HPP

#include <cstdint>
#include <limits>
#include <stdexcept>
#include <type_traits>
#include <vector>

namespace AtmosphereGridStrip
{
inline bool fitsUnsignedShort(unsigned int columns, unsigned int rows)
{
	return std::uint64_t(columns) + 1 <= std::numeric_limits<std::uint16_t>::max() / (std::uint64_t(rows) + 1);
}

template<typename Index> std::vector<Index> build(unsigned int columns, unsigned int rows)
{
	static_assert(std::is_same_v<Index, std::uint16_t> || std::is_same_v<Index, std::uint32_t>);
	if (columns == 0 || rows == 0) return {};
	const std::uint64_t stride = std::uint64_t(columns) + 1;
	if (stride > std::numeric_limits<Index>::max() / (std::uint64_t(rows) + 1))
		throw std::overflow_error("Atmosphere grid exceeds index range including primitive restart reservation");
	const std::uint64_t indexCount = 2 * stride * rows + 2 * (std::uint64_t(rows) - 1);
	if (indexCount > std::numeric_limits<int>::max() / sizeof(Index))
		throw std::overflow_error("Atmosphere grid exceeds buffer size range");
	std::vector<Index> indices;
	indices.reserve(static_cast<std::size_t>(indexCount));
	for (unsigned int row = 0; row < rows; ++row)
	{
		const std::uint64_t upper = std::uint64_t(row) * stride;
		const std::uint64_t lower = upper + stride;
		if (row != 0)
		{
			indices.push_back(indices.back());
			indices.push_back(static_cast<Index>(upper));
		}
		for (unsigned int column = 0; column <= columns; ++column)
		{
			indices.push_back(static_cast<Index>(upper + column));
			indices.push_back(static_cast<Index>(lower + column));
		}
	}
	return indices;
}
}

#endif
