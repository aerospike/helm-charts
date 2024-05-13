#!/bin/bash -e

WORKSPACE="$(git rev-parse --show-toplevel)"

helm uninstall quote-semantic-search --namespace aerospike
helm uninstall as-quote-search --namespace aerospike
kubectl delete -f "$WORKSPACE/aerospike-proximus/examples/quote-search/aerospike.yaml"
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
