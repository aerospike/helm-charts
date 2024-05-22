#!/bin/bash -e
WORKSPACE="$(git rev-parse --show-toplevel)"

REQUISITES=("kubectl" "kind" "docker" "helm")
for item in "${REQUISITES[@]}"; do
  if [[ -z $(which "${item}") ]]; then
    echo "${item} cannot be found on your system, please install ${item}"
    exit 1
  fi
done

echo "Installing Kind"
kind create cluster
kubectl cluster-info --context kind-kind

echo "Deploy Aerospike Cluster And Minio"
docker compose --file "$WORKSPACE/aerospike-backup-service/examples/kind/docker-compose.yaml" up -d
docker compose --file "$WORKSPACE/aerospike-backup-service/examples/kind/config/credentials" up -d

kubectl create namespace aerospike
kubectl create secret generic credentials \
--namespace aerospike \
--from-file="$WORKSPACE/aerospike-backup-service/examples/kind/config/credentials"
kubectl create secret generic psw-cm \
--namespace aerospike \
--from-file="$WORKSPACE/aerospike-backup-service/examples/kind/config/psw.txt"

helm install backup-service "$WORKSPACE/aerospike-backup-service/" \
--namespace aerospike \
--values "$WORKSPACE/aerospike-backup-service/examples/kind/config/minio-values.yaml"
