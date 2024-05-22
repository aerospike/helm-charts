#!/bin/bash -e
WORKSPACE="$(git rev-parse --show-toplevel)"

helm uninstall backup-service --namespace aerospike
kubectl delete secret --namespace aerospike psw-cm
kubectl delete secret --namespace aerospike credentials
kubectl delete namespace aerospike
docker compose --file "$WORKSPACE/aerospike-backup-service/examples/kind/docker-compose.yaml" down
kind delete cluster