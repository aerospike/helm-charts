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

if [ ! -f "$WORKSPACE/aerospike-proximus/local-env/config/features.conf" ]; then
  echo "features.conf Not found"
  exit 1
fi

echo "Installing Kind"
#kind create cluster --config "$WORKSPACE/aerospike-proximus/local-env/config/kind-cluster.yaml"
kind create cluster
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
--from-file=features.conf="$WORKSPACE/aerospike-proximus/local-env/config/features.conf"
kubectl --namespace aerospike create secret generic auth-secret --from-literal=password='admin123'


sleep 5
echo "Deploy Aerospike Cluster"
kubectl apply -f "$WORKSPACE/aerospike-proximus/examples/quote-search/aerospike.yaml"

sleep 5
echo "Waiting for Aerospike Cluster"
while true; do
  if  kubectl --namespace aerospike get pods --selector=statefulset.kubernetes.io/pod-name &> /dev/null; then
    kubectl --namespace aerospike wait pods \
    --selector=statefulset.kubernetes.io/pod-name --for=condition=ready --timeout=180s
    break
  fi
done


#echo "Deploy MetalLB"
#kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.4/config/manifests/metallb-native.yaml
#kubectl wait --namespace metallb-system \
#                --for=condition=ready pod \
#                --selector=app=metallb \
#                --timeout=90s
#kubectl apply -f "$WORKSPACE/aerospike-proximus/local-env/config/metallb-config.yaml"

echo "Deploying Istio"
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update

helm install istio-base istio/base --namespace istio-system --set defaultRevision=default --create-namespace --wait
helm install istiod istio/istiod --namespace istio-system --create-namespace --wait
helm install istio-ingress istio/gateway --namespace istio-ingress --create-namespace --wait

#kubectl apply -f "$WORKSPACE/aerospike-proximus/local-env/config/virtual-service.yaml"
#echo "Deploy Nginx"
#kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
#kubectl wait --namespace ingress-nginx \
#  --for=condition=ready pod \
#  --selector=app.kubernetes.io/component=controller \
#  --timeout=90s

kubectl apply -f "$WORKSPACE/aerospike-proximus/local-env/config/gateway.yaml"
kubectl apply -f "$WORKSPACE/aerospike-proximus/local-env/config/virtual-service-quote-search.yaml"
kubectl apply -f "$WORKSPACE/aerospike-proximus/local-env/config/virtual-service-vector-search.yaml"

sleep 30
echo "Deploy Proximus"
helm install as-quote-search "$WORKSPACE/aerospike-proximus" \
--values "$WORKSPACE/aerospike-proximus/examples/quote-search/as-quote-search-values.yaml" --namespace aerospike

echo "Deploying Quote-Search"
helm install quote-semantic-search "$WORKSPACE/aerospike-proximus-examples/quote-semantic-search" \
--values "$WORKSPACE/aerospike-proximus/local-env/config/quote-semantic-search-values.yaml" --namespace aerospike --wait
