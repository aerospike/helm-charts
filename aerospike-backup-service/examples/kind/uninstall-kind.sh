#!/bin/bash -e
WORKSPACE="$(git rev-parse --show-toplevel)"


docker compose --file "$WORKSPACE/aerospike-backup-service/examples/kind/docker-compose.yaml" down
kind delete cluster