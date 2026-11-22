# Skyinstrument Dynamic Calendar Feed (Phase 1)

Read-only static JSON feed served at `https://skyinstrument.cn/v1/calendar/` for injecting transient/editorial astronomy events (geomagnetic aurora alerts, newly discovered comets, major spaceflight passes, and observing-note enrichments) into the HarmonyOS app's Astronomy Calendar without uploading any user location or device identity.

## Published Files

- `/v1/calendar/manifest.json` — lightweight check (`schemaVersion`, `generation`, `updatedAt`, `feedPath`, `bytes`, `sha256`)
- `/v1/calendar/feed-<generation>.json` — immutable generation payload verified via exact byte length + SHA-256 on device
- `/v1/calendar/feed.json` — latest copy for quick human inspection

## Zero-Privacy Design

- Clients perform read-only HTTPS `GET` requests with no cookies, no query params, no device identifier, and no coordinates.
- Geographic visibility rules (`regionFilter.minLat/maxLat/minLon/maxLon/regionIds`) are evaluated **100% locally** on the user's device.

## Generating & Validating Locally

```bash
# Validate curated entries only
node deploy/calendar-feed/build-calendar-feed.mjs --validate-only

# Build feed including live NOAA SWPC Kp>=5 geomagnetic aurora alerts
node deploy/calendar-feed/build-calendar-feed.mjs --with-noaa --out /tmp/calendar-v1
```

## Deploying on `skyinstrument.cn` (Shanghai ECS)

Write into the existing static `/v1/` directory (e.g. `/srv/tle-mirror/public/v1/calendar/`) via a low-privilege systemd timer (every 1–3 hours) running `build-calendar-feed.mjs --with-noaa --out /srv/tle-mirror/public/v1/calendar`. No database, extra open ports, or new Nginx virtual host is required.
