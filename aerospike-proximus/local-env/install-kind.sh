#!/bin/bash -e
WORKSPACE="$(git rev-parse --show-toplevel)"

if [ ! -f "$WORKSPACE/aerospike-proximus/local-env/secrets/features.conf" ]; then
  echo "features.conf Not found"
  exit 1
fi

echo "Installing Kind"
kind create cluster --config "$WORKSPACE/aerospike-proximus/local-env/config/kind-cluster.yaml"
kubectl cluster-info --context kind-kind

echo "Deploying AKO"
curl -sL https://github.com/operator-framework/operator-lifecycle-manager/releases/download/v0.25.0/install.sh \
| bash -s v0.25.0
kubectl create -f https://operatorhub.io/install/aerospike-kubernetes-operator.yaml
echo "Waiting for AKO"
while true; do
  if kubectl --namespace operators get deployment/aerospike-operator-controller-manager &> /dev/null; then
    kubectl --namespace operators wait \
    --for=condition=available --timeout=180s deployment/aerospike-operator-controller-manager
    break
  fi
done

echo "Grant permissions to the target namespace"
kubectl create namespace aerospike
kubectl --namespace aerospike create serviceaccount aerospike-operator-controller-manager
kubectl create clusterrolebinding aerospike-cluster \
--clusterrole=aerospike-cluster --serviceaccount=aerospike:aerospike-operator-controller-manager

echo "Set Secrets for Aerospike Cluster"
kubectl --namespace aerospike create secret generic aerospike-secret \
--from-file="$WORKSPACE/aerospike-proximus/local-env/secrets"
kubectl --namespace aerospike create secret generic auth-secret --from-literal=password='admin123'


sleep 5s
echo "Deploy Aerospike Cluster"
kubectl apply -f "$WORKSPACE/aerospike-proximus/local-env/config/aerospike-cluster.yaml"

sleep 5s
echo "Waiting for Aerospike Cluster"
while true; do
  if  kubectl --namespace aerospike get pods --selector=statefulset.kubernetes.io/pod-name &> /dev/null; then
    kubectl --namespace aerospike wait pods \
    --selector=statefulset.kubernetes.io/pod-name --for=condition=ready --timeout=180s
    break
  fi
done

echo "Deploy MetalLB"
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.4/config/manifests/metallb-native.yaml
kubectl wait --namespace metallb-system \
                --for=condition=ready pod \
                --selector=app=metallb \
                --timeout=90s
kubectl apply -f "$WORKSPACE/aerospike-proximus/local-env/config/metallb-config.yaml"

sleep 30s
echo "Deploy Proximus"
kubectl --namespace aerospike create secret generic aerospike-proximus-secret \
--from-file=features.conf="$WORKSPACE/aerospike-proximus/local-env/secrets/features.conf"
helm install proximus "$WORKSPACE/aerospike-proximus" \
--values "$WORKSPACE/aerospike-proximus/local-env/config/values.yaml" --namespace aerospike
