#!/usr/bin/env bash
# Migrate the Jenkins controller (jenkins-data volume) from this local machine to the dev server.
#
#   bash migrate-to-dev.sh precheck   # read-only checks on both machines
#   bash migrate-to-dev.sh image      # build the Jenkins image on dev (same pinned core version)
#   bash migrate-to-dev.sh sync       # bulk copy while local Jenkins keeps running (repeatable)
#   bash migrate-to-dev.sh cutover    # stop local, final sync, start on dev, switch nginx
#   bash migrate-to-dev.sh rollback   # stop dev Jenkins, point nginx back, start local
set -euo pipefail

DEV_HOST="${DEV_HOST:-ubuntu@42.112.59.88}"
VOLUME="${VOLUME:-jenkins-data}"
IMAGE="${IMAGE:-myjenkins-blueocean:lts}"
NGINX_CONF="${NGINX_CONF:-/etc/nginx/sites-enabled/jenkins.motcaigido.xyz.conf}"
OLD_UPSTREAM="${OLD_UPSTREAM:-http://office.toncorp.io:30006}"
NEW_UPSTREAM="${NEW_UPSTREAM:-http://127.0.0.1:30006}"
STAMP="$(date +%Y%m%d-%H%M%S)"

SRC="/var/lib/docker/volumes/${VOLUME}/_data/"
DST="/var/lib/docker/volumes/${VOLUME}/_data/"

# Rebuildable data, not worth transferring.
EXCLUDES=(
  --exclude=/workspace/
  --exclude=/caches/
  --exclude=/war/
  --exclude=/.cache/
  --exclude=/plugins/*/
  --exclude=/jobs/**/workspace*/
  --exclude=/.migrated-from-local
)

remote() { ssh -o ConnectTimeout=10 "$DEV_HOST" "$@"; }
log() { printf '\n==> %s\n' "$*"; }

do_rsync() {
  # rsync needs root locally to read the volume; keep the user's ssh-agent and known_hosts for the remote side.
  sudo --preserve-env=SSH_AUTH_SOCK rsync -aHAXz --numeric-ids --delete --partial --info=progress2 "${EXCLUDES[@]}" \
    -e "ssh -o ConnectTimeout=10 -o UserKnownHostsFile=$HOME/.ssh/known_hosts" --rsync-path="sudo rsync" \
    "$SRC" "${DEV_HOST}:${DST}"
}

precheck() {
  log "Local"
  docker exec jenkins-blueocean sh -c 'echo "Jenkins $JENKINS_VERSION"; du -sh /var/jenkins_home'
  sudo test -d "$SRC" && echo "volume path OK: $SRC"
  log "Dev server ($DEV_HOST)"
  remote "set -e; hostname; sudo -n true && echo 'sudo OK'; which rsync docker; df -h /var/lib/docker | tail -1
          sudo -n ss -ltn | grep -E ':30006\b' && echo 'WARN: port 30006 in use' || echo 'port 30006 free'
          sudo -n docker ps -a --format '{{.Names}}' | grep -E '^jenkins-' || echo 'no jenkins containers'
          if sudo -n test -f ${DST}config.xml; then echo 'WARN: existing Jenkins data on dev, will be moved to _data.bak-<ts> on first sync'; fi
          grep -n proxy_pass ${NGINX_CONF}"
}

image() {
  log "Building ${IMAGE} on dev"
  tar -C "$(dirname "$0")" -cf - Dockerfile | remote "sudo docker build --progress=plain -t ${IMAGE} -"
}

prepare_remote_volume() {
  remote "set -e
    sudo docker volume inspect ${VOLUME} >/dev/null 2>&1 || sudo docker volume create ${VOLUME} >/dev/null
    if sudo test -f ${DST}config.xml && ! sudo test -f ${DST}.migrated-from-local; then
      echo 'Backing up existing dev Jenkins data -> _data.bak-${STAMP}'
      sudo mv /var/lib/docker/volumes/${VOLUME}/_data /var/lib/docker/volumes/${VOLUME}/_data.bak-${STAMP}
      sudo mkdir /var/lib/docker/volumes/${VOLUME}/_data
    fi
    sudo touch ${DST}.migrated-from-local"
}

sync() {
  if remote "sudo docker ps --format '{{.Names}}' | grep -qx jenkins-blueocean"; then
    echo "Jenkins is already running on dev, refusing to sync over it." >&2; exit 1
  fi
  prepare_remote_volume
  log "rsync local -> dev (Jenkins still running locally)"
  do_rsync
}

cutover() {
  remote "sudo docker image inspect ${IMAGE} >/dev/null" || { echo "Run '$0 image' first." >&2; exit 1; }
  cat <<EOF

Before continuing, in the local Jenkins UI: Manage Jenkins > Prepare for Shutdown,
and wait until no builds are running.
EOF
  read -rp "Type 'yes' to stop local Jenkins and cut over: " ans
  [ "$ans" = "yes" ] || exit 1

  log "Stopping local Jenkins"
  docker stop jenkins-blueocean

  sync

  log "Starting Jenkins on dev"
  remote "JENKINS_BIND=127.0.0.1 bash -s" < "$(dirname "$0")/deploy.sh"

  log "Waiting for Jenkins on dev"
  remote 'for i in $(seq 1 60); do code=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:30006/login); [ "$code" = 200 ] && echo "up" && exit 0; sleep 5; done; echo "timeout" >&2; exit 1'

  log "Switching nginx upstream -> ${NEW_UPSTREAM}"
  remote "set -e; sudo cp ${NGINX_CONF} /tmp/jenkins.nginx.bak-${STAMP}
    sudo sed -i 's#proxy_pass ${OLD_UPSTREAM};#proxy_pass ${NEW_UPSTREAM};#' ${NGINX_CONF}
    sudo nginx -t && sudo systemctl reload nginx; grep -n proxy_pass ${NGINX_CONF}"

  log "Done. Open https://jenkins.motcaigido.xyz and verify. Local volume ${VOLUME} is kept for rollback."
}

rollback() {
  log "Stopping Jenkins on dev"
  remote "sudo docker rm -f jenkins-blueocean jenkins-docker || true"
  log "Switching nginx upstream back -> ${OLD_UPSTREAM}"
  remote "set -e; sudo sed -i 's#proxy_pass ${NEW_UPSTREAM};#proxy_pass ${OLD_UPSTREAM};#' ${NGINX_CONF}
    sudo nginx -t && sudo systemctl reload nginx"
  log "Starting local Jenkins"
  docker start jenkins-blueocean
}

case "${1:-}" in
  precheck|image|sync|cutover|rollback) "$1" ;;
  *) sed -n '2,9p' "$0"; exit 1 ;;
esac
