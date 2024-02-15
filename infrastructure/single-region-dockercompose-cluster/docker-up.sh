#?/bin/bash

export CRDB_VERSION="cockroachdb/cockroach:latest"
export COMPANY=""
export ENTKEY=""
export XDG_CONFIG_HOME="/mnt"
export XDG_DATA_HOME="/mnt"

podman-compose up -d

sleep 120
