/*
 * Stellarium
 * Copyright (C) 2026 Stellarium Developers
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#ifndef MOUSEPICKER_HPP
#define MOUSEPICKER_HPP

#include "TouchPicker.hpp"

class StelCore;

//! Mouse/trackpad adapter for the shared TouchPicker engine.
//! Uses a precise 25 device-pixel base radius and a 2-degree angular cap;
//! candidate visibility, DSO render state and ranking are shared with touch.
class MousePicker
{
public:
	//! Pick the object at a viewport-independent screen position without
	//! changing the current selection.
	//! @param core current StelCore
	//! @param xVp mouse x in viewport-independent pixels
	//! @param yVp mouse y in viewport-independent pixels
	//! @param skyW sky-surface width in vp
	//! @param skyH sky-surface height in vp
	//! @return ranked candidates and pick diagnostics
	static PickResult pickAt(const StelCore* core, int xVp, int yVp, int skyW, int skyH);

	//! Pick and select the object at a viewport-independent screen position.
	//! @param core current StelCore
	//! @param xVp mouse x in viewport-independent pixels
	//! @param yVp mouse y in viewport-independent pixels
	//! @param skyW sky-surface width in vp
	//! @param skyH sky-surface height in vp
	//! @param result optional pick diagnostics; found is cleared when selection fails
	//! @return true when an object was found and selected
	static bool pickAndSelect(const StelCore* core, int xVp, int yVp, int skyW, int skyH,
							  PickResult* result = nullptr);
};

#endif // MOUSEPICKER_HPP
