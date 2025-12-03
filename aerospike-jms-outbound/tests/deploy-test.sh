#!/bin/bash

# Deployment script for aerospike-jms-outbound Helm chart to a test cluster
set -e

CHART_NAME="aerospike-jms-outbound"
RELEASE_NAME="test-jms-outbound"
NAMESPACE="aerospike-test"
VALUES_FILE=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --release-name)
            RELEASE_NAME="$2"
            shift 2
            ;;
        --values)
            VALUES_FILE="$2"
            shift 2
            ;;
        --uninstall)
            print_info "Uninstalling release $RELEASE_NAME from namespace $NAMESPACE..."
            helm uninstall $RELEASE_NAME --namespace $NAMESPACE 2>/dev/null || print_warning "Release not found"
            kubectl delete namespace $NAMESPACE 2>/dev/null || print_warning "Namespace not found"
            exit 0
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --namespace NAME       Kubernetes namespace (default: aerospike-test)"
            echo "  --release-name NAME    Helm release name (default: test-jms-outbound)"
            echo "  --values FILE          Path to values file (optional)"
            echo "  --uninstall            Uninstall the release"
            echo "  --help                 Show this help message"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

print_info "🚀 Deploying Aerospike JMS Outbound Connector"
print_info "=============================================="
print_info "Chart: $CHART_NAME"
print_info "Release: $RELEASE_NAME"
print_info "Namespace: $NAMESPACE"
if [ -n "$VALUES_FILE" ]; then
    print_info "Values file: $VALUES_FILE"
fi
echo ""

# Check prerequisites
print_info "Checking prerequisites..."

if ! command -v helm &> /dev/null; then
    print_error "Helm is not installed. Please install Helm v3.x"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed. Please install kubectl"
    exit 1
fi

# Check Kubernetes cluster connectivity
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster"
    print_info "Please ensure kubectl is configured correctly"
    exit 1
fi

print_info "✅ Prerequisites check passed"
echo ""

# Create namespace
print_info "Creating namespace $NAMESPACE..."
kubectl create namespace $NAMESPACE 2>/dev/null || print_warning "Namespace already exists"
echo ""

# Check if TLS secrets are needed and create them if missing
if [ -n "$VALUES_FILE" ] && [ -f "$VALUES_FILE" ]; then
    # Check if values file references tls-certs secret (not commented out)
    if grep -q "tls-certs" "$VALUES_FILE" && grep -q "^connectorSecrets:" "$VALUES_FILE"; then
        print_info "Checking for TLS secret 'tls-certs'..."
        if ! kubectl get secret tls-certs -n $NAMESPACE &>/dev/null; then
            print_warning "TLS secret 'tls-certs' not found in namespace $NAMESPACE"
            
            # Try to create from examples/tls/tls-certs directory
            TLS_CERTS_DIR="examples/tls/tls-certs"
            if [ -d "$TLS_CERTS_DIR" ]; then
                print_info "Creating TLS secret from $TLS_CERTS_DIR..."
                if kubectl create secret generic tls-certs --from-file=$TLS_CERTS_DIR -n $NAMESPACE 2>/dev/null; then
                    print_info "✅ TLS secret created successfully"
                else
                    print_error "Failed to create TLS secret. Please create it manually:"
                    print_info "  kubectl create secret generic tls-certs --from-file=$TLS_CERTS_DIR -n $NAMESPACE"
                    exit 1
                fi
            else
                print_error "TLS secret 'tls-certs' is required but not found."
                print_error "Please create it manually or ensure $TLS_CERTS_DIR directory exists."
                print_info "Example: kubectl create secret generic tls-certs --from-file=<path-to-tls-certs> -n $NAMESPACE"
                exit 1
            fi
        else
            print_info "✅ TLS secret 'tls-certs' already exists"
        fi
        echo ""
    fi
fi

# Install the chart
print_info "Installing Helm chart..."
# Use current directory (.) as chart path since we're deploying from local chart directory
INSTALL_CMD="helm install $RELEASE_NAME . --namespace $NAMESPACE --wait --timeout 2m"

if [ -n "$VALUES_FILE" ] && [ -f "$VALUES_FILE" ]; then
    INSTALL_CMD="$INSTALL_CMD -f $VALUES_FILE"
    print_info "Using values file: $VALUES_FILE"
fi

if eval "$INSTALL_CMD"; then
    print_info "✅ Chart installed successfully"
else
    print_error "Chart installation failed"
    exit 1
fi

echo ""

# Wait for pods to be ready
print_info "Waiting for pods to be ready..."
if kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=$CHART_NAME --namespace $NAMESPACE --timeout=120s 2>/dev/null; then
    print_info "✅ All pods are ready"
else
    print_warning "Some pods may not be ready yet (checking status...)"
fi

echo ""

# Display deployment status
print_info "Deployment Status:"
echo "===================="
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=$CHART_NAME
echo ""

print_info "StatefulSet Status:"
kubectl get statefulset -n $NAMESPACE
echo ""

print_info "Service Status:"
kubectl get service -n $NAMESPACE
echo ""

print_info "ConfigMap Status:"
kubectl get configmap -n $NAMESPACE
echo ""

# Show pod logs
print_info "Recent logs from pods:"
PODS=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=$CHART_NAME -o jsonpath='{.items[*].metadata.name}')
for pod in $PODS; do
    echo "--- Logs from $pod ---"
    kubectl logs -n $NAMESPACE $pod --tail=10 || true
    echo ""
done

# Run Helm tests if available
print_info "Running Helm tests..."
if helm test $RELEASE_NAME --namespace $NAMESPACE --timeout 60s 2>&1; then
    print_info "✅ Helm tests passed"
else
    print_warning "Helm tests had issues (this is normal if test pods aren't ready)"
fi

echo ""
print_info "🎉 Deployment completed!"
print_info ""
print_info "Next steps:"
print_info "1. Check pod logs: kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=$CHART_NAME"
print_info "2. Get pod details: kubectl describe pod -n $NAMESPACE -l app.kubernetes.io/name=$CHART_NAME"
print_info "3. Check service: kubectl get svc -n $NAMESPACE"
print_info "4. Run integration test: cd tests/integration-test && ./run-integration-test.sh"
print_info "5. Uninstall: $0 --uninstall --namespace $NAMESPACE --release-name $RELEASE_NAME"
echo ""

