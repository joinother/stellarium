export const tle1 = '1 25544U 98067A   26306.43427755  .00005374  00000+0  10508-3 0  9999'
export const tle2 = '2 25544  51.6332 335.9757 0007139 339.3739  20.6961 15.49150046593183'
export const tle = `ISS (ZARYA)\n${tle1}\n${tle2}\n`
export const satnogs = JSON.stringify([{ norad_cat_id: 25544, tle0: '0 ISS (ZARYA)', tle1, tle2 }])
export const csvHeader = 'OBJECT_NAME,OBJECT_ID,EPOCH,MEAN_MOTION,ECCENTRICITY,INCLINATION,RA_OF_ASC_NODE,ARG_OF_PERICENTER,MEAN_ANOMALY,EPHEMERIS_TYPE,CLASSIFICATION_TYPE,NORAD_CAT_ID,ELEMENT_SET_NO,REV_AT_EPOCH,BSTAR,MEAN_MOTION_DOT,MEAN_MOTION_DDOT'
export const csvRow = '"ISS, \"\"ZARYA\"\"",1998-067A,2026-11-02T10:25:21.580320,15.49150046,0.0007139,51.6332,335.9757,339.3739,20.6961,0,U,25544,999,59318,0.00010508,0.00005374,0'
export const csv = `${csvHeader}\r\n${csvRow}\r\n`
export const json = JSON.stringify({ version: 1, nova: { fixture: { name: 'Fixture nova' } } })
export const csvSource = { id: 'satellites.csv.stations', format: 'csv',
  upstreamUrl: 'https://fixtures.invalid/stations.csv', mirrorPath: '/v1/catalogs/satellites/stations.csv' }
export const jsonSource = { id: 'catalog.novae', format: 'json',
  upstreamUrl: 'https://fixtures.invalid/novae.json', mirrorPath: '/v1/catalogs/novae.json' }
