#!/bin/bash -e
WORKSPACE="$(git rev-parse --show-toplevel)"
PROJECT="aerospike-dev"
ZONE=""
PASSWORD=""

mkdir -p "$WORKSPACE/aerospike-vector-search/examples/gke/secrets"

if [ -z "$PROJECT" ]; then
    echo "Set Project"
    exit 1
fi

if [ -z "$ZONE" ]; then
    echo "set Zone"
    exit 1
fi

if [ ! -f "$WORKSPACE/aerospike-vector-search/examples/gke/secrets/features.conf" ]; then
  echo "features.conf Not found"
  exit 1
fi

echo "Install GKE"
gcloud config set project "$PROJECT"
gcloud container clusters create avs-gke-cluster \
--zone "$ZONE" \
--project "$PROJECT" \
--num-nodes 3 \
--machine-type e2-standard-4
gcloud container clusters get-credentials avs-gke-cluster --zone="$ZONE"

sleep 60
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
--from-file="$WORKSPACE/aerospike-vector-search/examples/gke/secrets"

kubectl --namespace aerospike create secret generic auth-secret --from-literal=password='admin123'

echo "Add Storage Class"
kubectl apply -f https://raw.githubusercontent.com/aerospike/aerospike-kubernetes-operator/master/config/samples/storage/gce_ssd_storage_class.yaml

sleep 5
echo "Deploy Aerospike Cluster"
kubectl apply -f "$WORKSPACE/aerospike-vector-search/examples/gke/aerospike.yaml"

sleep 5
echo "Waiting for Aerospike Cluster"
while true; do
  if  kubectl --namespace aerospike get pods --selector=statefulset.kubernetes.io/pod-name &> /dev/null; then
    kubectl --namespace aerospike wait pods \
    --selector=statefulset.kubernetes.io/pod-name --for=condition=ready --timeout=180s
    break
  fi
done

echo "Deploying Istio"
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update

helm install istio-base istio/base --namespace istio-system --set defaultRevision=default --create-namespace --wait
helm install istiod istio/istiod --namespace istio-system --create-namespace --wait
helm install istio-ingress istio/gateway \
--values "$WORKSPACE/aerospike-vector-search/gke/config/istio-ingressgateway-values.yaml" \
--namespace istio-ingress \
--create-namespace \
--wait

kubectl apply -f "$WORKSPACE/aerospike-vector-search/gke/config/gateway.yaml"
kubectl apply -f "$WORKSPACE/aerospike-vector-search/gke/config/virtual-service-vector-search.yaml"

echo "Deploy AVS"
helm install avs-gke "$WORKSPACE/aerospike-vector-search" \
--values "$WORKSPACE/aerospike-vector-search/examples/gke/avs-gke-values.yaml" --namespace aerospike --wait

echo "Deploying Quote-Search"

docker run --name="quote-search" \
--rm \
--detach \
--env AVS_HOST="$(kubectl get svc/istio-ingress --namespace istio-ingress -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')" \
--env AVS_IS_LOADBALANCER="True" aerospike/quote-search-example:preview

echo "Run asvec cli"
asvec index ls \
-h "$(kubectl get svc/istio-ingress --namespace istio-ingress -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')" \
--log-level DEBUG
