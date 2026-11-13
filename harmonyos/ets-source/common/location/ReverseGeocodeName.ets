import { site } from '@kit.MapKit'

// Return only the smallest administrative division from a reverse-geocode
// address component: adminLevel5 → adminLevel4 → adminLevel3 → adminLevel2 →
// adminLevel1, then locality/city as a fallback. Streets, house numbers and
// formatted addresses are intentionally not concatenated; the pick card and
// the GPS label stay short.
export function smallestAdminDivision(component: site.AddressComponent): string {
  const levels: Array<string | undefined> = [
    component.adminLevel5,
    component.adminLevel4,
    component.adminLevel3,
    component.adminLevel2,
    component.adminLevel1
  ]
  for (const level of levels) {
    if (level !== undefined && level.length > 0) return level
  }
  return component.locality ?? component.city?.cityName ?? ''
}
