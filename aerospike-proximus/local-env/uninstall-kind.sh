#!/bin/bash -e

WORKSPACE="$(git rev-parse --show-toplevel)"

container_exists="$(docker ps -a -q -f name=^quote-search$)"
if [ ! -z "$container_exists" ]; then
    docker stop quote-search
    docker rm quote-search
  fi
if [ -d "$WORKSPACE/aerospike-proximus/proximus-examples" ]; then
    rm -rf "$WORKSPACE/aerospike-proximus/proximus-examples"
  fi

helm delete proximus --namespace aerospike
kubectl --namespace aerospike delete secret aerospike-proximus-secret
kubectl delete -f "$WORKSPACE/aerospike-proximus/local-env/config/metallb-config.yaml"
kubectl delete -f https://raw.githubusercontent.com/metallb/metallb/v0.14.4/config/manifests/metallb-native.yaml
kubectl delete -f "$WORKSPACE/aerospike-proximus/local-env/config/aerospike-cluster.yaml"
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
rm -f "$WORKSPACE/aerospike-proximus/local-env/secrets/features.conf"
