#!/bin/bash -e
WORKSPACE="$(git rev-parse --show-toplevel)"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
--values "$WORKSPACE"/aerospike-vector-search/eks/config/kube-prometheus-stack-values.yaml \
--namespace monitoring \
--create-namespace \
--wait
kubectl apply -f "$WORKSPACE"/aerospike-vector-search/eks/config/servicemonitor.yaml

#kubectl port-forward service/kube-prometheus-stack-prometheus 9090 -n monitoring
