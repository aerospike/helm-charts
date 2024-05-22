#!/bin/bash -e

WORKSPACE="$(git rev-parse --show-toplevel)"

helm uninstall quote-search --namespace aerospike
helm uninstall avs --namespace aerospike
kubectl delete -f "$WORKSPACE/aerospike-proximus/kind/config/virtual-service-vector-search.yaml"
kubectl delete -f "$WORKSPACE/aerospike-proximus/kind/config/gateway.yaml"
helm uninstall istio-ingress --namespace istio-ingress
kubectl delete namespace istio-ingress
helm uninstall istiod --namespace istio-system
helm uninstall istio-base --namespace istio-system
kubectl delete namespace istio-system
kubectl delete -f "$WORKSPACE/aerospike-proximus/kind/config/metallb-config.yaml"
kubectl delete -f https://raw.githubusercontent.com/metallb/metallb/v0.14.4/config/manifests/metallb-native.yaml
kubectl delete -f "$WORKSPACE/aerospike-proximus/examples/kind/aerospike.yaml"
kubectl --namespace aerospike delete secret auth-secret
kubectl --namespace aerospike delete secret aerospike-secret
kubectl delete clusterrolebinding aerospike-cluster
kubectl --namespace aerospike delete serviceaccount aerospike-operator-controller-manager
kubectl delete namespace aerospike
kubectl delete -f https://operatorhub.io/install/aerospike-kubernetes-operator.yaml
kubectl delete clusterserviceversion "$(kubectl get clusterserviceversion -o=jsonpath='{.items[0].metadata.name}')"
kubectl delete crd aerospikeclusters.asdb.aerospike.com
kind delete cluster
docker network rm kind
