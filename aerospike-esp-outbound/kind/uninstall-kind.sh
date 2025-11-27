#!/bin/bash -e

WORKSPACE="$(git rev-parse --show-toplevel)"

echo "Cleaning up ESP Outbound integration test environment..."

# Uninstall Helm releases
helm uninstall test-esp-outbound --namespace aerospike-test 2>/dev/null || true
helm uninstall xdr-proxy --namespace aerospike-test 2>/dev/null || true

# Delete Aerospike clusters
kubectl delete aerospikecluster aerocluster-src aerocluster-dst -n aerospike-test 2>/dev/null || true

# Wait for clusters to be deleted
sleep 5

# Delete secrets
kubectl --namespace aerospike-test delete secret aerospike-secret 2>/dev/null || true

# Delete RBAC resources
kubectl delete clusterrolebinding aerospike-cluster-esp-test 2>/dev/null || true
kubectl --namespace aerospike-test delete serviceaccount aerospike-operator-controller-manager 2>/dev/null || true

# Delete namespace
kubectl delete namespace aerospike-test 2>/dev/null || true

# Uninstall AKO
kubectl delete -f https://operatorhub.io/install/aerospike-kubernetes-operator.yaml 2>/dev/null || true

# Delete OLM CSV and CRD
kubectl delete clusterserviceversion "$(kubectl get clusterserviceversion -o=jsonpath='{.items[0].metadata.name}' 2>/dev/null)" 2>/dev/null || true
kubectl delete crd aerospikeclusters.asdb.aerospike.com 2>/dev/null || true

# Delete Kind cluster
kind delete cluster --name esp-test-cluster 2>/dev/null || true

# Clean up Docker network
docker network rm kind 2>/dev/null || true

echo ""
echo "✅ Cleanup complete!"

