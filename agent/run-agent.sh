#!/usr/bin/env bash
# Run on the LOCAL machine: starts a Jenkins inbound agent that connects to the
# dev-server controller over WebSocket. Builds use a dedicated Docker-in-Docker
# daemon, so images/containers/cache never touch the host's Docker.
set -euo pipefail

cd "$(dirname "$0")"
[ -f .env ] && set -a && . ./.env && set +a

: "${JENKINS_URL:?set JENKINS_URL in agent/.env (e.g. https://jenkins.motcaigido.xyz/)}"
: "${JENKINS_SECRET:?set JENKINS_SECRET in agent/.env (from the node page in Jenkins)}"
JENKINS_AGENT_NAME="${JENKINS_AGENT_NAME:-local-builder}"
IMAGE="${AGENT_IMAGE:-jenkins-local-agent:latest}"
CONTAINER="${AGENT_CONTAINER:-jenkins-local-agent}"
DIND_CONTAINER="${AGENT_DIND_CONTAINER:-jenkins-local-agent-docker}"
NETWORK="${AGENT_NETWORK:-jenkins-local-agent}"
WORKDIR=/home/jenkins/agent

# Optional caps for the build daemon, e.g. AGENT_CPUS=8 AGENT_MEMORY=16g
LIMITS=()
[ -n "${AGENT_CPUS:-}" ] && LIMITS+=(--cpus "$AGENT_CPUS")
[ -n "${AGENT_MEMORY:-}" ] && LIMITS+=(--memory "$AGENT_MEMORY")

sudo docker build -t "$IMAGE" .
sudo docker network inspect "$NETWORK" >/dev/null 2>&1 || sudo docker network create "$NETWORK" >/dev/null
sudo docker rm -f "$CONTAINER" "$DIND_CONTAINER" >/dev/null 2>&1 || true
sudo docker run --rm --user root --entrypoint chown \
    --volume jenkins-local-agent-workdir:"$WORKDIR" "$IMAGE" jenkins:jenkins "$WORKDIR"

# Workspace is mounted at the same path in both containers so
# `docker run -v $WORKSPACE:...` resolves correctly inside the build daemon.
sudo docker run \
    --name "$DIND_CONTAINER" \
    --restart=always \
    --detach \
    --privileged \
    --network "$NETWORK" \
    --network-alias docker \
    "${LIMITS[@]}" \
    --env DOCKER_TLS_CERTDIR=/certs \
    --volume jenkins-local-agent-docker-certs:/certs/client \
    --volume jenkins-local-agent-docker-data:/var/lib/docker \
    --volume jenkins-local-agent-workdir:"$WORKDIR" \
    docker:dind \
    --storage-driver overlay2

sudo docker run \
    --name "$CONTAINER" \
    --restart=always \
    --detach \
    --init \
    --network "$NETWORK" \
    --env JENKINS_URL="$JENKINS_URL" \
    --env JENKINS_SECRET="$JENKINS_SECRET" \
    --env JENKINS_AGENT_NAME="$JENKINS_AGENT_NAME" \
    --env JENKINS_WEB_SOCKET=true \
    --env JENKINS_AGENT_WORKDIR="$WORKDIR" \
    --env DOCKER_HOST=tcp://docker:2376 \
    --env DOCKER_CERT_PATH=/certs/client \
    --env DOCKER_TLS_VERIFY=1 \
    --volume jenkins-local-agent-docker-certs:/certs/client:ro \
    --volume jenkins-local-agent-workdir:"$WORKDIR" \
    "$IMAGE"

echo "Agent '$JENKINS_AGENT_NAME' started."
echo "Logs:         sudo docker logs -f $CONTAINER"
echo "Build daemon: sudo docker exec $DIND_CONTAINER docker images"
