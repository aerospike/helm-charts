#!/bin/bash -e
WORKSPACE="$(git rev-parse --show-toplevel)"
PROJECT=""
ZONE=""

if [ -z "$PROJECT" ]; then
    echo "Set Project"
    exit 1
fi

if [ -z "$ZONE" ]; then
    echo "set Zone"
    exit 1
fi

if [ ! -f "$WORKSPACE/aerospike-proximus/gke/config/features.conf" ]; then
  echo "features.conf Not found"
  exit 1
fi

echo "Install GKE "
gcloud config set project "$PROJECT"
gcloud container clusters create proximus-gke-cluster \
--zone "$ZONE" \
--num-nodes 3 \
--machine-type e2-standard-4
gcloud container clusters get-credentials proximus-gke-cluster --zone="$ZONE"

sleep 1m
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
--from-file=features.conf="$WORKSPACE/aerospike-proximus/gke/config/features.conf"
kubectl --namespace aerospike create secret generic auth-secret --from-literal=password='admin123'

echo "Add Storage Class"
kubectl apply -f https://raw.githubusercontent.com/aerospike/aerospike-kubernetes-operator/master/config/samples/storage/gce_ssd_storage_class.yaml

sleep 5s
echo "Deploy Aerospike Cluster"
kubectl apply -f "$WORKSPACE/aerospike-proximus/examples/gke/aerospike.yaml"

sleep 5s
echo "Waiting for Aerospike Cluster"
while true; do
  if  kubectl --namespace aerospike get pods --selector=statefulset.kubernetes.io/pod-name &> /dev/null; then
    kubectl --namespace aerospike wait pods \
    --selector=statefulset.kubernetes.io/pod-name --for=condition=ready --timeout=180s
    break
  fi
done

sleep 30s
echo "Deploy Proximus"
helm install as-proximus-gke "$WORKSPACE/aerospike-proximus" \
--values "$WORKSPACE/aerospike-proximus/examples/gke/as-proximus-gke-values.yaml" --namespace aerospike
