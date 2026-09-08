#include "PresentationGeometry.h"
#include <cassert>
#include <cmath>

int main()
{
    auto state = nextPresentationState(0, 1023, 767, 2560, 1600);
    assert((state & 0xffff) == 0);
    state = nextPresentationState(state, 2560, 1600, 2560, 1600);
    assert((state & 0xffff) == 1);
    state = nextPresentationState(state, 2560, 1600, 2560, 1600);
    assert((state & 0xffff) == 2 && (state >> 32) == 2560 && ((state >> 16) & 0xffff) == 1600);
    assert((nextPresentationState(state, 2560, 1600, 1600, 2560) & 0xffff) == 0);
    assert((nextPresentationState(state, 1600, 2560, 1600, 2560) & 0xffff) == 1);
    assert(nextPresentationState(state, 0, 0, 2560, 1600) == 0);
    assert(fitPresentationFrame(0, 100, 2560, 1600).width == 0);
    const auto full = fitPresentationFrame(2560, 1600, 2560, 1600);
    assert(full.width == 2560 && full.height == 1600 && full.left == 0 && full.bottom == 0);
    const auto initial = fitPresentationFrame(1023, 767, 2560, 1600);
    assert(initial.width < 2560 && initial.height == 1600 && initial.left > 0);
    for (const auto frameWidth : {767, 1023, 1600, 2560}) {
        for (const auto frameHeight : {767, 1023, 1600, 2560}) {
            for (const auto surfaceWidth : {360, 800, 1600, 2560}) {
                for (const auto surfaceHeight : {640, 800, 1600, 2560}) {
                    const auto viewport = fitPresentationFrame(frameWidth, frameHeight, surfaceWidth, surfaceHeight);
                    assert(viewport.left >= 0 && viewport.bottom >= 0);
                    assert(viewport.left + viewport.width <= surfaceWidth);
                    assert(viewport.bottom + viewport.height <= surfaceHeight);
                    const double expectedWidth = double(viewport.height) * frameWidth / frameHeight;
                    assert(std::abs(expectedWidth - viewport.width) < 2.2);
                }
            }
        }
    }
}
