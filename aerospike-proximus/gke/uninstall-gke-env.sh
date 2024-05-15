#!/bin/bash -e
WORKSPACE="$(git rev-parse --show-toplevel)"
ZONE=""

helm uninstall quote-semantic-search --namespace aerospike
helm uninstall as-proximus-gke --namespace aerospike
kubectl delete -f "$WORKSPACE/aerospike-proximus/gke/config/gateway.yaml"
kubectl delete -f "$WORKSPACE/aerospike-proximus/gke/config/virtual-service-vector-search.yaml"
helm uninstall istio-ingress --namespace istio-ingress
helm uninstall istiod --namespace istio-system
helm uninstall istio-base --namespace istio-system
kubectl delete -f "$WORKSPACE/aerospike-proximus/examples/gke/aerospike.yaml"
kubectl delete -f https://raw.githubusercontent.com/aerospike/aerospike-kubernetes-operator/master/config/samples/storage/gce_ssd_storage_class.yaml
kubectl --namespace aerospike delete secret auth-secret
kubectl --namespace aerospike delete secret aerospike-secret
kubectl delete clusterrolebinding aerospike-cluster
kubectl --namespace aerospike delete serviceaccount aerospike-operator-controller-manager
kubectl delete namespace aerospike
kubectl delete -f https://operatorhub.io/install/aerospike-kubernetes-operator.yaml
kubectl delete clusterserviceversion "$(kubectl get clusterserviceversion -o=jsonpath='{.items[0].metadata.name}')"
kubectl delete crd aerospikeclusters.asdb.aerospike.com
gcloud container clusters delete proximus-gke-cluster --zone="$ZONE" --quiet