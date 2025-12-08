#!/bin/bash

# Integration Test Runner Script
# Sets up and tests: Aerospike DB -> Kafka Outbound Connector -> Kafka Broker
# This script:
# 1. Deploys Kafka broker
# 2. Deploys Kafka Outbound connector
# 3. Deploys Aerospike cluster (source) with XDR pointing to connector
# 4. Installs Aerospike tools
# 5. Executes test data flow
# 6. Displays metrics and status

set -e

NAMESPACE="aerospike-test"
KAFKA_RELEASE="kafka"
CONNECTOR_RELEASE="test-kafka-outbound"
SRC_CLUSTER="aerocluster-kafka-src"
KAFKA_TOPIC="aerospike"
CONTEXT="kind-kafka-test-cluster"  # Explicit context for parallel execution safety

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

print_info "🚀 Setting up Kafka Outbound Integration Test Environment"
print_info "======================================================"
echo ""

# Verify existing files exist
if [ ! -f "$SCRIPT_DIR/kafka-deployment.yaml" ]; then
    print_error "kafka-deployment.yaml not found in $SCRIPT_DIR"
    echo "INTEGRATION_TEST_FAILED"
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/kafka-outbound-integration-values.yaml" ]; then
    print_error "kafka-outbound-integration-values.yaml not found in $SCRIPT_DIR"
    echo "INTEGRATION_TEST_FAILED"
    exit 1
fi

print_info "✅ Using existing configuration files from $SCRIPT_DIR"
echo ""

# Check if TLS secrets are needed for Kafka Outbound
CONNECTOR_VALUES_FILE="$SCRIPT_DIR/kafka-outbound-integration-values.yaml"
if [ -f "$CONNECTOR_VALUES_FILE" ]; then
    if grep -q "connectorSecrets:" "$CONNECTOR_VALUES_FILE" && ! grep -q "^#.*connectorSecrets:" "$CONNECTOR_VALUES_FILE"; then
        if grep -q "tls-certs-kafka" "$CONNECTOR_VALUES_FILE"; then
            print_info "Checking for TLS secret 'tls-certs-kafka'..."
            if ! kubectl get secret tls-certs-kafka -n "${NAMESPACE}" &>/dev/null; then
                print_warning "TLS secret 'tls-certs-kafka' not found in namespace ${NAMESPACE}"
                CHART_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
                TLS_CERTS_DIR="${CHART_ROOT}/examples/tls/tls-certs"
                if [ -d "$TLS_CERTS_DIR" ]; then
                    print_info "Creating TLS secret from ${TLS_CERTS_DIR}..."
                    if kubectl create secret generic tls-certs-kafka --from-file="${TLS_CERTS_DIR}" -n "${NAMESPACE}" 2>/dev/null; then
                        print_info "✅ TLS secret created successfully"
                    else
                        print_warning "Failed to create TLS secret. Continuing anyway..."
                    fi
                else
                    print_warning "TLS secret 'tls-certs-kafka' is required but ${TLS_CERTS_DIR} not found."
                    print_info "  kubectl create secret generic tls-certs-kafka --from-file=<path-to-tls-certs> -n ${NAMESPACE}"
                fi
            else
                print_info "✅ TLS secret 'tls-certs-kafka' already exists"
            fi
            echo ""
        fi
    fi
fi

# Check for existing deployments and clean up if needed
print_info "Checking for existing deployments..."
EXISTING_HELM=$(helm list -n "${NAMESPACE}" --short 2>/dev/null | grep -E "(${CONNECTOR_RELEASE}|${KAFKA_RELEASE})" || true)
EXISTING_CLUSTERS=$(kubectl get aerospikecluster -n "${NAMESPACE}" -o name 2>/dev/null | grep -E "${SRC_CLUSTER}" || true)

if [ -n "$EXISTING_HELM" ] || [ -n "$EXISTING_CLUSTERS" ]; then
    print_warning "Found existing deployments. Cleaning up..."
    echo ""
    
    if helm list -n "${NAMESPACE}" --short | grep -q "^${CONNECTOR_RELEASE}$"; then
        print_info "Uninstalling existing ${CONNECTOR_RELEASE}..."
        helm uninstall "${CONNECTOR_RELEASE}" -n "${NAMESPACE}" 2>/dev/null || true
    fi
    
    if helm list -n "${NAMESPACE}" --short | grep -q "^${KAFKA_RELEASE}$"; then
        print_info "Uninstalling existing ${KAFKA_RELEASE}..."
        helm uninstall "${KAFKA_RELEASE}" -n "${NAMESPACE}" 2>/dev/null || true
    fi
    
    # Also clean up direct Kubernetes resources
    kubectl delete statefulset kafka -n "${NAMESPACE}" 2>/dev/null || true
    kubectl delete service kafka kafka-headless -n "${NAMESPACE}" 2>/dev/null || true
    
    if kubectl get aerospikecluster "${SRC_CLUSTER}" -n "${NAMESPACE}" &>/dev/null; then
        print_info "Deleting existing ${SRC_CLUSTER}..."
        kubectl delete aerospikecluster "${SRC_CLUSTER}" -n "${NAMESPACE}" 2>/dev/null || true
    fi
    
    print_info "Waiting for cleanup to complete (10 seconds)..."
    sleep 10
    echo ""
fi

# Step 1: Deploy Kafka broker
print_info "Step 1: Deploying Kafka broker..."
print_info "Using Apache Kafka 4.1.0 official image (KRaft mode, no ZooKeeper required)..."

# Deploy Kafka using Apache Kafka official images
kubectl apply -f "$SCRIPT_DIR/kafka-deployment.yaml"

print_info "Waiting for Kafka pods to be ready (this may take a few minutes)..."
# Wait for Kafka StatefulSet to be ready
kubectl wait --for=condition=ready pod \
  -l app=kafka \
  -n ${NAMESPACE} \
  --timeout=10m || print_warning "Kafka pods may still be starting"

print_info "✅ Kafka broker deployed"
echo ""

# Get Kafka broker service name
KAFKA_SERVICE="kafka"
KAFKA_BOOTSTRAP_SERVERS="${KAFKA_SERVICE}.${NAMESPACE}.svc.cluster.local:9092"

# Step 2: Update connector values with Kafka broker address
print_info "Step 2: Updating connector configuration with Kafka broker address..."
TEMP_VALUES=$(mktemp)
# Update bootstrap servers in the values file
sed "s|- kafka.aerospike-test.svc.cluster.local:9092|- ${KAFKA_BOOTSTRAP_SERVERS}|g" \
  "$SCRIPT_DIR/kafka-outbound-integration-values.yaml" > "$TEMP_VALUES"

# Step 3: Deploy Kafka Outbound connector
print_info "Step 3: Deploying Kafka Outbound connector..."
helm install "${CONNECTOR_RELEASE}" "$SCRIPT_DIR/../.." \
  -n "${NAMESPACE}" \
  -f "$TEMP_VALUES" \
  --wait --timeout=2m

rm -f "$TEMP_VALUES"
print_info "✅ Kafka Outbound connector deployed"
echo ""

# Step 4: Get connector pod DNS names and create source cluster YAML
print_info "Step 4: Getting Kafka Outbound connector pod DNS names..."
CONNECTOR_PODS=$(kubectl get pods -n "${NAMESPACE}" \
  --selector=app.kubernetes.io/name=aerospike-kafka-outbound \
  --no-headers -o custom-columns=":metadata.name" | head -3)

if [ -z "$CONNECTOR_PODS" ]; then
    print_error "No Kafka Outbound connector pods found. Please check deployment."
    echo "INTEGRATION_TEST_FAILED"
    exit 1
fi

CONNECTOR_POD_DNS=""
for pod in $CONNECTOR_PODS; do
    CONNECTOR_POD_DNS="${CONNECTOR_POD_DNS}            - ${pod}.${CONNECTOR_RELEASE}-aerospike-kafka-outbound.${NAMESPACE}.svc.cluster.local:8080\n"
done

print_info "Kafka Outbound connector pods found:"
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
        port: 3020
      fabric:
        port: 3021
      heartbeat:
        port: 3022
    namespaces:
      - name: test
        replication-factor: 1
        storage-engine:
          type: memory
          data-size: 300000000  # 300MB - minimum required for Aerospike 8.0.0.8
    xdr:
      dcs:
        - name: kafka
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
timeout=240
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
    kubectl cp "${LOCAL_TOOLS_FILE}" ${NAMESPACE}/${SRC_CLUSTER}-0-0:/tmp/tools.tgz || {
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
    # Install libreadline (try both versions for different Ubuntu releases)
    (apt-get install -y -qq libreadline8 > /dev/null 2>&1 || apt-get install -y -qq libreadline9 > /dev/null 2>&1 || true) && \
    # Extract tar file (tar will fail if file is invalid)
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
    # Use wget with redirect following and proper URL
    wget --no-check-certificate --content-disposition -q 'https://download.aerospike.com/artifacts/aerospike-server-enterprise/8.0.0.8/${TOOLS_PKG}' -O tools.tgz || \
    curl -L -o tools.tgz 'https://download.aerospike.com/artifacts/aerospike-server-enterprise/8.0.0.8/${TOOLS_PKG}' && \
    # Extract tar file (tar will fail if file is invalid)
    tar -xzf tools.tgz > /dev/null 2>&1 && \
    # Install libreadline (try both versions for different Ubuntu releases)
    (apt-get install -y -qq libreadline8 > /dev/null 2>&1 || apt-get install -y -qq libreadline9 > /dev/null 2>&1 || true) && \
    dpkg -i aerospike-server-enterprise_8.0.0.8_tools-11.2.2_ubuntu20.04_*/${DEB_PKG} > /dev/null 2>&1 && \
    echo '✅ Tools installed successfully from download'
    " || print_warning "Tools installation from download may have failed (check manually)"
fi

print_info "✅ Tools installation complete"
echo ""

# Step 8: Create Kafka topic (if needed)
print_info "Step 8: Creating Kafka topic '${KAFKA_TOPIC}'..."
# Find Kafka pod name
KAFKA_POD=$(kubectl get pods -n "${NAMESPACE}" -l app=kafka -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$KAFKA_POD" ]; then
    print_warning "Kafka pod not found, skipping topic creation"
else
    # Wait a bit for Kafka to be fully ready
    sleep 5
    
    # Find kafka-topics.sh script path (Apache Kafka image uses /opt/kafka/bin/)
    KAFKA_TOPICS_SCRIPT="/opt/kafka/bin/kafka-topics.sh"
    
    # Check if topic exists
    TOPIC_LIST=$(kubectl exec -n "${NAMESPACE}" "${KAFKA_POD}" -- bash -c "${KAFKA_TOPICS_SCRIPT} --list --bootstrap-server localhost:9092 2>&1" || echo "")
    
    if echo "$TOPIC_LIST" | grep -q "^${KAFKA_TOPIC}$"; then
        print_info "✅ Kafka topic already exists"
    else
        # Create topic (Kafka 4.1.0 auto-creates topics, but we'll try explicit creation)
        CREATE_OUTPUT=$(kubectl exec -n "${NAMESPACE}" "${KAFKA_POD}" -- bash -c "${KAFKA_TOPICS_SCRIPT} --create --bootstrap-server localhost:9092 --topic ${KAFKA_TOPIC} --partitions 3 --replication-factor 1 2>&1" || echo "")
        
        if echo "$CREATE_OUTPUT" | grep -qE "(Created topic|already exists)"; then
            print_info "✅ Kafka topic created or already exists"
        else
            # Kafka 4.1.0 auto-creates topics, so this is OK
            print_info "✅ Topic will be auto-created when first message arrives (Kafka 4.1.0 feature)"
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
INSERT_OUTPUT=$(kubectl exec -n "${NAMESPACE}" "${SRC_CLUSTER}-0-0" -- aql -h localhost -p 3020 -c \
  "INSERT INTO test.demo (PK, name, value) VALUES ('${TEST_KEY}', 'Test Record', 100)" 2>&1)

if echo "$INSERT_OUTPUT" | grep -q "OK"; then
    print_info "✅ Test data inserted successfully"
else
    print_warning "⚠️  Data insertion may have failed (check logs)"
    echo "$INSERT_OUTPUT"
fi

# Wait for data to flow through pipeline
print_info "Waiting for data replication to Kafka (10 seconds)..."
sleep 10

# Verify data in Kafka
print_info "Verifying data in Kafka topic '${KAFKA_TOPIC}'..."
print_info "Checking messages in Kafka partitions..."
# Find Kafka pod name
KAFKA_POD=$(kubectl get pods -n "${NAMESPACE}" -l app=kafka -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
FOUND_MESSAGE=false
if [ -n "$KAFKA_POD" ]; then
    KAFKA_CONSUMER_SCRIPT="/opt/kafka/bin/kafka-console-consumer.sh"
    # Check each partition separately to avoid timeout issues
    for PARTITION in 0 1 2; do
        print_info "Checking partition ${PARTITION}..."
        if command -v gtimeout &> /dev/null; then
            KAFKA_MESSAGES=$(gtimeout 10 kubectl exec -n "${NAMESPACE}" "${KAFKA_POD}" -- bash -c "${KAFKA_CONSUMER_SCRIPT} --bootstrap-server localhost:9092 --topic ${KAFKA_TOPIC} --partition ${PARTITION} --from-beginning --max-messages 10 --timeout-ms 8000 2>&1" || true)
        elif command -v timeout &> /dev/null; then
            KAFKA_MESSAGES=$(timeout 10 kubectl exec -n "${NAMESPACE}" "${KAFKA_POD}" -- bash -c "${KAFKA_CONSUMER_SCRIPT} --bootstrap-server localhost:9092 --topic ${KAFKA_TOPIC} --partition ${PARTITION} --from-beginning --max-messages 10 --timeout-ms 8000 2>&1" || true)
        else
            # Fallback: run consumer with timeout
            KAFKA_MESSAGES=$(kubectl exec -n "${NAMESPACE}" "${KAFKA_POD}" -- bash -c "${KAFKA_CONSUMER_SCRIPT} --bootstrap-server localhost:9092 --topic ${KAFKA_TOPIC} --partition ${PARTITION} --from-beginning --max-messages 10 --timeout-ms 8000 2>&1" || echo "")
        fi
        
        # Check if test key is in this partition
        if echo "$KAFKA_MESSAGES" | grep -q "${TEST_KEY}"; then
            print_info "✅ Test data found in Kafka partition ${PARTITION}!"
            echo "$KAFKA_MESSAGES" | grep -E "(metadata|userKey|${TEST_KEY})" | head -3
            FOUND_MESSAGE=true
            break
        elif echo "$KAFKA_MESSAGES" | grep -q "Processed a total of"; then
            MSG_COUNT=$(echo "$KAFKA_MESSAGES" | grep "Processed a total of" | sed 's/.*Processed a total of \([0-9]*\) messages.*/\1/' || echo "0")
            if [ "$MSG_COUNT" -gt 0 ] 2>/dev/null; then
                print_info "Found ${MSG_COUNT} message(s) in partition ${PARTITION}"
                echo "$KAFKA_MESSAGES" | grep -v "ERROR\|Error\|timeout\|Exception" | head -2
            fi
        fi
    done
    
    if [ "$FOUND_MESSAGE" = false ]; then
        print_error "❌ Test FAILED: Test key '${TEST_KEY}' not found in Kafka partitions"
        print_warning "This may indicate:"
        print_warning "  - Kafka Outbound connector is not forwarding data correctly"
        print_warning "  - Data replication delay (try waiting longer)"
        print_warning "  - Network connectivity issues"
        echo ""
        echo "INTEGRATION_TEST_FAILED"
        exit 1
    fi
else
    print_error "❌ Test FAILED: Kafka pod not found for message verification"
    echo ""
    echo "INTEGRATION_TEST_FAILED"
    exit 1
fi
echo ""

# Step 10: Display Metrics
print_info "Step 10: Checking component metrics..."
echo ""

# Check Kafka Outbound connector metrics across all pods
print_info "Kafka Outbound Connector Pod Metrics:"
CONNECTOR_POD_COUNT=$(kubectl get pods -n "${NAMESPACE}" \
  --selector=app.kubernetes.io/name=aerospike-kafka-outbound \
  --no-headers | wc -l | tr -d ' ')

for i in $(seq 0 $((CONNECTOR_POD_COUNT - 1))); do
    POD_NAME="${CONNECTOR_RELEASE}-aerospike-kafka-outbound-${i}"
    if kubectl get pod "${POD_NAME}" -n "${NAMESPACE}" &>/dev/null; then
        echo "Kafka Outbound Pod $i (${POD_NAME}):"
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
  | grep -E "(NAME|aerocluster|kafka-outbound|kafka)" || true
echo ""

print_info "✅ Integration test complete!"
echo ""
print_info "📋 Summary:"
print_info "   - Test key used: ${TEST_KEY}"
print_info "   - Kafka topic: ${KAFKA_TOPIC}"
print_info "   - Kafka broker: ${KAFKA_BOOTSTRAP_SERVERS}"
print_info "   - Check metrics above to verify data flow"
print_info "   - All pods should show STATUS=Running and READY=true"
echo ""
print_info "📁 Files used:"
print_info "   - $SCRIPT_DIR/kafka-deployment.yaml (Kafka broker deployment - Apache Kafka 4.1.0)"
print_info "   - $SCRIPT_DIR/kafka-outbound-integration-values.yaml (Connector config)"
print_info "   - $SRC_CLUSTER_FILE (Source cluster - dynamically generated with connector pod DNS)"
echo ""
print_info "💡 To manually verify Kafka messages:"
KAFKA_POD=$(kubectl get pods -n "${NAMESPACE}" -l app=kafka -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "kafka-0")
print_info "   kubectl exec -n ${NAMESPACE} ${KAFKA_POD} -- bash -c \"/opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic ${KAFKA_TOPIC} --from-beginning\""
echo ""
echo "INTEGRATION_TEST_PASSED"
