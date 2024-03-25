#!/bin/bash -e
WORKSPACE="$(git rev-parse --show-toplevel)"
kubectl --namespace aerospike create secret generic aerospike-proximus-secret --from-file=features.conf="$WORKSPACE/aerospike-proximus/local-env/secrets/features.conf"
helm install proximus "$WORKSPACE/aerospike-proximus" -f "$WORKSPACE/aerospike-proximus/local-env/config/values.yaml" -n aerospike
kubectl apply -f "$WORKSPACE/aerospike-proximus/local-env/config/aerospike-proximus-ingress.yaml"
