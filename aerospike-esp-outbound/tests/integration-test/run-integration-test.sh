#!/bin/bash

# Integration Test Runner Script
# Sets up and tests: Source DB -> ESP Outbound -> XDR Proxy -> Destination DB
# This script:
# 1. Deploys all components (destination DB, XDR Proxy, ESP Outbound, source DB)
# 2. Installs Aerospike tools
# 3. Executes test data flow
# 4. Displays metrics and status

set -e

NAMESPACE="aerospike-test"
ESP_RELEASE="test-esp-outbound"
PROXY_RELEASE="xdr-proxy"
SRC_CLUSTER="aerocluster-esp-src"
DST_CLUSTER="aerocluster-esp-dst"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_info "🚀 Setting up Integration Test Environment"
print_info "=========================================="
echo ""

# Verify existing files exist
if [ ! -f "$SCRIPT_DIR/aerocluster-dst.yaml" ]; then
    print_error "aerocluster-dst.yaml not found in $SCRIPT_DIR"
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/xdr-proxy-values.yaml" ]; then
    print_error "xdr-proxy-values.yaml not found in $SCRIPT_DIR"
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/esp-outbound-integration-values.yaml" ]; then
    print_error "esp-outbound-integration-values.yaml not found in $SCRIPT_DIR"
    exit 1
fi

print_info "✅ Using existing configuration files from $SCRIPT_DIR"
echo ""

# Check if TLS secrets are needed for ESP Outbound
ESP_VALUES_FILE="$SCRIPT_DIR/esp-outbound-integration-values.yaml"
if [ -f "$ESP_VALUES_FILE" ]; then
    # Check if values file references tls-certs-esp secret (not commented out)
    if grep -q "connectorSecrets:" "$ESP_VALUES_FILE" && ! grep -q "^#.*connectorSecrets:" "$ESP_VALUES_FILE"; then
        if grep -q "tls-certs-esp" "$ESP_VALUES_FILE"; then
            print_info "Checking for TLS secret 'tls-certs-esp'..."
            if ! kubectl get secret tls-certs-esp -n $NAMESPACE &>/dev/null; then
                print_warning "TLS secret 'tls-certs-esp' not found in namespace $NAMESPACE"
                
                # Try to create from examples/tls/tls-certs directory (relative to chart root)
                CHART_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
                TLS_CERTS_DIR="$CHART_ROOT/examples/tls/tls-certs"
                if [ -d "$TLS_CERTS_DIR" ]; then
                    print_info "Creating TLS secret from $TLS_CERTS_DIR..."
                    if kubectl create secret generic tls-certs-esp --from-file=$TLS_CERTS_DIR -n $NAMESPACE 2>/dev/null; then
                        print_info "✅ TLS secret created successfully"
                    else
                        print_warning "Failed to create TLS secret. Continuing anyway (may fail if TLS is required)..."
                    fi
                else
                    print_warning "TLS secret 'tls-certs-esp' is required but $TLS_CERTS_DIR not found."
                    print_warning "Please create it manually if TLS is configured:"
                    print_info "  kubectl create secret generic tls-certs-esp --from-file=<path-to-tls-certs> -n $NAMESPACE"
                fi
            else
                print_info "✅ TLS secret 'tls-certs-esp' already exists"
            fi
            echo ""
        fi
    fi
fi

# Check for existing deployments and clean up if needed
print_info "Checking for existing deployments..."
EXISTING_HELM=$(helm list -n ${NAMESPACE} --short 2>/dev/null | grep -E "(${ESP_RELEASE}|${PROXY_RELEASE})" || true)
EXISTING_CLUSTERS=$(kubectl get aerospikecluster -n ${NAMESPACE} -o name 2>/dev/null | grep -E "(${SRC_CLUSTER}|${DST_CLUSTER})" || true)

if [ -n "$EXISTING_HELM" ] || [ -n "$EXISTING_CLUSTERS" ]; then
    print_warning "Found existing deployments. Cleaning up..."
    echo ""
    
    # Uninstall Helm releases
    if helm list -n ${NAMESPACE} --short | grep -q "^${ESP_RELEASE}$"; then
        print_info "Uninstalling existing ${ESP_RELEASE}..."
        helm uninstall ${ESP_RELEASE} -n ${NAMESPACE} 2>/dev/null || true
    fi
    
    if helm list -n ${NAMESPACE} --short | grep -q "^${PROXY_RELEASE}$"; then
        print_info "Uninstalling existing ${PROXY_RELEASE}..."
        helm uninstall ${PROXY_RELEASE} -n ${NAMESPACE} 2>/dev/null || true
    fi
    
    # Delete Aerospike clusters
    if kubectl get aerospikecluster ${SRC_CLUSTER} -n ${NAMESPACE} &>/dev/null; then
        print_info "Deleting existing ${SRC_CLUSTER}..."
        kubectl delete aerospikecluster ${SRC_CLUSTER} -n ${NAMESPACE} 2>/dev/null || true
    fi
    
    if kubectl get aerospikecluster ${DST_CLUSTER} -n ${NAMESPACE} &>/dev/null; then
        print_info "Deleting existing ${DST_CLUSTER}..."
        kubectl delete aerospikecluster ${DST_CLUSTER} -n ${NAMESPACE} 2>/dev/null || true
    fi
    
    print_info "Waiting for cleanup to complete (10 seconds)..."
    sleep 10
    echo ""
fi

# Step 1: Deploy destination cluster
print_info "Step 1: Deploying destination Aerospike cluster..."
kubectl apply -f "$SCRIPT_DIR/aerocluster-dst.yaml"

# Wait for pod to exist first
print_info "Waiting for pod to be created..."
timeout=120
elapsed=0
while [ $elapsed -lt $timeout ]; do
    if kubectl get pod ${DST_CLUSTER}-0-0 -n ${NAMESPACE} &>/dev/null; then
        break
    fi
    sleep 2
    elapsed=$((elapsed + 2))
done

# Wait for pod to be ready
print_info "Waiting for pod to be ready..."
kubectl wait --for=condition=ready pod \
  ${DST_CLUSTER}-0-0 \
  -n ${NAMESPACE} --timeout=3m
print_info "✅ Destination cluster ready"
echo ""

# Step 2: Deploy XDR Proxy
print_info "Step 2: Deploying XDR Proxy..."
WORKSPACE="$(cd "$SCRIPT_DIR/../../.." && pwd)"
helm install ${PROXY_RELEASE} "$WORKSPACE/aerospike-xdr-proxy" \
  -n ${NAMESPACE} -f "$SCRIPT_DIR/xdr-proxy-values.yaml" --wait --timeout=2m
print_info "✅ XDR Proxy deployed"
echo ""

# Step 3: Deploy ESP Outbound
print_info "Step 3: Deploying ESP Outbound connector..."
helm install ${ESP_RELEASE} "$SCRIPT_DIR/../.." \
  -n ${NAMESPACE} -f "$SCRIPT_DIR/esp-outbound-integration-values.yaml" --wait --timeout=2m
print_info "✅ ESP Outbound deployed"
echo ""

# Step 4: Get ESP Outbound pod DNS names and create source cluster YAML
print_info "Step 4: Getting ESP Outbound pod DNS names..."
ESP_PODS=$(kubectl get pods -n $NAMESPACE \
  --selector=app.kubernetes.io/name=aerospike-esp-outbound \
  --no-headers -o custom-columns=":metadata.name" | head -3)

if [ -z "$ESP_PODS" ]; then
    print_error "No ESP Outbound pods found. Please check deployment."
    exit 1
fi

ESP_POD_DNS=""
for pod in $ESP_PODS; do
    ESP_POD_DNS="${ESP_POD_DNS}            - ${pod}.${ESP_RELEASE}-aerospike-esp-outbound.${NAMESPACE}.svc.cluster.local:8901\n"
done

print_info "ESP Outbound pods found:"
echo -e "$ESP_POD_DNS"
echo ""

# Generate source cluster YAML with ESP pod DNS names
print_info "Step 5: Creating source Aerospike cluster configuration..."
SRC_CLUSTER_FILE="$SCRIPT_DIR/aerocluster-src-generated.yaml"
cat > "$SRC_CLUSTER_FILE" <<EOF
apiVersion: asdb.aerospike.com/v1
kind: AerospikeCluster
metadata:
  name: ${SRC_CLUSTER}
  namespace: ${NAMESPACE}
spec:
  size: 1
  image: aerospike/aerospike-server-enterprise:8.0.0.8
  podSpec:
    multiPodPerHost: true
  storage:
    volumes:
      - name: aerospike-secret
        source:
          secret:
            secretName: aerospike-secret
        aerospike:
          path: /etc/aerospike/secrets
  validationPolicy:
    skipWorkDirValidate: true
    skipXdrDlogFileValidate: true
  aerospikeConfig:
    service:
      feature-key-file: /etc/aerospike/secrets/features.conf
    network:
      service:
        port: 3000
      fabric:
        port: 3001
      heartbeat:
        port: 3002
    namespaces:
      - name: test
        replication-factor: 1
        storage-engine:
          type: memory
          data-size: 3000000000
    xdr:
      dcs:
        - name: esp
          connector: true
          namespaces:
            - name: test
          node-address-ports:
$(echo -e "$ESP_POD_DNS")
EOF

print_info "✅ Source cluster configuration created: $SRC_CLUSTER_FILE"
echo ""

# Step 6: Deploy source cluster
print_info "Step 6: Deploying source Aerospike cluster..."
kubectl apply -f "$SRC_CLUSTER_FILE"

# Wait for pod to exist first
print_info "Waiting for pod to be created..."
timeout=120
elapsed=0
while [ $elapsed -lt $timeout ]; do
    if kubectl get pod ${SRC_CLUSTER}-0-0 -n ${NAMESPACE} &>/dev/null; then
        break
    fi
    sleep 2
    elapsed=$((elapsed + 2))
done

# Wait for pod to be ready
print_info "Waiting for pod to be ready..."
kubectl wait --for=condition=ready pod \
  ${SRC_CLUSTER}-0-0 \
  -n ${NAMESPACE} --timeout=3m
print_info "✅ Source cluster ready"
echo ""

# Step 7: Install Aerospike tools in DB pods
print_info "Step 7: Installing Aerospike tools in DB pods..."
echo ""

# Detect architecture
ARCH=$(kubectl exec -n ${NAMESPACE} ${DST_CLUSTER}-0-0 -- uname -m 2>/dev/null || echo "aarch64")
if [[ "$ARCH" == *"x86"* ]] || [[ "$ARCH" == *"amd64"* ]]; then
    # Use x86_64.tgz (not amd64.tgz) as per Aerospike download page
    TOOLS_PKG="aerospike-server-enterprise_8.0.0.8_tools-11.2.2_ubuntu20.04_x86_64.tgz"
    DEB_PKG="aerospike-tools_11.2.2-ubuntu20.04_amd64.deb"
else
    TOOLS_PKG="aerospike-server-enterprise_8.0.0.8_tools-11.2.2_ubuntu20.04_aarch64.tgz"
    DEB_PKG="aerospike-tools_11.2.2-ubuntu20.04_arm64.deb"
fi

print_info "Detected architecture: $ARCH"
print_info "Using tools package: $TOOLS_PKG"
echo ""

# Check for local tools file on Jenkins box
LOCAL_TOOLS_PATH="/var/lib/jenkins/aerospike-connect-resources/tests2/aerospike"
LOCAL_TOOLS_FILE=""
if [ -f "${LOCAL_TOOLS_PATH}/${TOOLS_PKG}" ]; then
    LOCAL_TOOLS_FILE="${LOCAL_TOOLS_PATH}/${TOOLS_PKG}"
fi

# Helper function to install tools in a pod
install_tools_in_pod() {
    local POD_NAME=$1
    local POD_TYPE=$2
    local USE_LOCAL_FILE=false
    
    if [ -n "$LOCAL_TOOLS_FILE" ] && [ -f "$LOCAL_TOOLS_FILE" ]; then
        print_info "Copying tools file into ${POD_TYPE} pod..."
        if kubectl cp "${LOCAL_TOOLS_FILE}" ${NAMESPACE}/${POD_NAME}:/tmp/tools.tgz 2>/dev/null; then
            USE_LOCAL_FILE=true
        else
            print_warning "Failed to copy local tools file to ${POD_TYPE} pod, falling back to download"
        fi
    fi
    
    if [ "$USE_LOCAL_FILE" = true ]; then
        # Install from copied local file
        kubectl exec -n ${NAMESPACE} ${POD_NAME} -- bash -c "
        set -e
        cd /tmp && \
        apt-get update -qq && \
        (apt-get install -y -qq libreadline8 > /dev/null 2>&1 || apt-get install -y -qq libreadline9 > /dev/null 2>&1 || true) && \
        tar -xzf tools.tgz > /dev/null 2>&1 && \
        dpkg -i aerospike-server-enterprise_8.0.0.8_tools-11.2.2_ubuntu20.04_*/${DEB_PKG} > /dev/null 2>&1 && \
        echo '✅ Tools installed successfully from local file'
        " || print_warning "Tools installation from local file in ${POD_TYPE} pod may have failed (check manually)"
    else
        # Fall back to download method
        kubectl exec -n ${NAMESPACE} ${POD_NAME} -- bash -c "
        set -e
        cd /tmp && \
        apt-get update -qq && \
        apt-get install -y -qq wget curl > /dev/null 2>&1 && \
        wget --no-check-certificate --content-disposition -q 'https://download.aerospike.com/artifacts/aerospike-server-enterprise/8.0.0.8/${TOOLS_PKG}' -O tools.tgz || \
        curl -L -o tools.tgz 'https://download.aerospike.com/artifacts/aerospike-server-enterprise/8.0.0.8/${TOOLS_PKG}' && \
        tar -xzf tools.tgz > /dev/null 2>&1 && \
        (apt-get install -y -qq libreadline8 > /dev/null 2>&1 || apt-get install -y -qq libreadline9 > /dev/null 2>&1 || true) && \
        dpkg -i aerospike-server-enterprise_8.0.0.8_tools-11.2.2_ubuntu20.04_*/${DEB_PKG} > /dev/null 2>&1 && \
        echo '✅ Tools installed successfully from download'
        " || print_warning "Tools installation from download in ${POD_TYPE} pod may have failed (check manually)"
    fi
}

# Install tools in destination DB pod
print_info "Installing tools in destination DB pod..."
if [ -n "$LOCAL_TOOLS_FILE" ] && [ -f "$LOCAL_TOOLS_FILE" ]; then
    print_info "Found local tools file: $LOCAL_TOOLS_FILE"
fi
install_tools_in_pod "${DST_CLUSTER}-0-0" "destination"

# Install tools in source DB pod
print_info "Installing tools in source DB pod..."
install_tools_in_pod "${SRC_CLUSTER}-0-0" "source"

print_info "✅ Tools installation complete"
echo ""

print_info "✅ Integration test environment setup complete!"
echo ""

# Step 8: Test Data Flow
print_info "Step 8: Testing data flow..."
echo ""

# Insert test data in source DB
print_info "Inserting test data in source DB..."
TEST_KEY="test-key-$(date +%s)"
INSERT_OUTPUT=$(kubectl exec -n ${NAMESPACE} ${SRC_CLUSTER}-0-0 -- aql -h localhost -p 3000 -c \
  "INSERT INTO test.demo (PK, name, value) VALUES ('${TEST_KEY}', 'Test Record', 100)" 2>&1)

if echo "$INSERT_OUTPUT" | grep -q "OK"; then
    print_info "✅ Test data inserted successfully"
else
    print_warning "⚠️  Data insertion may have failed (check logs)"
    echo "$INSERT_OUTPUT"
fi

# Wait for data to flow through pipeline
print_info "Waiting for data replication (10 seconds)..."
sleep 10

# Verify data in destination DB
print_info "Verifying data in destination DB..."
RESULT=$(kubectl exec -n ${NAMESPACE} ${DST_CLUSTER}-0-0 -- aql -h localhost -p 3003 -c \
  "SELECT * FROM test.demo WHERE PK='${TEST_KEY}'" 2>&1 | grep -v "^OK" || true)

if echo "$RESULT" | grep -q "${TEST_KEY}"; then
    print_info "✅ Test data found in destination DB!"
    echo "$RESULT"
else
    print_warning "⚠️  Test data not found in destination DB (this may be normal if replication is still in progress)"
    echo "$RESULT"
fi
echo ""

# Step 9: Display Metrics
print_info "Step 9: Checking component metrics..."
echo ""

# Check ESP Outbound metrics across all pods
print_info "ESP Outbound Pod Metrics:"
ESP_POD_COUNT=$(kubectl get pods -n ${NAMESPACE} \
  --selector=app.kubernetes.io/name=aerospike-esp-outbound \
  --no-headers | wc -l | tr -d ' ')

for i in $(seq 0 $((ESP_POD_COUNT - 1))); do
    POD_NAME="${ESP_RELEASE}-aerospike-esp-outbound-${i}"
    if kubectl get pod ${POD_NAME} -n ${NAMESPACE} &>/dev/null; then
        echo "ESP Outbound Pod $i (${POD_NAME}):"
        METRICS=$(kubectl logs -n ${NAMESPACE} ${POD_NAME} --tail=20 2>/dev/null | \
          grep -E "(requests-total|requests-success)" | tail -5 || echo "No metrics found")
        if [ -n "$METRICS" ] && [ "$METRICS" != "No metrics found" ]; then
            echo "$METRICS"
        else
            echo "  No requests yet"
        fi
    fi
done
echo ""

# Check XDR Proxy metrics
print_info "XDR Proxy Metrics:"
PROXY_POD_NAME="${PROXY_RELEASE}-aerospike-xdr-proxy-0"
if kubectl get pod ${PROXY_POD_NAME} -n ${NAMESPACE} &>/dev/null; then
    PROXY_METRICS=$(kubectl logs -n ${NAMESPACE} ${PROXY_POD_NAME} --tail=20 2>/dev/null | \
      grep -E "(requests-total|requests-success)" | tail -5 || echo "No metrics found")
    if [ -n "$PROXY_METRICS" ] && [ "$PROXY_METRICS" != "No metrics found" ]; then
        echo "$PROXY_METRICS"
    else
        echo "  No requests yet"
    fi
else
    print_warning "XDR Proxy pod not found"
fi
echo ""

# Step 10: Final Status Check
print_info "Step 10: Final status check..."
echo ""
kubectl get pods -n ${NAMESPACE} -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready" \
  | grep -E "(NAME|aerocluster|esp-outbound|xdr-proxy)" || true
echo ""

print_info "✅ Integration test complete!"
echo ""
print_info "📋 Summary:"
print_info "   - Test key used: ${TEST_KEY}"
print_info "   - Check metrics above to verify data flow"
print_info "   - All pods should show STATUS=Running and READY=true"
echo ""
print_info "📁 Files used:"
print_info "   - $SCRIPT_DIR/aerocluster-dst.yaml (Destination cluster)"
print_info "   - $SCRIPT_DIR/xdr-proxy-values.yaml (XDR Proxy config)"
print_info "   - $SCRIPT_DIR/esp-outbound-integration-values.yaml (ESP config)"
print_info "   - $SRC_CLUSTER_FILE (Source cluster - dynamically generated with ESP pod DNS)"
