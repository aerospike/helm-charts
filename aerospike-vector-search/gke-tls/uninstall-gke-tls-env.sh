#!/bin/bash -e
WORKSPACE="$(git rev-parse --show-toplevel)"
PROJECT=""
ZONE=""

#rm -rf "$PWD/aerospike-vector-search-examples"
#helm uninstall quote-search --namespace aerospike
helm uninstall avs-gke --namespace aerospike
kubectl delete -f "$WORKSPACE/aerospike-vector-search/gke-tls/config/gateway.yaml"
kubectl delete -f "$WORKSPACE/aerospike-vector-search/gke-tls/config/virtual-service-vector-search.yaml"
helm uninstall istio-ingress --namespace istio-ingress
kubectl delete namespace istio-ingress
helm uninstall istiod --namespace istio-system
helm uninstall istio-base --namespace istio-system
kubectl delete namespace istio-system
kubectl delete -f "$WORKSPACE/aerospike-vector-search/examples/gke-tls/aerospike.yaml"
kubectl delete -f https://raw.githubusercontent.com/aerospike/aerospike-kubernetes-operator/master/config/samples/storage/gce_ssd_storage_class.yaml
kubectl --namespace aerospike delete secret auth-secret
kubectl --namespace aerospike delete secret aerospike-secret
kubectl --namespace aerospike delete secret aerospike-tls
kubectl delete clusterrolebinding aerospike-cluster
kubectl --namespace aerospike delete serviceaccount aerospike-operator-controller-manager
kubectl delete namespace aerospike
kubectl delete -f https://operatorhub.io/install/aerospike-kubernetes-operator.yaml
kubectl delete clusterserviceversion "$(kubectl get clusterserviceversion -o=jsonpath='{.items[0].metadata.name}')"
kubectl delete crd aerospikeclusters.asdb.aerospike.com
rm -rf "$WORKSPACE/aerospike-vector-search/examples/gke-tls/input"
rm -rf "$WORKSPACE/aerospike-vector-search/examples/gke-tls/output"
rm -rf "$WORKSPACE/aerospike-vector-search/examples/gke-tls/secrets"
gcloud container clusters delete avs-gke-cluster --project="$PROJECT" --zone="$ZONE" --quiet
