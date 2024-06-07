#!/bin/bash -e
WORKSPACE="$(git rev-parse --show-toplevel)"

kubectl delete -f "$WORKSPACE"/aerospike-vector-search/eks/config/servicemonitor.yaml
helm uninstall kube-prometheus-stack --namespace monitoring
