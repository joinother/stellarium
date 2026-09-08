#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>

inline std::uint64_t nextPresentationState(std::uint64_t previous, int frameWidth, int frameHeight,
                                            int surfaceWidth, int surfaceHeight)
{
    if (frameWidth <= 0 || frameHeight <= 0 || surfaceWidth <= 0 || surfaceHeight <= 0 ||
        frameWidth > 65535 || frameHeight > 65535)
        return 0;
    const bool matching = std::abs(double(frameWidth) * surfaceHeight / (double(frameHeight) * surfaceWidth) - 1) < 0.008;
    const std::uint64_t dimensions = (std::uint64_t(frameWidth) << 32) | (std::uint64_t(frameHeight) << 16);
    const unsigned count = matching ? ((previous >> 16) == (dimensions >> 16) ?
        std::min(2u, unsigned(previous & 0xffff) + 1) : 1) : 0;
    return dimensions | count;
}

struct PresentationViewport {
    int left;
    int bottom;
    int width;
    int height;
};

inline PresentationViewport fitPresentationFrame(int frameWidth, int frameHeight,
                                                 int surfaceWidth, int surfaceHeight)
{
    if (frameWidth <= 0 || frameHeight <= 0 || surfaceWidth <= 0 || surfaceHeight <= 0)
        return {0, 0, 0, 0};
    const double scale = std::min(double(surfaceWidth) / frameWidth, double(surfaceHeight) / frameHeight);
    const int width = std::max(1, std::min(surfaceWidth, int(std::lround(frameWidth * scale))));
    const int height = std::max(1, std::min(surfaceHeight, int(std::lround(frameHeight * scale))));
    return {(surfaceWidth - width) / 2, (surfaceHeight - height) / 2, width, height};
}
