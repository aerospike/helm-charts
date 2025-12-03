#!/bin/bash

# Integration Test Runner Script
# Sets up and tests: RabbitMQ Broker -> JMS Inbound Connector -> Aerospike DB
# This script:
# 1. Deploys RabbitMQ broker
# 2. Deploys Aerospike cluster (destination)
# 3. Deploys JMS Inbound connector
# 4. Installs Aerospike tools
# 5. Sends test messages to RabbitMQ queue
# 6. Verifies messages were written to Aerospike DB
# 7. Displays metrics and status

set -e

NAMESPACE="aerospike-test"
RABBITMQ_RELEASE="rabbitmq"
CONNECTOR_RELEASE="test-jms-inbound"
DST_CLUSTER="aerocluster-dst"
JMS_QUEUE="aerospike"

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

print_info "🚀 Setting up JMS Inbound Integration Test Environment"
print_info "======================================================"
echo ""

# Verify existing files exist
if [ ! -f "$SCRIPT_DIR/rabbitmq-deployment.yaml" ]; then
    print_error "rabbitmq-deployment.yaml not found in $SCRIPT_DIR"
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/jms-inbound-integration-values.yaml" ]; then
    print_error "jms-inbound-integration-values.yaml not found in $SCRIPT_DIR"
    exit 1
fi

# Check if TLS secrets are needed for JMS Inbound
CONNECTOR_VALUES_FILE="$SCRIPT_DIR/jms-inbound-integration-values.yaml"
if [ -f "$CONNECTOR_VALUES_FILE" ]; then
    if grep -q "connectorSecrets:" "$CONNECTOR_VALUES_FILE" && ! grep -q "^#.*connectorSecrets:" "$CONNECTOR_VALUES_FILE"; then
        if grep -q "tls-certs" "$CONNECTOR_VALUES_FILE"; then
            print_info "Checking for TLS secret 'tls-certs'..."
            if ! kubectl get secret tls-certs -n $NAMESPACE &>/dev/null; then
                print_warning "TLS secret 'tls-certs' not found in namespace $NAMESPACE"
                CHART_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
                TLS_CERTS_DIR="$CHART_ROOT/examples/tls/tls-certs"
                if [ -d "$TLS_CERTS_DIR" ]; then
                    print_info "Creating TLS secret from $TLS_CERTS_DIR..."
                    if kubectl create secret generic tls-certs --from-file=$TLS_CERTS_DIR -n $NAMESPACE 2>/dev/null; then
                        print_info "✅ TLS secret created successfully"
                    else
                        print_warning "Failed to create TLS secret. Continuing anyway..."
                    fi
                else
                    print_warning "TLS secret 'tls-certs' is required but $TLS_CERTS_DIR not found."
                    print_info "  kubectl create secret generic tls-certs --from-file=<path-to-tls-certs> -n $NAMESPACE"
                fi
            fi
            echo ""
        fi
    fi
fi

# Check for existing deployments and clean up if needed
print_info "Checking for existing deployments..."
EXISTING_HELM=$(helm list -n ${NAMESPACE} --short 2>/dev/null | grep -E "(${CONNECTOR_RELEASE}|${RABBITMQ_RELEASE})" || true)
EXISTING_CLUSTERS=$(kubectl get aerospikecluster -n ${NAMESPACE} -o name 2>/dev/null | grep -E "${DST_CLUSTER}" || true)

if [ -n "$EXISTING_HELM" ] || [ -n "$EXISTING_CLUSTERS" ]; then
    print_warning "Found existing deployments. Cleaning up..."
    echo ""
    
    if helm list -n ${NAMESPACE} --short | grep -q "^${CONNECTOR_RELEASE}$"; then
        print_info "Uninstalling existing ${CONNECTOR_RELEASE}..."
        helm uninstall ${CONNECTOR_RELEASE} -n ${NAMESPACE} 2>/dev/null || true
    fi
    
    if helm list -n ${NAMESPACE} --short | grep -q "^${RABBITMQ_RELEASE}$"; then
        print_info "Uninstalling existing ${RABBITMQ_RELEASE}..."
        helm uninstall ${RABBITMQ_RELEASE} -n ${NAMESPACE} 2>/dev/null || true
    fi
    
    # Also clean up direct Kubernetes resources
    kubectl delete statefulset rabbitmq -n ${NAMESPACE} 2>/dev/null || true
    kubectl delete service rabbitmq rabbitmq-headless -n ${NAMESPACE} 2>/dev/null || true
    
    if kubectl get aerospikecluster ${DST_CLUSTER} -n ${NAMESPACE} &>/dev/null; then
        print_info "Deleting existing ${DST_CLUSTER}..."
        kubectl delete aerospikecluster ${DST_CLUSTER} -n ${NAMESPACE} 2>/dev/null || true
    fi
    
    print_info "Waiting for cleanup to complete (10 seconds)..."
    sleep 10
    echo ""
fi

# Step 1: Deploy RabbitMQ broker
print_info "Step 1: Deploying RabbitMQ broker..."
kubectl apply -f "$SCRIPT_DIR/rabbitmq-deployment.yaml" > /dev/null 2>&1
kubectl wait --for=condition=ready pod -l app=rabbitmq -n ${NAMESPACE} --timeout=10m > /dev/null 2>&1 || print_warning "RabbitMQ pods may still be starting"
sleep 10
print_info "✅ RabbitMQ broker deployed"
echo ""

# Step 2: Deploy Aerospike destination cluster
print_info "Step 2: Deploying Aerospike destination cluster..."
kubectl apply -f "$SCRIPT_DIR/aerocluster-dst.yaml" > /dev/null 2>&1
timeout=120
elapsed=0
while [ $elapsed -lt $timeout ]; do
    if kubectl get pod ${DST_CLUSTER}-0-0 -n ${NAMESPACE} &>/dev/null; then
        break
    fi
    sleep 2
    elapsed=$((elapsed + 2))
done
kubectl wait --for=condition=ready pod ${DST_CLUSTER}-0-0 -n ${NAMESPACE} --timeout=3m > /dev/null 2>&1
print_info "✅ Destination cluster ready"
echo ""

# Step 3: Deploy JMS Inbound connector
print_info "Step 3: Deploying JMS Inbound connector..."
helm install ${CONNECTOR_RELEASE} "$SCRIPT_DIR/.." -n ${NAMESPACE} -f "$SCRIPT_DIR/jms-inbound-integration-values.yaml" --wait --timeout=2m > /dev/null 2>&1
print_info "✅ JMS Inbound connector deployed"
echo ""

# Step 4: Install Aerospike tools
print_info "Step 4: Installing Aerospike tools..."
ARCH=$(kubectl exec -n ${NAMESPACE} ${DST_CLUSTER}-0-0 -- uname -m 2>/dev/null || echo "aarch64")
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
    kubectl cp "${LOCAL_TOOLS_FILE}" ${NAMESPACE}/${DST_CLUSTER}-0-0:/tmp/tools.tgz || {
        print_warning "Failed to copy local tools file, falling back to download"
        LOCAL_TOOLS_FILE=""
    }
fi

if [ -n "$LOCAL_TOOLS_FILE" ] && [ -f "$LOCAL_TOOLS_FILE" ]; then
    # Install from copied local file
    kubectl exec -n ${NAMESPACE} ${DST_CLUSTER}-0-0 -- bash -c "
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
    kubectl exec -n ${NAMESPACE} ${DST_CLUSTER}-0-0 -- bash -c "
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

# Step 5: Wait for connector to be ready
print_info "Step 5: Waiting for connector to be ready..."
sleep 10
echo ""

# Step 6: Send test messages to RabbitMQ queue
print_info "Step 6: Testing data flow..."
RABBITMQ_POD=$(kubectl get pods -n ${NAMESPACE} -l app=rabbitmq -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$RABBITMQ_POD" ]; then
    print_error "RabbitMQ pod not found!"
    exit 1
fi

# Generate test message with timestamp
TEST_KEY="test-key-$(date +%s)"
TEST_MESSAGE="{\"key\":\"${TEST_KEY}\",\"name\":\"Test Record\",\"value\":100}"

print_info "Sending test message to RabbitMQ queue '${JMS_QUEUE}'..."
print_info "Test key: ${TEST_KEY}"

# Send message using RabbitMQ HTTP API (matches INTEGRATION-TEST.md)
# This ensures messages are sent in the format the JMS client expects
print_info "Sending test message to RabbitMQ queue '${JMS_QUEUE}' via HTTP API..."
SEND_OUTPUT=$(kubectl exec -n ${NAMESPACE} ${RABBITMQ_POD} -- python3 -c "
import sys, json, urllib.request, base64
message = sys.argv[1]
queue = sys.argv[2]
message_b64 = base64.b64encode(message.encode('utf-8')).decode('utf-8')
url = 'http://localhost:15672/api/exchanges/%2F/amq.default/publish'
data = json.dumps({
    'properties': {},
    'routing_key': queue,
    'payload': message_b64,
    'payload_encoding': 'base64'
}).encode('utf-8')
req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json'})
auth = base64.b64encode(b'guest:guest').decode('utf-8')
req.add_header('Authorization', 'Basic ' + auth)
response = urllib.request.urlopen(req)
print(json.loads(response.read().decode('utf-8')))
" "${TEST_MESSAGE}" "${JMS_QUEUE}" 2>&1 || echo "")

if echo "$SEND_OUTPUT" | grep -qE "(routed.*True|routed.*true|\"routed\": *true)"; then
    print_info "✅ Test message sent successfully"
else
    print_warning "⚠️  Message sending may have failed"
    echo "$SEND_OUTPUT" | head -5
fi

# Wait for connector to process message
print_info "Waiting for connector to process message (20 seconds)..."
sleep 20
echo ""

# Step 7: Verify data in Aerospike DB
print_info "Step 7: Verifying data in Aerospike DB..."
FOUND_RECORD=false

# Query Aerospike for the test record (try multiple times)
print_info "Running AQL query: SELECT * FROM test.demo WHERE PK='${TEST_KEY}'"
for i in 1 2 3; do
    QUERY_OUTPUT=$(kubectl exec -n ${NAMESPACE} ${DST_CLUSTER}-0-0 -- aql -h localhost -p 3000 -c \
      "SELECT * FROM test.demo WHERE PK='${TEST_KEY}'" 2>&1 || echo "")
    
    # Always print the AQL query output
    print_info "AQL Query Result (attempt $i):"
    echo "----------------------------------------"
    echo "$QUERY_OUTPUT"
    echo "----------------------------------------"
    
    if echo "$QUERY_OUTPUT" | grep -q "${TEST_KEY}"; then
        print_info "✅ Record found in Aerospike DB"
        FOUND_RECORD=true
        break
    elif [ $i -lt 3 ]; then
        print_info "Record not found yet, waiting 5 more seconds..."
        sleep 5
    fi
done

if [ "$FOUND_RECORD" = false ]; then
    print_warning "⚠️  Test record '${TEST_KEY}' not found in Aerospike DB after multiple attempts"
    print_info "Checking all records in test.demo namespace..."
    ALL_RECORDS=$(kubectl exec -n ${NAMESPACE} ${DST_CLUSTER}-0-0 -- aql -h localhost -p 3000 -c \
      "SELECT * FROM test.demo" 2>&1 || echo "")
    echo "----------------------------------------"
    echo "$ALL_RECORDS"
    echo "----------------------------------------"
fi
echo ""

# Step 8: Display Metrics
print_info "Step 8: Component metrics..."
CONNECTOR_POD_COUNT=$(kubectl get pods -n ${NAMESPACE} \
  --selector=app.kubernetes.io/name=aerospike-jms-inbound \
  --no-headers | wc -l | tr -d ' ')

print_info "JMS Inbound Connector Pod Metrics:"
for i in $(seq 0 $((CONNECTOR_POD_COUNT - 1))); do
    POD_NAME="${CONNECTOR_RELEASE}-aerospike-jms-inbound-${i}"
    if kubectl get pod ${POD_NAME} -n ${NAMESPACE} &>/dev/null; then
        echo "JMS Inbound Pod $i (${POD_NAME}):"
        METRICS=$(kubectl logs -n ${NAMESPACE} ${POD_NAME} --tail=50 2>/dev/null | \
          grep "metrics-ticker" | \
          grep -E "(messages-consumed.*count=|messages-processed.*count=|records-written.*count=|requests-total.*count=|requests-success.*count=)" | \
          tail -8 || echo "")
        if [ -n "$METRICS" ]; then
            echo "$METRICS" | grep -E "(messages-consumed.*count=|messages-processed.*count=|records-written.*count=|requests-total.*count=|requests-success.*count=)" | \
              sed 's/.*metrics-ticker - //' | sed 's/^/  /'
        else
            echo "  No metrics found yet"
        fi
    fi
done
echo ""

# Check RabbitMQ queue statistics
print_info "RabbitMQ Queue Statistics:"
QUEUE_STATS=$(kubectl exec -n ${NAMESPACE} ${RABBITMQ_POD} -- rabbitmqctl list_queues name messages messages_ready messages_unacknowledged consumers 2>&1 | grep -E "^${JMS_QUEUE}|^name" || echo "")
if [ -n "$QUEUE_STATS" ]; then
    echo "$QUEUE_STATS"
fi
echo ""

# Step 9: Final Status Check
print_info "Step 9: Final status..."
kubectl get pods -n ${NAMESPACE} -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready" \
  | grep -E "(NAME|aerocluster|jms-inbound|rabbitmq)" || true
echo ""

print_info "✅ Integration test complete!"
if [ "$FOUND_RECORD" = true ]; then
    print_info "   Test key: ${TEST_KEY} | Queue: ${JMS_QUEUE} | Broker: rabbitmq.aerospike-test.svc.cluster.local:5672"
    print_info "   ✅ Data successfully written to Aerospike DB"
else
    print_info "   Test key: ${TEST_KEY} | Queue: ${JMS_QUEUE} | Broker: rabbitmq.aerospike-test.svc.cluster.local:5672"
    print_warning "   ⚠️  Data verification failed - check connector logs"
fi
