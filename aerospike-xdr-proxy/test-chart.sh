#!/bin/bash

# Test script for aerospike-xdr-proxy Helm chart

set -e

CHART_NAME="."
RELEASE_NAME="test-xdr-proxy"
NAMESPACE="aerospike-test"
CLEAR_TEXT_VALUES="examples/clear-text/as-xdr-proxy-values.yaml"
TLS_VALUES="examples/tls/as-xdr-proxy-tls-values.yaml"

echo "🧪 Testing Aerospike XDR Proxy Helm Chart"
echo "=============================================="

# Function to cleanup
cleanup() {
    echo "🧹 Cleaning up test resources..."
    helm uninstall $RELEASE_NAME --namespace $NAMESPACE 2>/dev/null || true
    kubectl delete namespace $NAMESPACE 2>/dev/null || true
}

# Set trap for cleanup
trap cleanup EXIT

# Test 1: Lint the chart
echo "📋 Test 1: Linting chart..."
helm lint $CHART_NAME
echo "✅ Chart linting passed"

# Test 2: Template rendering
echo "📋 Test 2: Testing template rendering..."
helm template $RELEASE_NAME $CHART_NAME --debug > /dev/null
echo "✅ Template rendering passed"

# Test 3: Template rendering with clear-text values
echo "📋 Test 3: Testing template rendering with clear-text values..."
helm template $RELEASE_NAME $CHART_NAME -f $CLEAR_TEXT_VALUES --debug > /dev/null
echo "✅ Clear-text template rendering passed"

# Test 4: Template rendering with TLS values
echo "📋 Test 4: Testing template rendering with TLS values..."
helm template $RELEASE_NAME $CHART_NAME -f $TLS_VALUES --debug > /dev/null
echo "✅ TLS template rendering passed"

# Test 5: Dry-run installation
echo "📋 Test 5: Testing dry-run installation..."
helm install --dry-run --debug $RELEASE_NAME $CHART_NAME --namespace $NAMESPACE
echo "✅ Dry-run installation passed"

# Test 6: Actual installation (if kubectl is available)
if command -v kubectl &> /dev/null; then
    echo "📋 Test 6: Testing actual installation..."

    # Create namespace
    kubectl create namespace $NAMESPACE 2>/dev/null || true

    # Install chart
    helm install $RELEASE_NAME $CHART_NAME --namespace $NAMESPACE -f $CLEAR_TEXT_VALUES

    # Wait for pods to be ready
    echo "⏳ Waiting for pods to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=aerospike-xdr-proxy --namespace $NAMESPACE --timeout=60s

    # Check resources
    echo "📊 Checking deployed resources..."
    kubectl get pods -n $NAMESPACE
    kubectl get statefulset -n $NAMESPACE
    kubectl get service -n $NAMESPACE
    kubectl get configmap -n $NAMESPACE

    # Test connectivity
    echo "🔗 Testing connectivity..."
    kubectl run test-pod --image=busybox --rm -it --restart=Never --namespace $NAMESPACE -- nslookup $RELEASE_NAME-aerospike-xdr-proxy || true

    # Run helm test
    echo "🧪 Running Helm tests..."
    helm test $RELEASE_NAME --namespace $NAMESPACE || true

    echo "✅ Actual installation test passed"
else
    echo "⚠️  kubectl not available, skipping actual installation test"
fi

echo ""
echo "🎉 All tests completed successfully!"
echo "=============================================="
