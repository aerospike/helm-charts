#!/bin/bash -e
WORKSPACE="$(git rev-parse --show-toplevel)"

# Check prerequisites
REQUISITES=("kubectl" "kind" "docker" "helm")
for item in "${REQUISITES[@]}"; do
  if [[ -z $(which "${item}") ]]; then
    echo "${item} cannot be found on your system, please install ${item}"
    exit 1
  fi
done

if [ ! -f "$WORKSPACE/aerospike-proxy/kind/config/docker-config.json" ]; then
  echo "docker-config.json Not found"
  exit 1
fi

if [ ! -f "$WORKSPACE/aerospike-proxy/kind/config/features.conf" ]; then
  echo "features.conf Not found"
  exit 1
fi

echo "Installing Kind"
kind create cluster --config "$WORKSPACE/aerospike-proxy/kind/config/kind-cluster.yaml"
kubectl cluster-info --context kind-kind

echo "Deploying AKO"
curl -sL https://github.com/operator-framework/operator-lifecycle-manager/releases/download/v0.28.0/install.sh \
| bash -s v0.28.0
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
--from-file=features.conf="$WORKSPACE/aerospike-proxy/kind/config/features.conf"
kubectl --namespace aerospike create secret generic auth-secret --from-literal=password='admin123'

kubectl --namespace aerospike create secret generic regcred \
    --from-file=.dockerconfigjson="$WORKSPACE/aerospike-proxy/kind/config/docker-config.json" \
    --type=kubernetes.io/dockerconfigjson

sleep 5
echo "Deploy Aerospike Cluster"
kubectl apply -f "$WORKSPACE/aerospike-proxy/examples/kind/aerospike.yaml"

sleep 5
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
kubectl apply -f "$WORKSPACE/aerospike-proxy/kind/config/metallb-config.yaml"


echo "Deploying Istio"
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update
helm install istio-base istio/base --namespace istio-system --set defaultRevision=default --create-namespace --wait
helm install istiod istio/istiod --namespace istio-system --create-namespace --wait
helm install istio-ingress istio/gateway \
--values "$WORKSPACE/aerospike-proxy/kind/config/istio-ingressgateway-values.yaml" \
--namespace istio-ingress \
--create-namespace \
--wait

kubectl apply -f "$WORKSPACE/aerospike-proxy/kind/config/gateway.yaml"
kubectl apply -f "$WORKSPACE/aerospike-proxy/kind/config/virtual-service-proxy.yaml"

echo "Installing Aerospike Proxy"
helm install proxy "$WORKSPACE/aerospike-proxy" \
--values "$WORKSPACE/aerospike-proxy/examples/kind/proxy-kind-values.yaml" --namespace aerospike --wait