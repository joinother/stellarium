#!/usr/bin/env bash
set -euo pipefail
[[ $(id -un) == root ]] || exit 77
stage=${1:?staging directory required}
[[ "$stage" == /var/tmp/sky-tle-deploy-* && -d "$stage" ]] || exit 2
cd "$stage"
sha256sum -c SHA256SUMS
node --check fetch-mirror.mjs
bash -n run-mirror.sh
[[ $(systemctl show -p MainPID --value tle-mirror.service) == 0 ]] || { echo 'Refresh still running'; exit 3; }
[[ -z $(find /srv/tle-mirror /opt/tle-mirror -type l -print -quit) ]] || { echo 'Unexpected symlink'; exit 4; }
backup=/var/backups/skyinstrument/tle-hardening-$(date -u +%Y%m%dT%H%M%SZ)
install -d -m 0700 "$backup"
cp -a /opt/tle-mirror "$backup/code"
cp -a /etc/systemd/system/tle-mirror.service /etc/systemd/system/tle-mirror.timer "$backup/"
if [[ -d /etc/systemd/system/tle-mirror.service.d ]]; then cp -a /etc/systemd/system/tle-mirror.service.d "$backup/"; fi
cp -a /etc/skyinstrument-website/nginx.conf "$backup/website-nginx.conf"
cp -a /srv/tle-mirror "$backup/data"
systemctl stop tle-mirror.timer
[[ $(systemctl show -p MainPID --value tle-mirror.service) == 0 ]] || { systemctl start tle-mirror.timer; exit 3; }
if ! getent passwd tle-mirror >/dev/null; then
  useradd --system --user-group --no-create-home --home-dir /nonexistent --shell /sbin/nologin tle-mirror
fi
[[ $(getent passwd tle-mirror | cut -d: -f7) == /sbin/nologin ]] || exit 5
[[ $(id -nG tle-mirror) == tle-mirror ]] || exit 5
install -o root -g root -m 0644 fetch-mirror.mjs /opt/tle-mirror/fetch-mirror.mjs
install -o root -g root -m 0644 sources.json /opt/tle-mirror/sources.json
install -o root -g root -m 0755 run-mirror.sh /opt/tle-mirror/run-mirror.sh
install -o root -g root -m 0644 publish-status.mjs /opt/tle-mirror/publish-status.mjs
install -o root -g root -m 0644 tle-mirror.service /etc/systemd/system/tle-mirror.service
install -o root -g root -m 0644 tle-mirror.timer /etc/systemd/system/tle-mirror.timer
install -o root -g root -m 0644 tle-mirror-status.service /etc/systemd/system/tle-mirror-status.service
install -o root -g root -m 0644 tle-mirror-status.timer /etc/systemd/system/tle-mirror-status.timer
if [[ -e /etc/systemd/system/tle-mirror.service.d/health.conf ]]; then
  mv /etc/systemd/system/tle-mirror.service.d/health.conf "$backup/disabled-health.conf"
fi
chown -R tle-mirror:tle-mirror /srv/tle-mirror
find /srv/tle-mirror -type d -exec chmod 0755 {} +
find /srv/tle-mirror -type f -exec chmod 0644 {} +
if [[ -d /srv/tle-mirror/.quarantine ]]; then chmod 0700 /srv/tle-mirror/.quarantine; fi
runuser -u tle-mirror -- test ! -w /opt/tle-mirror/fetch-mirror.mjs
runuser -u tle-mirror -- test ! -r /etc/nightwindow-api.env
runuser -u tle-mirror -- test -w /srv/tle-mirror
set +e
runuser -u tle-mirror -- /opt/tle-mirror/run-mirror.sh --validate-only > "$backup/migration.log" 2>&1
migration_status=$?
set -e
[[ $migration_status == 0 || $migration_status == 1 ]] || exit "$migration_status"
node -e 'const fs=require("fs"); const manifest=JSON.parse(fs.readFileSync("/srv/tle-mirror/v1/manifest.json")); if (!manifest.sources.every(source=>["fresh","stale","unavailable"].includes(source.status))) process.exit(1)'
install -o root -g root -m 0644 mirror-status.conf /etc/skyinstrument-website/conf.d/mirror-status.conf
nginx -t -c /etc/skyinstrument-website/nginx.conf
systemctl daemon-reload
systemd-analyze verify /etc/systemd/system/tle-mirror.service /etc/systemd/system/tle-mirror.timer /etc/systemd/system/tle-mirror-status.service /etc/systemd/system/tle-mirror-status.timer
nginx -s reload -c /etc/skyinstrument-website/nginx.conf
systemctl enable --now tle-mirror.timer
systemctl enable --now tle-mirror-status.timer
systemctl start tle-mirror-status.service
systemctl start --no-block tle-mirror.service
printf 'backup=%s\n' "$backup"
systemctl show tle-mirror.service -p User -p Group -p NoNewPrivileges -p ProtectSystem -p ReadWritePaths -p CapabilityBoundingSet -p EnvironmentFiles
