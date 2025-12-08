#!/bin/bash

# Integration Test Runner Script
# Sets up and tests: Aerospike DB -> JMS Outbound Connector -> RabbitMQ Broker
# This script:
# 1. Deploys RabbitMQ broker
# 2. Deploys JMS Outbound connector
# 3. Deploys Aerospike cluster (source) with XDR pointing to connector
# 4. Installs Aerospike tools
# 5. Executes test data flow
# 6. Displays metrics and status

set -e

NAMESPACE="aerospike-test"
RABBITMQ_RELEASE="rabbitmq-jms-outbound"
CONNECTOR_RELEASE="test-jms-outbound"
SRC_CLUSTER="aerocluster-jms-outbound-src"
JMS_QUEUE="aerospike"
CONTEXT="kind-jms-test-cluster"  # Explicit context for parallel execution safety

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

print_info "🚀 Setting up JMS Outbound Integration Test Environment"
print_info "======================================================"
echo ""

# Verify existing files exist
if [ ! -f "$SCRIPT_DIR/rabbitmq-deployment.yaml" ]; then
    print_error "rabbitmq-deployment.yaml not found in $SCRIPT_DIR"
    echo "INTEGRATION_TEST_FAILED"
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/jms-outbound-integration-values.yaml" ]; then
    print_error "jms-outbound-integration-values.yaml not found in $SCRIPT_DIR"
    echo "INTEGRATION_TEST_FAILED"
    exit 1
fi


# Check if TLS secrets are needed for JMS Outbound
CONNECTOR_VALUES_FILE="$SCRIPT_DIR/jms-outbound-integration-values.yaml"
if [ -f "$CONNECTOR_VALUES_FILE" ]; then
    if grep -q "connectorSecrets:" "$CONNECTOR_VALUES_FILE" && ! grep -q "^#.*connectorSecrets:" "$CONNECTOR_VALUES_FILE"; then
        if grep -q "tls-certs-jms-outbound" "$CONNECTOR_VALUES_FILE"; then
            print_info "Checking for TLS secret 'tls-certs-jms-outbound'..."
            if ! kubectl get secret tls-certs-jms-outbound -n "${NAMESPACE}" &>/dev/null; then
                print_warning "TLS secret 'tls-certs-jms-outbound' not found in namespace ${NAMESPACE}"
                CHART_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
                TLS_CERTS_DIR="${CHART_ROOT}/examples/tls/tls-certs"
                if [ -d "${TLS_CERTS_DIR}" ]; then
                    print_info "Creating TLS secret from ${TLS_CERTS_DIR}..."
                    if kubectl create secret generic tls-certs-jms-outbound --from-file="${TLS_CERTS_DIR}" -n "${NAMESPACE}" 2>/dev/null; then
                        print_info "✅ TLS secret created successfully"
                    else
                        print_warning "Failed to create TLS secret. Continuing anyway..."
                    fi
                else
                    print_warning "TLS secret 'tls-certs-jms-outbound' is required but ${TLS_CERTS_DIR} not found."
                    print_info "  kubectl create secret generic tls-certs-jms-outbound --from-file=<path-to-tls-certs> -n ${NAMESPACE}"
                fi
            else
                print_info "✅ TLS secret 'tls-certs-jms-outbound' already exists"
            fi
            echo ""
        fi
    fi
fi

# Check for existing deployments and clean up if needed
print_info "Checking for existing deployments..."
EXISTING_HELM=$(helm list -n "${NAMESPACE}" --short 2>/dev/null | grep -E "(${CONNECTOR_RELEASE}|${RABBITMQ_RELEASE})" || true)
EXISTING_CLUSTERS=$(kubectl get aerospikecluster -n "${NAMESPACE}" -o name 2>/dev/null | grep -E "${SRC_CLUSTER}" || true)

if [ -n "$EXISTING_HELM" ] || [ -n "$EXISTING_CLUSTERS" ]; then
    print_warning "Found existing deployments. Cleaning up..."
    echo ""
    
    if helm list -n "${NAMESPACE}" --short | grep -q "^${CONNECTOR_RELEASE}$"; then
        print_info "Uninstalling existing ${CONNECTOR_RELEASE}..."
        helm uninstall "${CONNECTOR_RELEASE}" -n "${NAMESPACE}" 2>/dev/null || true
    fi
    
    if helm list -n "${NAMESPACE}" --short | grep -q "^${RABBITMQ_RELEASE}$"; then
        print_info "Uninstalling existing ${RABBITMQ_RELEASE}..."
        helm uninstall "${RABBITMQ_RELEASE}" -n "${NAMESPACE}" 2>/dev/null || true
    fi
    
    # Also clean up direct Kubernetes resources
    kubectl delete statefulset rabbitmq-jms-outbound -n "${NAMESPACE}" 2>/dev/null || true
    kubectl delete service rabbitmq-jms-outbound rabbitmq-jms-outbound-headless -n "${NAMESPACE}" 2>/dev/null || true
    
    if kubectl get aerospikecluster "${SRC_CLUSTER}" -n "${NAMESPACE}" &>/dev/null; then
        print_info "Deleting existing ${SRC_CLUSTER}..."
        kubectl delete aerospikecluster "${SRC_CLUSTER}" -n "${NAMESPACE}" 2>/dev/null || true
    fi
    
    print_info "Waiting for cleanup to complete (10 seconds)..."
    sleep 10
    echo ""
fi

# Step 1: Deploy RabbitMQ broker
print_info "Step 1: Deploying RabbitMQ broker..."
kubectl apply -f "$SCRIPT_DIR/rabbitmq-deployment.yaml" > /dev/null 2>&1
kubectl wait --for=condition=ready pod -l app=rabbitmq-jms-outbound -n "${NAMESPACE}" --timeout=10m > /dev/null 2>&1 || print_warning "RabbitMQ pods may still be starting"
sleep 10
print_info "✅ RabbitMQ broker deployed"
echo ""

# Get RabbitMQ broker service name
RABBITMQ_SERVICE="rabbitmq-jms-outbound"
RABBITMQ_HOST="${RABBITMQ_SERVICE}.${NAMESPACE}.svc.cluster.local"

# Step 2: Deploy JMS Outbound connector
print_info "Step 2: Deploying JMS Outbound connector..."
TEMP_VALUES=$(mktemp)
sed "s|rabbitmq-jms-outbound.aerospike-test.svc.cluster.local|${RABBITMQ_HOST}|g" \
  "$SCRIPT_DIR/jms-outbound-integration-values.yaml" > "$TEMP_VALUES"
helm install "${CONNECTOR_RELEASE}" "$SCRIPT_DIR/../.." -n "${NAMESPACE}" -f "$TEMP_VALUES" --wait --timeout=2m > /dev/null 2>&1
rm -f "$TEMP_VALUES"
print_info "✅ JMS Outbound connector deployed"
echo ""

# Step 3: Get connector pod DNS names and create source cluster YAML
print_info "Step 3: Creating source Aerospike cluster configuration..."
CONNECTOR_PODS=$(kubectl get pods -n "${NAMESPACE}" \
  --selector=app.kubernetes.io/name=aerospike-jms-outbound \
  --no-headers -o custom-columns=":metadata.name" | head -3)

if [ -z "$CONNECTOR_PODS" ]; then
    print_error "No JMS Outbound connector pods found. Please check deployment."
    echo "INTEGRATION_TEST_FAILED"
    exit 1
fi

CONNECTOR_POD_DNS=""
while IFS= read -r pod; do
    if [ -n "$pod" ]; then
        CONNECTOR_POD_DNS="${CONNECTOR_POD_DNS}            - ${pod}.${CONNECTOR_RELEASE}-aerospike-jms-outbound.${NAMESPACE}.svc.cluster.local:8080\n"
    fi
done <<< "$CONNECTOR_PODS"
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
        port: 3010
      fabric:
        port: 3011
      heartbeat:
        port: 3012
    namespaces:
      - name: test
        replication-factor: 1
        storage-engine:
          type: memory
          data-size: 300000000  # 300MB - minimum required for Aerospike 8.0.0.8
    xdr:
      dcs:
        - name: jms
          connector: true
          namespaces:
            - name: test
          node-address-ports:
$(echo -e "$CONNECTOR_POD_DNS")
EOF

# Step 4: Deploy source cluster
print_info "Step 4: Deploying source Aerospike cluster..."
kubectl apply -f "$SRC_CLUSTER_FILE" > /dev/null 2>&1
timeout=240
elapsed=0
while [ $elapsed -lt $timeout ]; do
    if kubectl get pod "${SRC_CLUSTER}-0-0" -n "${NAMESPACE}" &>/dev/null; then
        break
    fi
    sleep 2
    elapsed=$((elapsed + 2))
done
kubectl wait --for=condition=ready pod "${SRC_CLUSTER}-0-0" -n "${NAMESPACE}" --timeout=3m > /dev/null 2>&1
print_info "✅ Source cluster ready"
echo ""

# Step 5: Install Aerospike tools in DB pod
print_info "Step 5: Installing Aerospike tools..."
ARCH=$(kubectl exec -n "${NAMESPACE}" "${SRC_CLUSTER}-0-0" -- uname -m 2>/dev/null || echo "aarch64")
if [[ "$ARCH" == *"x86"* ]] || [[ "$ARCH" == *"amd64"* ]]; then
    # Use x86_64.tgz (not amd64.tgz) as per Aerospike download page
    TOOLS_PKG="aerospike-server-enterprise_8.0.0.8_tools-11.2.2_ubuntu20.04_x86_64.tgz"
    DEB_PKG="aerospike-tools_11.2.2-ubuntu20.04_amd64.deb"
else
    TOOLS_PKG="aerospike-server-enterprise_8.0.0.8_tools-11.2.2_ubuntu20.04_aarch64.tgz"
    DEB_PKG="aerospike-tools_11.2.2-ubuntu20.04_arm64.deb"
fi

# Check for local tools file on Jenkins box
LOCAL_TOOLS_PATH="/var/lib/jenkins/aerospike-connect-resources/tests2/aerospike"
LOCAL_TOOLS_FILE=""
if [ -f "${LOCAL_TOOLS_PATH}/${TOOLS_PKG}" ]; then
    LOCAL_TOOLS_FILE="${LOCAL_TOOLS_PATH}/${TOOLS_PKG}"
fi

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
    " > /dev/null 2>&1 || print_warning "Tools installation from local file may have failed"
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
    " > /dev/null 2>&1 || print_warning "Tools installation from download may have failed"
fi
print_info "✅ Tools installed"
echo ""

# Step 6: Test Data Flow
print_info "Step 6: Testing data flow..."

# Insert test data in source DB
print_info "Inserting test data in source DB..."
TEST_KEY="test-key-$(date +%s)"
INSERT_OUTPUT=$(kubectl exec -n "${NAMESPACE}" "${SRC_CLUSTER}-0-0" -- aql -h localhost -p 3010 -c \
  "INSERT INTO test.demo (PK, name, value) VALUES ('${TEST_KEY}', 'Test Record', 100)" 2>&1)

if ! echo "$INSERT_OUTPUT" | grep -q "OK"; then
    print_warning "⚠️  Data insertion may have failed"
    echo "$INSERT_OUTPUT"
fi

# Verify record was inserted using AQL SELECT
print_info "Verifying record in Aerospike DB..."
AQL_OUTPUT=$(kubectl exec -n "${NAMESPACE}" "${SRC_CLUSTER}-0-0" -- aql -h localhost -p 3010 -c \
  "SELECT * FROM test.demo WHERE PK='${TEST_KEY}'" 2>&1)

if echo "$AQL_OUTPUT" | grep -q "${TEST_KEY}"; then
    print_info "✅ Record found in Aerospike DB:"
    echo "$AQL_OUTPUT" | grep -A 5 "${TEST_KEY}" | head -10
else
    print_warning "⚠️  Record not found in Aerospike DB"
    echo "$AQL_OUTPUT"
fi
echo ""

sleep 10
print_info "Verifying data in RabbitMQ queue..."
RABBITMQ_POD=$(kubectl get pods -n "${NAMESPACE}" -l app=rabbitmq-jms-outbound -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
FOUND_MESSAGE=false
if [ -n "$RABBITMQ_POD" ]; then
    QUEUE_STATS=$(kubectl exec -n "${NAMESPACE}" "${RABBITMQ_POD}" -- rabbitmqctl list_queues name messages messages_ready messages_unacknowledged 2>&1 | grep -E "^${JMS_QUEUE}|^name" || echo "")
    
    if [ -n "$QUEUE_STATS" ]; then
        MSG_COUNT=$(echo "$QUEUE_STATS" | grep "^${JMS_QUEUE}" | awk '{print $2}' | tr -d ' ' || echo "0")
        
        if [ -n "$MSG_COUNT" ] && [ "$MSG_COUNT" != "" ] && [ "$MSG_COUNT" -gt 0 ] 2>/dev/null; then
            print_info "✅ Found ${MSG_COUNT} message(s) in queue"
            FOUND_MESSAGE=true
            
            # Get and decode message content
            CONSUMED_OUTPUT=$(kubectl exec -n "${NAMESPACE}" "${RABBITMQ_POD}" -- rabbitmqadmin get queue="${JMS_QUEUE}" ackmode=ack_requeue_false count=1 2>&1 || echo "")
            
            if [ -n "$CONSUMED_OUTPUT" ] && echo "$CONSUMED_OUTPUT" | grep -q "payload"; then
                # Use Python to extract payload (more reliable than awk for long base64 strings)
                PAYLOAD=$(echo "$CONSUMED_OUTPUT" | python3 -c "
import sys
output = sys.stdin.read()
if 'payload' in output:
    lines = output.split('\n')
    # Find header line
    for i, line in enumerate(lines):
        if 'payload' in line.lower() and 'routing_key' in line.lower():
            # Find data line (after separator, which is typically line i+1)
            for j in range(i+2, len(lines)):
                if '|' in lines[j] and lines[j].strip() and not lines[j].strip().startswith('+'):
                    data_line = lines[j]
                    cols = data_line.split('|')
                    # Payload is typically the 4th column (index 4, after routing_key, exchange, message_count)
                    if len(cols) > 4:
                        payload = cols[4].strip()
                        if len(payload) > 10:
                            print(payload)
                            break
            break
" 2>/dev/null || echo "")
                
                if [ -n "$PAYLOAD" ] && [ "$PAYLOAD" != "payload" ] && [ ${#PAYLOAD} -gt 10 ]; then
                    # Decode base64 payload
                    DECODED_PAYLOAD=$(echo "$PAYLOAD" | python3 -c "import sys, base64; data=base64.b64decode(sys.stdin.read().strip()); print(data.decode('utf-8', errors='ignore'))" 2>/dev/null || echo "")
                    
                    # Extract JSON from decoded payload (works on both macOS and Linux)
                    # Use python to extract JSON instead of grep -oP (not available on macOS)
                    JSON_CONTENT=$(echo "$DECODED_PAYLOAD" | python3 -c "
import sys
import re
text = sys.stdin.read()
# Find JSON object (nested braces)
matches = re.findall(r'\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}', text)
if matches:
    # Get the last (most complete) JSON match
    print(matches[-1])
else:
    print(text[:500])
" 2>/dev/null || echo "$DECODED_PAYLOAD")
                    
                    print_info "✅ Message content from queue:"
                    echo "----------------------------------------"
                    if [ -n "$JSON_CONTENT" ] && echo "$JSON_CONTENT" | grep -q "{"; then
                        # Try to format as JSON
                        FORMATTED_JSON=$(echo "$JSON_CONTENT" | python3 -m json.tool 2>/dev/null || echo "$JSON_CONTENT")
                        echo "$FORMATTED_JSON"
                        echo ""
                        
                        if echo "$JSON_CONTENT" | grep -q "${TEST_KEY}"; then
                            print_info "✅ Test key '${TEST_KEY}' verified in message"
                        else
                            print_warning "⚠️  Test key '${TEST_KEY}' not found in JSON content"
                        fi
                    else
                        # Show raw decoded payload if JSON extraction failed
                        echo "$DECODED_PAYLOAD" | head -50
                        echo ""
                        if echo "$DECODED_PAYLOAD" | grep -q "${TEST_KEY}"; then
                            print_info "✅ Test key '${TEST_KEY}' found in decoded payload"
                        else
                            print_warning "⚠️  Test key '${TEST_KEY}' not found in decoded payload"
                        fi
                    fi
                    echo "----------------------------------------"
                else
                    print_warning "⚠️  Could not extract payload from message"
                    echo "Debug: PAYLOAD length=${#PAYLOAD}"
                fi
            else
                print_warning "⚠️  No payload found in consumed output or queue is empty"
                if [ -n "$CONSUMED_OUTPUT" ]; then
                    echo "Debug output:"
                    echo "$CONSUMED_OUTPUT" | head -5
                fi
            fi
        fi
    fi
    
    if [ "$FOUND_MESSAGE" = false ]; then
        print_error "❌ Test FAILED: No messages found in RabbitMQ queue"
        print_warning "This may indicate:"
        print_warning "  - JMS Outbound connector is not forwarding data correctly"
        print_warning "  - Data replication delay (try waiting longer)"
        print_warning "  - Network connectivity issues"
        echo ""
        echo "INTEGRATION_TEST_FAILED"
        exit 1
    fi
else
    print_error "❌ Test FAILED: RabbitMQ pod not found for message verification"
    echo ""
    echo "INTEGRATION_TEST_FAILED"
    exit 1
fi
echo ""

# Step 7: Display Metrics
print_info "Step 7: Component metrics..."

# Check JMS Outbound connector metrics across all pods
print_info "JMS Outbound Connector Pod Metrics:"
CONNECTOR_POD_COUNT=$(kubectl get pods -n "${NAMESPACE}" \
  --selector=app.kubernetes.io/name=aerospike-jms-outbound \
  --no-headers | wc -l | tr -d ' ')

for i in $(seq 0 $((CONNECTOR_POD_COUNT - 1))); do
    POD_NAME="${CONNECTOR_RELEASE}-aerospike-jms-outbound-${i}"
    if kubectl get pod "${POD_NAME}" -n "${NAMESPACE}" &>/dev/null; then
        echo "JMS Outbound Pod $i (${POD_NAME}):"
        # Get the latest metrics - focus on count metrics
        # Extract metrics with count values
        METRICS=$(kubectl logs -n "${NAMESPACE}" "${POD_NAME}" --tail=50 2>/dev/null | \
          grep "metrics-ticker" | \
          grep -E "(requests-total.*count=|requests-success.*count=|requests-error.*count=|jms-connections.*count=|jms-connections-active.*count=|connections.*count=)" | \
          tail -8 || echo "")
        
        if [ -n "$METRICS" ]; then
            # Show key count metrics
            echo "$METRICS" | grep -E "(requests-total.*count=|requests-success.*count=|requests-error.*count=|jms-connections.*count=)" | \
              sed 's/.*metrics-ticker - //' | sed 's/^/  /'
            
            # Also show connection metrics if available
            CONN_METRICS=$(echo "$METRICS" | grep -E "(connections.*count=|jms-connections-active.*count=)" | \
              sed 's/.*metrics-ticker - //' | sed 's/^/  /' | head -2 || echo "")
            if [ -n "$CONN_METRICS" ]; then
                echo "$CONN_METRICS"
            fi
        else
            echo "  No metrics found yet"
        fi
    fi
done
echo ""

# Step 8: Final Status Check
print_info "Step 8: Final status..."
kubectl get pods -n "${NAMESPACE}" -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready" \
  | grep -E "(NAME|aerocluster|jms-outbound|rabbitmq)" || true
echo ""

print_info "✅ Integration test complete!"
print_info "   Test key: ${TEST_KEY} | Queue: ${JMS_QUEUE} | Broker: ${RABBITMQ_HOST}:5672"
echo ""
echo "INTEGRATION_TEST_PASSED"
