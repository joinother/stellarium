# Skyinstrument Dynamic Calendar Feed (Dual-Track Static Architecture)

Read-only static JSON feed served at `https://skyinstrument.cn/v1/calendar/` for injecting transient/editorial astronomy events (geomagnetic aurora alerts, bright perihelion comets, major spaceflight passes, and observing-note enrichments) into the HarmonyOS app's Astronomy Calendar without uploading any user location or device identity.

## Dual-Track Collection Model

1. **Automated Server Track (Zero-LLM, Zero-Hallucination, Unattended every 2h)**:
   - **NOAA SWPC Geomagnetic Aurora Alerts** (`--with-noaa`): merges `Kp >= 5` 3-hour storm slots into `aurora-alert` cards with local latitude filtering (`regionFilter.minLat`).
   - **MPC Bright Perihelion Comets** (`--mpc-comets /srv/tle-mirror/v1/catalogs/mpc/comets.txt`): reads the already-mirrored local MPC comet catalog (zero extra external fetches) and emits up to 3 active bright `comet-alert` cards (`peakMag <= 10.5`, perihelion within `[-45d, +60d]`). On the HarmonyOS client, receiving a `comet-alert` also triggers the silent closed-loop MPC comet orbit refresh (`MinorBodiesStore`).
2. **Curated Editorial Track (`curated-events.json`)**:
   - Major eclipses, meteor-shower observing guides (`enrich`), crewed spaceflight / Tiangong milestones, or event retractions (`retract`). Curated entries take precedence over auto-generated entries sharing the same `id`.

## Published Files

- `/v1/calendar/manifest.json` — lightweight check (`schemaVersion`, `generation`, `updatedAt`, `feedPath`, `bytes`, `sha256`), cached 5 min (`max-age=300, must-revalidate`)
- `/v1/calendar/feed-<generation>.json` — immutable generation payload verified via exact byte length + SHA-256 on device
- `/v1/calendar/feed.json` — latest copy for quick human inspection

## Zero-Privacy Design

- Clients perform read-only HTTPS `GET` requests with no cookies, no query params, no device identifier, and no coordinates.
- Geographic visibility rules (`regionFilter.minLat/maxLat/minLon/maxLon/regionIds`) are evaluated **100% locally** on the user's device.

## Generating & Validating Locally

```bash
# Validate curated entries only
node deploy/calendar-feed/build-calendar-feed.mjs --validate-only

# Dry-run combining curated entries + live NOAA + live skyinstrument.cn MPC comets
node deploy/calendar-feed/build-calendar-feed.mjs \
  --with-noaa \
  --mpc-comets https://skyinstrument.cn/v1/catalogs/mpc/comets.txt \
  --dry-run
```

## Deploying on `skyinstrument.cn` (Shanghai ECS)

```bash
install -d -o tle-mirror -g tle-mirror /opt/tle-mirror/calendar-feed /srv/tle-mirror/v1/calendar
install -m 644 -o tle-mirror -g tle-mirror deploy/calendar-feed/build-calendar-feed.mjs deploy/calendar-feed/curated-events.json /opt/tle-mirror/calendar-feed/
install -m 644 deploy/calendar-feed/skyinstrument-calendar-feed.service deploy/calendar-feed/skyinstrument-calendar-feed.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now skyinstrument-calendar-feed.timer
systemctl start skyinstrument-calendar-feed.service
curl -fsS https://skyinstrument.cn/v1/calendar/manifest.json
```
