#include "../src/core/modules/AtmosphereGridStrip.hpp"
#include <algorithm>
#include <array>
#include <cassert>
#include <cmath>
#include <iostream>

using Triangle = std::array<std::uint32_t, 3>;

template<typename Index> static std::vector<Triangle> triangles(const std::vector<Index>& indices)
{
	std::vector<Triangle> result;
	for (std::size_t position = 2; position < indices.size(); ++position)
	{
		Triangle triangle{indices[position - 2], indices[position - 1], indices[position]};
		if (position % 2) std::swap(triangle[0], triangle[1]);
		if (triangle[0] != triangle[1] && triangle[0] != triangle[2] && triangle[1] != triangle[2])
			result.push_back(triangle);
	}
	return result;
}

static std::vector<Triangle> separateRows(unsigned int columns, unsigned int rows)
{
	std::vector<Triangle> result;
	for (unsigned int row = 0; row < rows; ++row)
	{
		std::vector<std::uint32_t> strip;
		for (unsigned int column = 0; column <= columns; ++column)
		{
			strip.push_back(row * (columns + 1) + column);
			strip.push_back((row + 1) * (columns + 1) + column);
		}
		const auto rowTriangles = triangles(strip);
		result.insert(result.end(), rowTriangles.begin(), rowTriangles.end());
	}
	return result;
}

template<typename Index> static void checkGeometry(unsigned int columns, unsigned int rows)
{
	const auto indices = AtmosphereGridStrip::build<Index>(columns, rows);
	const auto expected = separateRows(columns, rows);
	const auto actual = triangles(indices);
	assert(actual == expected);
	assert(actual.size() == std::size_t(columns) * rows * 2);
	assert(indices.size() == 2 * (std::size_t(columns) + 1) * rows + 2 * (rows - 1));
	assert((indices.size() - 2) - actual.size() == 4 * (rows - 1));
	for (const auto index : indices)
	{
		assert(index < (std::uint64_t(columns) + 1) * (rows + 1));
		assert(index != std::numeric_limits<Index>::max());
	}
	const auto position = [columns](std::uint32_t index)
	{
		const auto column = index % (columns + 1);
		const auto row = index / (columns + 1);
		return std::array<double, 2>{column == 0 ? 0. : column == columns ? double(columns) - 0.5 : double(column) - 0.5 * (row & 1), double(row)};
	};
	for (const auto& triangle : actual)
	{
		const auto first = position(triangle[0]);
		const auto second = position(triangle[1]);
		const auto third = position(triangle[2]);
		const double signedArea = (second[0] - first[0]) * (third[1] - first[1])
			- (second[1] - first[1]) * (third[0] - first[0]);
		assert(signedArea < 0.);
		const auto firstRow = triangle[0] / (columns + 1);
		const auto secondRow = triangle[1] / (columns + 1);
		const auto thirdRow = triangle[2] / (columns + 1);
		assert(std::max({firstRow, secondRow, thirdRow}) - std::min({firstRow, secondRow, thirdRow}) == 1);
	}
}

template<typename Action> static void expectOverflow(Action action)
{
	bool rejected = false;
	try { action(); }
	catch (const std::overflow_error&) { rejected = true; }
	assert(rejected);
}

int main()
{
	for (unsigned int columns = 1; columns <= 24; ++columns)
		for (unsigned int rows = 1; rows <= 24; ++rows)
			checkGeometry<std::uint16_t>(columns, rows);
	for (unsigned int columns : {29u, 38u, 51u, 61u, 68u, 91u})
		checkGeometry<std::uint16_t>(columns, 44);
	checkGeometry<std::uint16_t>(254, 256);
	checkGeometry<std::uint32_t>(255, 255);
	checkGeometry<std::uint32_t>(256, 256);
	assert(AtmosphereGridStrip::fitsUnsignedShort(254, 256));
	assert(!AtmosphereGridStrip::fitsUnsignedShort(255, 255));
	assert(!AtmosphereGridStrip::fitsUnsignedShort(256, 256));
	assert(!AtmosphereGridStrip::fitsUnsignedShort(~0u, ~0u));
	expectOverflow([] { AtmosphereGridStrip::build<std::uint16_t>(255, 255); });
	expectOverflow([] { AtmosphereGridStrip::build<std::uint16_t>(256, 256); });
	expectOverflow([] { AtmosphereGridStrip::build<std::uint32_t>(~0u, ~0u); });
	expectOverflow([] { AtmosphereGridStrip::build<std::uint32_t>(100000, 10000); });
	assert(AtmosphereGridStrip::build<std::uint16_t>(0, 44).empty());
	assert(AtmosphereGridStrip::build<std::uint16_t>(44, 0).empty());
	std::cout << "Atmosphere strip: 585 grids have identical ordered/wound triangles; ushort/restart/overflow and empty-grid checks passed\n";
}
