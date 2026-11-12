#!/usr/bin/env bash
set -euo pipefail

case ${1:-status} in
  status)
    remote_command='systemctl is-active skyinstrument-resources; curl -fsS --max-time 5 http://127.0.0.1:8080/healthz'
    ;;
  health)
    remote_command='curl -fsS --max-time 5 http://127.0.0.1:8080/healthz'
    ;;
  mirror)
    remote_command='systemctl show tle-mirror.service -p User -p Group -p Result -p ExecMainStatus -p MainPID; systemctl is-active tle-mirror.timer tle-mirror-status.timer; curl -fsS --max-time 5 --resolve skyinstrument.cn:443:127.0.0.1 https://skyinstrument.cn/v1/status.json'
    ;;
  capacity)
    remote_command='df -h /; free -m; uptime'
    ;;
  ports)
    remote_command='ss -lntu'
    ;;
  *)
    printf '%s\n' 'Usage: resource-server-cli.sh [status|health|mirror|capacity|ports]' >&2
    exit 2
    ;;
esac
[[ $# -le 1 ]] || { echo 'Additional arguments are not accepted' >&2; exit 2; }
remote_command='set -e; if [ "$(id -un)" != skyops ]; then echo "Unexpected session user; close the previous instance session before retrying" >&2; exit 77; fi; '"$remote_command"
exec workbench exec --instance-id i-uf68vk358s8l58afzswt --region cn-shanghai --profile skyinstrument --user-name skyops --timeout 15 --output json --command "$remote_command"
