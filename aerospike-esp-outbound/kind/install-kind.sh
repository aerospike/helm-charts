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

if [ ! -f "$WORKSPACE/aerospike-esp-outbound/kind/config/features.conf" ]; then
  echo "features.conf Not found"
  echo "Please create features.conf file with your Aerospike license"
  echo "You can copy it from another chart or create it manually"
  exit 1
fi

echo "Installing Kind"
kind create cluster --config "$WORKSPACE/aerospike-esp-outbound/kind/config/kind-cluster.yaml"
kubectl cluster-info --context kind-esp-test-cluster

echo "Deploying OLM"
curl -sL https://github.com/operator-framework/operator-lifecycle-manager/releases/download/v0.32.0/install.sh \
| bash -s v0.32.0

echo "Deploying AKO"
kubectl create -f https://operatorhub.io/install/aerospike-kubernetes-operator.yaml
echo "Waiting for AKO"
while true; do
  if kubectl --namespace operators get deployment/aerospike-operator-controller-manager &> /dev/null; then
    kubectl --namespace operators wait \
    --for=condition=available --timeout=180s deployment/aerospike-operator-controller-manager
    break
  fi
  sleep 2
done

echo "Grant permissions to the target namespace"
kubectl create namespace aerospike-test || true
kubectl --namespace aerospike-test create serviceaccount aerospike-operator-controller-manager || true
kubectl create clusterrolebinding aerospike-cluster-esp-test \
--clusterrole=aerospike-cluster --serviceaccount=aerospike-test:aerospike-operator-controller-manager || true

echo "Set Secrets for Aerospike Cluster"
kubectl --namespace aerospike-test create secret generic aerospike-secret \
--from-file=features.conf="$WORKSPACE/aerospike-esp-outbound/kind/config/features.conf" || \
kubectl --namespace aerospike-test create secret generic aerospike-secret \
--from-file=features.conf="$WORKSPACE/aerospike-esp-outbound/kind/config/features.conf" --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "✅ Kind cluster setup complete!"
echo ""
echo "Next steps:"
echo "1. Run integration test: cd integration-test && ./run-integration-test.sh"
echo "2. Or deploy ESP Outbound manually: helm install test-esp-outbound ../aerospike-esp-outbound --namespace aerospike-test"
echo ""
echo "To clean up: ./uninstall-kind.sh"

