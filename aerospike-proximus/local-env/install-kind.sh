#!/bin/bash -e
GITHUB_TOKEN=""
FEATURES_CONF_URL=""
DOCKER_SERVER="https://aerospike.jfrog.io"
DOCKER_USERNAME=""
DOCKER_PASSWORD=""

mkdir -p "$(pwd)/secrets"
mkdir -p "$(pwd)/kind/volume"

echo "Downloading features.conf"
if [ ! -f "$(pwd)/secrets/features.conf" ]; then
  if [ -z "$GITHUB_TOKEN" ]; then
      echo "GITHUB_TOKEN env variable is not set, unable to download features.conf"
      exit 1
    fi

  if [ -z "$FEATURES_CONF_URL" ]; then
      echo "FEATURES_CONF_URL env variable is not set, unable to download features.conf"
      exit 1
    fi

  curl -s -H "Authorization: token $GITHUB_TOKEN" "$FEATURES_CONF_URL" \
  | tee "$(pwd)/secrets/features.conf" > "$(git rev-parse --show-toplevel)/aerospike-proximus/features.conf"
fi

echo "Installing Kind"
terraform -chdir="$(pwd)/kind" init -no-color -upgrade
terraform -chdir="$(pwd)/kind" apply -no-color -compact-warnings -auto-approve

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
kubectl --namespace aerospike create secret generic aerospike-secret --from-file="$(pwd)/secrets"
kubectl --namespace aerospike create secret generic auth-secret --from-literal=password='admin123'
kubectl --namespace aerospike create secret docker-registry regcred \
--docker-server="$DOCKER_SERVER" \
--docker-username="$DOCKER_USERNAME" \
--docker-password="$DOCKER_PASSWORD"


sleep 5s
echo "Deploy Aerospike Cluster"
kubectl apply -f "$(pwd)/config/aerospike-cluster.yaml"

sleep 5s
echo "Waiting for Aerospike Cluster"
while true; do
  if  kubectl --namespace aerospike get pods --selector=statefulset.kubernetes.io/pod-name &> /dev/null; then
    kubectl --namespace aerospike wait pods \
    --selector=statefulset.kubernetes.io/pod-name --for=condition=ready --timeout=180s
    break
  fi
done