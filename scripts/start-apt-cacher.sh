#!/usr/bin/env bash
# Start apt-cacher-ng in Docker to speed up pi-gen rebuilds.
# Set APT_PROXY=http://host.docker.internal:3142 in pi-gen's config to use it.
set -eu

NAME="apt-cacher-ng"
PORT="3142"
IMAGE="sameersbn/apt-cacher-ng"
VOLUME="apt-cacher-ng-cache"

if docker ps --format '{{.Names}}' | grep -qx "${NAME}"; then
	echo "${NAME} is already running on port ${PORT}."
	exit 0
fi

if docker ps -a --format '{{.Names}}' | grep -qx "${NAME}"; then
	echo "Starting existing ${NAME} container..."
	docker start "${NAME}"
else
	echo "Creating and starting ${NAME} container..."
	docker run -d \
		--name "${NAME}" \
		--restart=always \
		-p "${PORT}:3142" \
		-v "${VOLUME}:/var/cache/apt-cacher-ng" \
		"${IMAGE}"
fi

echo
echo "Waiting for apt-cacher-ng to accept connections..."
for _ in $(seq 1 20); do
	if curl -fsS -o /dev/null "http://localhost:${PORT}/acng-report.html"; then
		echo "Ready."
		echo
		echo "Set in pi-gen config:"
		echo "    APT_PROXY=http://host.docker.internal:${PORT}"
		echo
		echo "Web status: http://localhost:${PORT}/acng-report.html"
		exit 0
	fi
	sleep 1
done

echo "apt-cacher-ng did not become ready in time. Check: docker logs ${NAME}" >&2
exit 1
