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

#include "MousePicker.hpp"

#include "StelCore.hpp"
#include "StelModuleMgr.hpp"
#include "StelObjectMgr.hpp"
#include "StelProjector.hpp"
#include "TouchPicker.hpp"

PickResult MousePicker::pickAt(const StelCore* core, int xVp, int yVp, int skyW, int skyH)
{
	if (!core || skyW <= 0 || skyH <= 0)
		return PickResult();
	const StelProjectorP projector = core->getProjection(StelCore::FrameJ2000);
	if (!projector)
		return PickResult();
	const double dpr = static_cast<double>(projector->getViewportWidth())
		/ static_cast<double>(skyW);
	return TouchPicker::pickAt(core, xVp, yVp, skyW, skyH,
		TouchPicker::mouseProfile(dpr));
}

bool MousePicker::pickAndSelect(const StelCore* core, int xVp, int yVp, int skyW, int skyH,
								PickResult* result)
{
	PickResult pick = pickAt(core, xVp, yVp, skyW, skyH);
	if (result)
		*result = pick;
	if (!pick.found || pick.candidates.isEmpty())
		return false;
	StelObjectMgr* objectMgr = GETSTELMODULE(StelObjectMgr);
	if (!objectMgr || !pick.candidates.first().object)
		return false;
	const bool selected = objectMgr->setSelectedObject(pick.candidates.first().object);
	if (result && !selected)
		result->found = false;
	return selected;
}
