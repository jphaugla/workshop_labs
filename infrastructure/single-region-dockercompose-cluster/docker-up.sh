#?/bin/bash

export CRDB_VERSION="docker.io/cockroachdb/cockroach:latest"
export COMPANY=""
export ENTKEY=""

podman-compose up -d

sleep 120
