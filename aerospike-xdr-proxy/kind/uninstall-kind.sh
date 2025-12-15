#!/bin/bash -e

WORKSPACE="$(git rev-parse --show-toplevel)"
CONTEXT="kind-xdr-proxy-test-cluster"  # Explicit context for parallel execution safety

echo "Cleaning up XDR Proxy integration test environment..."

# Helper functions that automatically use the correct context
# This prevents race conditions when multiple scripts run in parallel
kubectl() {
    command kubectl --context="${CONTEXT}" "$@"
}

helm() {
    command helm --kube-context="${CONTEXT}" "$@"
}

# Verify context exists
if ! kubectl cluster-info &>/dev/null; then
    echo "⚠️  Warning: Cannot connect to cluster with context: ${CONTEXT}"
    echo "   Cluster may already be deleted or context doesn't exist"
    echo "   Continuing with cleanup anyway..."
fi

# Uninstall Helm releases
helm uninstall test-xdr-proxy --namespace aerospike-test 2>/dev/null || true

# Delete Aerospike clusters
kubectl delete aerospikecluster aerocluster-xdr-src aerocluster-xdr-dst -n aerospike-test 2>/dev/null || true

# Wait for clusters to be deleted
sleep 5

# Delete secrets
kubectl --namespace aerospike-test delete secret aerospike-secret 2>/dev/null || true
kubectl --namespace aerospike-test delete secret tls-certs-xdr-proxy 2>/dev/null || true

# Delete RBAC resources
kubectl delete clusterrolebinding aerospike-cluster-xdr-proxy-test 2>/dev/null || true
kubectl --namespace aerospike-test delete serviceaccount aerospike-operator-controller-manager 2>/dev/null || true

# Delete namespace
kubectl delete namespace aerospike-test 2>/dev/null || true

# Uninstall AKO
kubectl delete -f https://operatorhub.io/install/aerospike-kubernetes-operator.yaml 2>/dev/null || true

# Delete OLM CSV and CRD
kubectl delete clusterserviceversion "$(kubectl get clusterserviceversion -o=jsonpath='{.items[0].metadata.name}' 2>/dev/null)" 2>/dev/null || true
kubectl delete crd aerospikeclusters.asdb.aerospike.com 2>/dev/null || true

# Delete Kind cluster
kind delete cluster --name xdr-proxy-test-cluster 2>/dev/null || true

# Clean up Docker network (only if no other Kind clusters are using it)
if [ "$(kind get clusters 2>/dev/null | wc -l)" -eq 0 ]; then
    docker network rm kind 2>/dev/null || true
fi

echo ""
echo "✅ Cleanup complete!"
