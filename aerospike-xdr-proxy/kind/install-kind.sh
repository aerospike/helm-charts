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

# Check for local features.conf file on Jenkins box first
LOCAL_FEATURES_CONF="/var/lib/jenkins/aerospike-connect-resources/tests2/aerospike/features.conf"
FEATURES_CONF=""

if [ -f "$LOCAL_FEATURES_CONF" ]; then
  echo "Found local features.conf at: $LOCAL_FEATURES_CONF"
  FEATURES_CONF="$LOCAL_FEATURES_CONF"
elif [ -f "$WORKSPACE/aerospike-xdr-proxy/kind/config/features.conf" ]; then
  echo "Using features.conf from workspace: $WORKSPACE/aerospike-xdr-proxy/kind/config/features.conf"
  FEATURES_CONF="$WORKSPACE/aerospike-xdr-proxy/kind/config/features.conf"
else
  echo "features.conf Not found"
  echo "Please create features.conf file with your Aerospike license"
  echo "You can copy it from another chart or create it manually"
  echo "Expected locations:"
  echo "  - $LOCAL_FEATURES_CONF (Jenkins local)"
  echo "  - $WORKSPACE/aerospike-xdr-proxy/kind/config/features.conf (workspace)"
  exit 1
fi

echo "Installing Kind"
CONTEXT="kind-xdr-proxy-test-cluster"  # Explicit context for parallel execution safety
kind create cluster --config "$WORKSPACE/aerospike-xdr-proxy/kind/config/kind-cluster.yaml"
# kind create cluster automatically sets the context, but we'll use wrapper functions for safety

# Helper functions that automatically use the correct context
# This prevents race conditions when multiple scripts run in parallel
kubectl() {
    command kubectl --context="${CONTEXT}" "$@"
}

helm() {
    command helm --kube-context="${CONTEXT}" "$@"
}

kubectl cluster-info

echo "Deploying OLM"
# Check if OLM is already installed (idempotent check for parallel execution)
if ! kubectl get namespace olm &>/dev/null; then
    echo "Installing OLM..."
    curl -sL https://github.com/operator-framework/operator-lifecycle-manager/releases/download/v0.32.0/install.sh \
    | bash -s v0.32.0 || {
        echo "OLM installation had errors (may be due to parallel execution), checking if OLM is ready..."
    }
else
    echo "OLM namespace already exists, skipping installation"
fi

# Wait for OLM to be ready (handle race conditions from parallel execution)
echo "Waiting for OLM to initialize..."
for i in {1..60}; do
    if kubectl get namespace olm &>/dev/null && \
       kubectl wait --for=condition=Established --timeout=5s crd/clusterserviceversions.operators.coreos.com &>/dev/null && \
       kubectl wait --for=condition=available --timeout=5s deployment/olm-operator -n olm &>/dev/null; then
        echo "OLM is ready"
        break
    fi
    sleep 2
done

echo "Deploying AKO"
# Use idempotent apply instead of create to handle parallel execution
kubectl apply -f https://operatorhub.io/install/aerospike-kubernetes-operator.yaml || {
    echo "AKO installation had errors (may already exist), checking status..."
}
echo "Waiting for AKO"
for i in {1..90}; do
    if kubectl --namespace operators get deployment/aerospike-operator-controller-manager &>/dev/null; then
        kubectl --namespace operators wait \
        --for=condition=available --timeout=180s deployment/aerospike-operator-controller-manager && break
    fi
    sleep 2
done

echo "Grant permissions to the target namespace"
kubectl create namespace aerospike-test || true
kubectl --namespace aerospike-test create serviceaccount aerospike-operator-controller-manager || true
kubectl create clusterrolebinding aerospike-cluster-xdr-proxy-test \
--clusterrole=aerospike-cluster --serviceaccount=aerospike-test:aerospike-operator-controller-manager || true

echo "Set Secrets for Aerospike Cluster"
# Use idempotent apply to avoid race conditions when multiple install-kind.sh scripts run in parallel
kubectl --namespace aerospike-test create secret generic aerospike-secret \
--from-file=features.conf="$FEATURES_CONF" --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "✅ Kind cluster setup complete!"
echo ""
echo "Next steps:"
echo "1. Run integration test: cd ../tests/integration-test && ./run-integration-test.sh"
echo "2. Or deploy XDR Proxy manually: helm install test-xdr-proxy . --namespace aerospike-test"
echo ""
echo "To clean up: ./uninstall-kind.sh"
