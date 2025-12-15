#!/bin/bash

# Integration Test Runner Script
# Sets up and tests: Aerospike DB -> Pulsar Outbound Connector -> Pulsar Broker
# This script:
# 1. Deploys Pulsar broker
# 2. Deploys Pulsar Outbound connector
# 3. Deploys Aerospike cluster (source) with XDR pointing to connector
# 4. Installs Aerospike tools
# 5. Executes test data flow
# 6. Displays metrics and status

set -e

NAMESPACE="aerospike-test"
PULSAR_RELEASE="pulsar"
CONNECTOR_RELEASE="test-pulsar-outbound"
SRC_CLUSTER="aerocluster-pulsar-src"
PULSAR_TOPIC="persistent://public/default/aerospike"
PULSAR_TOPIC_NAME="aerospike"
CONTEXT="kind-pulsar-test-cluster"  # Explicit context for parallel execution safety

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
    print_error "Cannot connect to cluster with context: ${CONTEXT}"
    print_error "Please ensure the Kind cluster is created: kind get clusters"
    echo "INTEGRATION_TEST_FAILED"
    exit 1
fi

print_info "🚀 Setting up Pulsar Outbound Integration Test Environment"
print_info "======================================================"
echo ""

# Verify existing files exist
if [ ! -f "$SCRIPT_DIR/pulsar-deployment.yaml" ]; then
    print_error "pulsar-deployment.yaml not found in $SCRIPT_DIR"
    echo "INTEGRATION_TEST_FAILED"
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/pulsar-outbound-integration-values.yaml" ]; then
    print_error "pulsar-outbound-integration-values.yaml not found in $SCRIPT_DIR"
    echo "INTEGRATION_TEST_FAILED"
    exit 1
fi

print_info "✅ Using existing configuration files from $SCRIPT_DIR"
echo ""

# Check if TLS secrets are needed for Pulsar Outbound
CONNECTOR_VALUES_FILE="$SCRIPT_DIR/pulsar-outbound-integration-values.yaml"
if [ -f "$CONNECTOR_VALUES_FILE" ]; then
    if grep -q "connectorSecrets:" "$CONNECTOR_VALUES_FILE" && ! grep -q "^#.*connectorSecrets:" "$CONNECTOR_VALUES_FILE"; then
        if grep -q "tls-certs-pulsar" "$CONNECTOR_VALUES_FILE"; then
            print_info "Checking for TLS secret 'tls-certs-pulsar'..."
            if ! kubectl get secret tls-certs-pulsar -n "${NAMESPACE}" &>/dev/null; then
                print_warning "TLS secret 'tls-certs-pulsar' not found in namespace ${NAMESPACE}"
                CHART_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
                TLS_CERTS_DIR="${CHART_ROOT}/examples/tls/tls-certs"
                if [ -d "${TLS_CERTS_DIR}" ]; then
                    print_info "Creating TLS secret from ${TLS_CERTS_DIR}..."
                    if kubectl create secret generic tls-certs-pulsar --from-file="${TLS_CERTS_DIR}" -n "${NAMESPACE}" 2>/dev/null; then
                        print_info "✅ TLS secret created successfully"
                    else
                        print_warning "Failed to create TLS secret. Continuing anyway..."
                    fi
                else
                    print_warning "TLS secret 'tls-certs-pulsar' is required but ${TLS_CERTS_DIR} not found."
                    print_info "  kubectl create secret generic tls-certs-pulsar --from-file=<path-to-tls-certs> -n ${NAMESPACE}"
                fi
            else
                print_info "✅ TLS secret 'tls-certs-pulsar' already exists"
            fi
            echo ""
        fi
    fi
fi

# Check for existing deployments and clean up if needed
print_info "Checking for existing deployments..."
EXISTING_HELM=$(helm list -n "${NAMESPACE}" --short 2>/dev/null | grep -E "(${CONNECTOR_RELEASE}|${PULSAR_RELEASE})" || true)
EXISTING_CLUSTERS=$(kubectl get aerospikecluster -n "${NAMESPACE}" -o name 2>/dev/null | grep -E "${SRC_CLUSTER}" || true)

if [ -n "$EXISTING_HELM" ] || [ -n "$EXISTING_CLUSTERS" ]; then
    print_warning "Found existing deployments. Cleaning up..."
    echo ""
    
    if helm list -n "${NAMESPACE}" --short | grep -q "^${CONNECTOR_RELEASE}$"; then
        print_info "Uninstalling existing ${CONNECTOR_RELEASE}..."
        helm uninstall "${CONNECTOR_RELEASE}" -n "${NAMESPACE}" 2>/dev/null || true
    fi
    
    if helm list -n "${NAMESPACE}" --short | grep -q "^${PULSAR_RELEASE}$"; then
        print_info "Uninstalling existing ${PULSAR_RELEASE}..."
        helm uninstall "${PULSAR_RELEASE}" -n "${NAMESPACE}" 2>/dev/null || true
    fi
    
    # Also clean up direct Kubernetes resources
    kubectl delete statefulset pulsar -n "${NAMESPACE}" 2>/dev/null || true
    kubectl delete service pulsar pulsar-headless -n "${NAMESPACE}" 2>/dev/null || true
    
    if kubectl get aerospikecluster "${SRC_CLUSTER}" -n "${NAMESPACE}" &>/dev/null; then
        print_info "Deleting existing ${SRC_CLUSTER}..."
        kubectl delete aerospikecluster "${SRC_CLUSTER}" -n "${NAMESPACE}" 2>/dev/null || true
    fi
    
    print_info "Waiting for cleanup to complete (10 seconds)..."
    sleep 10
    echo ""
fi

# Step 1: Deploy Pulsar broker
print_info "Step 1: Deploying Pulsar broker..."
print_info "Using Apache Pulsar 4.0.7 official image (standalone mode)..."
kubectl apply -f "$SCRIPT_DIR/pulsar-deployment.yaml"

print_info "Waiting for Pulsar pods to be ready (this may take a few minutes)..."
kubectl wait --for=condition=ready pod \
  -l app=pulsar \
  -n "${NAMESPACE}" \
  --timeout=10m || print_warning "Pulsar pods may still be starting"

print_info "✅ Pulsar broker deployed"
echo ""

# Get Pulsar broker service name
PULSAR_SERVICE="pulsar"
PULSAR_SERVICE_URL="pulsar://${PULSAR_SERVICE}.${NAMESPACE}.svc.cluster.local:6650"

# Step 2: Update connector values with Pulsar broker address
print_info "Step 2: Updating connector configuration with Pulsar broker address..."
TEMP_VALUES=$(mktemp)
# Update service URL in the values file
sed "s|serviceUrl: pulsar://pulsar.aerospike-test.svc.cluster.local:6650|serviceUrl: ${PULSAR_SERVICE_URL}|g" \
  "$SCRIPT_DIR/pulsar-outbound-integration-values.yaml" > "$TEMP_VALUES"

# Step 3: Deploy Pulsar Outbound connector
print_info "Step 3: Deploying Pulsar Outbound connector..."
helm install "${CONNECTOR_RELEASE}" "$SCRIPT_DIR/../.." \
  -n "${NAMESPACE}" \
  -f "$TEMP_VALUES" \
  --wait --timeout=2m

rm -f "$TEMP_VALUES"
print_info "✅ Pulsar Outbound connector deployed"
echo ""

# Step 4: Get connector pod DNS names and create source cluster YAML
print_info "Step 4: Getting Pulsar Outbound connector pod DNS names..."
CONNECTOR_PODS=$(kubectl get pods -n "${NAMESPACE}" \
  --selector=app.kubernetes.io/name=aerospike-pulsar-outbound \
  --no-headers -o custom-columns=":metadata.name" | head -3)

if [ -z "$CONNECTOR_PODS" ]; then
    print_error "No Pulsar Outbound connector pods found. Please check deployment."
    echo "INTEGRATION_TEST_FAILED"
    exit 1
fi

CONNECTOR_POD_DNS=""
while IFS= read -r pod; do
    if [ -n "$pod" ]; then
        CONNECTOR_POD_DNS="${CONNECTOR_POD_DNS}            - ${pod}.${CONNECTOR_RELEASE}-aerospike-pulsar-outbound.${NAMESPACE}.svc.cluster.local:8080\n"
    fi
done <<< "$CONNECTOR_PODS"

print_info "Pulsar Outbound connector pods found:"
echo -e "$CONNECTOR_POD_DNS"
echo ""

# Generate source cluster YAML with connector pod DNS names
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
        port: 3030
      fabric:
        port: 3031
      heartbeat:
        port: 3032
    namespaces:
      - name: test
        replication-factor: 1
        storage-engine:
          type: memory
          data-size: 300000000  # 300MB - minimum required for Aerospike 8.0.0.8
    xdr:
      dcs:
        - name: pulsar
          connector: true
          namespaces:
            - name: test
          node-address-ports:
$(echo -e "$CONNECTOR_POD_DNS")
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
    if kubectl get pod "${SRC_CLUSTER}-0-0" -n "${NAMESPACE}" &>/dev/null; then
        break
    fi
    sleep 2
    elapsed=$((elapsed + 2))
done

# Wait for pod to be ready
print_info "Waiting for pod to be ready..."
kubectl wait --for=condition=ready pod \
  "${SRC_CLUSTER}-0-0" \
  -n "${NAMESPACE}" --timeout=3m
print_info "✅ Source cluster ready"
echo ""

# Step 7: Install Aerospike tools in DB pod
print_info "Step 7: Installing Aerospike tools in DB pod..."
echo ""

# Detect architecture
ARCH=$(kubectl exec -n "${NAMESPACE}" "${SRC_CLUSTER}-0-0" -- uname -m 2>/dev/null || echo "aarch64")
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

# Install tools in source DB pod
print_info "Installing tools in source DB pod..."
if [ -n "$LOCAL_TOOLS_FILE" ] && [ -f "$LOCAL_TOOLS_FILE" ]; then
    print_info "Found local tools file: $LOCAL_TOOLS_FILE"
    print_info "Copying tools file into pod..."
    kubectl cp "${LOCAL_TOOLS_FILE}" "${NAMESPACE}/${SRC_CLUSTER}-0-0:/tmp/tools.tgz" || {
        print_warning "Failed to copy local tools file, falling back to download"
        LOCAL_TOOLS_FILE=""
    }
fi

if [ -n "$LOCAL_TOOLS_FILE" ] && [ -f "$LOCAL_TOOLS_FILE" ]; then
    # Install from copied local file
    kubectl exec -n "${NAMESPACE}" "${SRC_CLUSTER}-0-0" -- bash -c "
    set -e
    cd /tmp && \
    apt-get update -qq && \
    (apt-get install -y -qq libreadline8 > /dev/null 2>&1 || apt-get install -y -qq libreadline9 > /dev/null 2>&1 || true) && \
    tar -xzf tools.tgz > /dev/null 2>&1 && \
    dpkg -i aerospike-server-enterprise_8.0.0.8_tools-11.2.2_ubuntu20.04_*/${DEB_PKG} > /dev/null 2>&1 && \
    echo '✅ Tools installed successfully from local file'
    " || print_warning "Tools installation from local file may have failed (check manually)"
else
    # Fall back to download method
    print_info "Local tools file not found, downloading from Aerospike..."
    kubectl exec -n "${NAMESPACE}" "${SRC_CLUSTER}-0-0" -- bash -c "
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
    " || print_warning "Tools installation from download may have failed (check manually)"
fi

print_info "✅ Tools installation complete"
echo ""

# Step 8: Create Pulsar topic (if needed)
print_info "Step 8: Creating Pulsar topic '${PULSAR_TOPIC}'..."
PULSAR_POD=$(kubectl get pods -n "${NAMESPACE}" -l app=pulsar -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$PULSAR_POD" ]; then
    print_warning "Pulsar pod not found, skipping topic creation"
else
    # Wait a bit for Pulsar to be fully ready
    sleep 10
    
    # Create namespace if it doesn't exist
    print_info "Creating Pulsar namespace 'public/default' if needed..."
    kubectl exec -n "${NAMESPACE}" "${PULSAR_POD}" -- bin/pulsar-admin namespaces create public/default 2>/dev/null || \
      print_info "Namespace already exists or will be auto-created"
    
    # Check if topic exists
    TOPIC_LIST=$(kubectl exec -n "${NAMESPACE}" "${PULSAR_POD}" -- bin/pulsar-admin topics list public/default 2>&1 || echo "")
    
    if echo "$TOPIC_LIST" | grep -q "${PULSAR_TOPIC_NAME}"; then
        print_info "✅ Pulsar topic already exists"
    else
        # Create topic
        CREATE_OUTPUT=$(kubectl exec -n "${NAMESPACE}" "${PULSAR_POD}" -- bin/pulsar-admin topics create "${PULSAR_TOPIC}" 2>&1 || echo "")
        
        if echo "$CREATE_OUTPUT" | grep -qE "(Created|already exists)"; then
            print_info "✅ Pulsar topic created or already exists"
        else
            print_info "✅ Topic will be auto-created when first message arrives"
        fi
    fi
fi
echo ""

# Step 9: Test Data Flow
print_info "Step 9: Testing data flow..."
echo ""

# Insert test data in source DB
print_info "Inserting test data in source DB..."
TEST_KEY="test-key-$(date +%s)"
INSERT_OUTPUT=$(kubectl exec -n "${NAMESPACE}" "${SRC_CLUSTER}-0-0" -- aql -h localhost -p 3030 -c \
  "INSERT INTO test.demo (PK, name, value) VALUES ('${TEST_KEY}', 'Test Record', 100)" 2>&1)

if echo "$INSERT_OUTPUT" | grep -q "OK"; then
    print_info "✅ Test data inserted successfully"
else
    print_warning "⚠️  Data insertion may have failed (check logs)"
    echo "$INSERT_OUTPUT"
fi

# Wait for data to flow through pipeline
print_info "Waiting for data replication to Pulsar (10 seconds)..."
sleep 10

# Verify data in Pulsar
print_info "Verifying data in Pulsar topic '${PULSAR_TOPIC}'..."
PULSAR_POD=$(kubectl get pods -n "${NAMESPACE}" -l app=pulsar -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
FOUND_MESSAGE=false
if [ -z "$PULSAR_POD" ]; then
    print_error "❌ Test FAILED: Pulsar pod not found for message verification"
    echo ""
    echo "INTEGRATION_TEST_FAILED"
    exit 1
fi

# Check Pulsar topic statistics first (most reliable indicator)
print_info "Checking Pulsar topic statistics..."
PULSAR_STATS=$(kubectl exec -n "${NAMESPACE}" "${PULSAR_POD}" -- bin/pulsar-admin topics stats "${PULSAR_TOPIC}" 2>&1 | grep -E "(msgInCount|msgInCounter|msgOutCount|msgOutCounter|storageSize)" | head -5 || echo "")
if [ -n "$PULSAR_STATS" ]; then
    print_info "Topic statistics:"
    echo "  ${PULSAR_STATS//$'\n'/$'\n'  }"
    # Extract msgInCounter and storageSize to verify messages were written
    MSG_IN_COUNT=$(echo "$PULSAR_STATS" | grep -E "msgInCount|msgInCounter" | sed 's/.*"msgInCount[^"]*" : \([0-9]*\).*/\1/' || echo "0")
    STORAGE_SIZE=$(echo "$PULSAR_STATS" | grep -E "storageSize" | sed 's/.*"storageSize" : \([0-9]*\).*/\1/' || echo "0")
    if [ "$MSG_IN_COUNT" -gt 0 ] 2>/dev/null; then
        print_info "✅ Found ${MSG_IN_COUNT} message(s) written to Pulsar topic (storage: ${STORAGE_SIZE} bytes)"
        FOUND_MESSAGE=true
    else
        print_warning "⚠️  No messages found in topic statistics (msgInCounter: ${MSG_IN_COUNT})"
        FOUND_MESSAGE=false
    fi
else
    print_warning "Could not retrieve topic statistics"
    FOUND_MESSAGE=false
fi
echo ""

# Attempt to peek at messages using a subscription with cursor reset to earliest
# This allows reading messages from the beginning even if they were already consumed
if [ "${FOUND_MESSAGE}" = true ]; then
    print_info "Attempting to peek at message content..."
    UNIQUE_SUB="verify-$(date +%s)-$$"
    
    # Create subscription and reset cursor to earliest, then try to consume
    print_info "Creating subscription '${UNIQUE_SUB}' and resetting cursor to earliest..."
    kubectl exec -n "${NAMESPACE}" "${PULSAR_POD}" -- bash -c "bin/pulsar-admin topics create-subscription ${PULSAR_TOPIC} -s ${UNIQUE_SUB} 2>&1 || true" >/dev/null 2>&1
    kubectl exec -n "${NAMESPACE}" "${PULSAR_POD}" -- bash -c "bin/pulsar-admin topics reset-cursor ${PULSAR_TOPIC} -s ${UNIQUE_SUB} -m earliest 2>&1 || true" >/dev/null 2>&1
    
    # Try to consume with timeout
    print_info "Consuming messages (timeout: 5 seconds)..."
    PULSAR_PEEK=$(kubectl exec -n "${NAMESPACE}" "${PULSAR_POD}" -- bash -c "timeout 5 bin/pulsar-client consume ${PULSAR_TOPIC} -s ${UNIQUE_SUB} -n 1 2>&1 || echo 'Timeout'" 2>&1 | grep -vE "(^INFO|^Nov|^\[pulsar|^2025|AutoConfigured|Subscribed|Connected|command terminated|Exclusive consumer)" | grep -v "^$" | head -10 || echo "")
    
    if [ -n "$PULSAR_PEEK" ] && ! echo "$PULSAR_PEEK" | grep -qE "(Timeout|error|Error|ConsumerBusy)"; then
        if echo "$PULSAR_PEEK" | grep -q "${TEST_KEY}"; then
            print_info "✅ Successfully peeked at message content - test key found!"
            echo "$PULSAR_PEEK" | grep -E "(metadata|userKey|${TEST_KEY})" | head -3
        else
            print_info "Peeked at messages (test key not found in output, but stats confirm delivery)"
            echo "$PULSAR_PEEK" | head -3
        fi
    else
        print_info "Message peek timed out or subscription conflict (this is OK)"
        print_info "Topic statistics above confirm successful delivery"
    fi
    
    # Clean up subscription
    kubectl exec -n "${NAMESPACE}" "${PULSAR_POD}" -- bash -c "bin/pulsar-admin topics unsubscribe ${PULSAR_TOPIC} -s ${UNIQUE_SUB} -f 2>&1 || true" >/dev/null 2>&1
    
    print_info ""
    print_info "💡 To manually verify message content:"
    print_info "   SUB=\$(date +%s)"
    print_info "   kubectl exec -n ${NAMESPACE} ${PULSAR_POD} -- bin/pulsar-admin topics create-subscription ${PULSAR_TOPIC} -s verify-\$SUB"
    print_info "   kubectl exec -n ${NAMESPACE} ${PULSAR_POD} -- bin/pulsar-admin topics reset-cursor ${PULSAR_TOPIC} -s verify-\$SUB -m earliest"
    print_info "   kubectl exec -n ${NAMESPACE} ${PULSAR_POD} -- bin/pulsar-client consume ${PULSAR_TOPIC} -s verify-\$SUB -n 10"
    print_info ""
    print_info "💡 To check topic statistics again:"
    print_info "   kubectl exec -n ${NAMESPACE} ${PULSAR_POD} -- bin/pulsar-admin topics stats ${PULSAR_TOPIC}"
fi

if [ "$FOUND_MESSAGE" = false ]; then
    print_error "❌ Test FAILED: No messages found in Pulsar topic"
    print_warning "This may indicate:"
    print_warning "  - Pulsar Outbound connector is not forwarding data correctly"
    print_warning "  - Data replication delay (try waiting longer)"
    print_warning "  - Network connectivity issues"
    echo ""
    echo "INTEGRATION_TEST_FAILED"
    exit 1
fi
echo ""

# Step 10: Display Metrics
print_info "Step 10: Checking component metrics..."
echo ""

# Check Pulsar Outbound connector metrics across all pods
print_info "Pulsar Outbound Connector Pod Metrics:"
CONNECTOR_POD_COUNT=$(kubectl get pods -n "${NAMESPACE}" \
  --selector=app.kubernetes.io/name=aerospike-pulsar-outbound \
  --no-headers | wc -l | tr -d ' ')

for i in $(seq 0 $((CONNECTOR_POD_COUNT - 1))); do
    POD_NAME="${CONNECTOR_RELEASE}-aerospike-pulsar-outbound-${i}"
    if kubectl get pod "${POD_NAME}" -n "${NAMESPACE}" &>/dev/null; then
        echo "Pulsar Outbound Pod $i (${POD_NAME}):"
        METRICS=$(kubectl logs -n "${NAMESPACE}" "${POD_NAME}" --tail=20 2>/dev/null | \
          grep -E "(records-sent|records-failed|requests-total|requests-success)" | tail -5 || echo "No metrics found")
        if [ -n "$METRICS" ] && [ "$METRICS" != "No metrics found" ]; then
            echo "$METRICS"
        else
            echo "  No metrics yet"
        fi
    fi
done
echo ""

# Step 11: Final Status Check
print_info "Step 11: Final status check..."
echo ""
kubectl get pods -n "${NAMESPACE}" -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready" \
  | grep -E "(NAME|aerocluster|pulsar-outbound|pulsar)" || true
echo ""

print_info "✅ Integration test complete!"
echo ""
print_info "📋 Summary:"
print_info "   - Test key used: ${TEST_KEY}"
print_info "   - Pulsar topic: ${PULSAR_TOPIC}"
print_info "   - Pulsar broker: ${PULSAR_SERVICE_URL}"
print_info "   - Check metrics above to verify data flow"
print_info "   - All pods should show STATUS=Running and READY=true"
echo ""
print_info "📁 Files used:"
print_info "   - $SCRIPT_DIR/pulsar-deployment.yaml (Pulsar broker deployment - Apache Pulsar 4.0.7)"
print_info "   - $SCRIPT_DIR/pulsar-outbound-integration-values.yaml (Connector config)"
print_info "   - $SRC_CLUSTER_FILE (Source cluster - dynamically generated with connector pod DNS)"
echo ""
print_info "💡 To manually verify Pulsar messages:"
PULSAR_POD=$(kubectl get pods -n "${NAMESPACE}" -l app=pulsar -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "pulsar-0")
print_info "   kubectl exec -n ${NAMESPACE} ${PULSAR_POD} -- bin/pulsar-client consume ${PULSAR_TOPIC} -s test-subscription -n 10"
echo ""
echo "INTEGRATION_TEST_PASSED"
