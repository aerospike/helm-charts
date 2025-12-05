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
RABBITMQ_RELEASE="rabbitmq-jms-inbound"
CONNECTOR_RELEASE="test-jms-inbound"
DST_CLUSTER="aerocluster-jms-inbound-dst"
JMS_QUEUE="aerospike"
CONTEXT="kind-jms-inbound-test-cluster"  # Explicit context for parallel execution safety

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

print_info "🚀 Setting up JMS Inbound Integration Test Environment"
print_info "======================================================"
echo ""

# Verify existing files exist
if [ ! -f "$SCRIPT_DIR/rabbitmq-deployment.yaml" ]; then
    print_error "rabbitmq-deployment.yaml not found in $SCRIPT_DIR"
    echo "INTEGRATION_TEST_FAILED"
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/jms-inbound-integration-values.yaml" ]; then
    print_error "jms-inbound-integration-values.yaml not found in $SCRIPT_DIR"
    echo "INTEGRATION_TEST_FAILED"
    exit 1
fi

# Check if TLS secrets are needed for JMS Inbound
CONNECTOR_VALUES_FILE="$SCRIPT_DIR/jms-inbound-integration-values.yaml"
if [ -f "$CONNECTOR_VALUES_FILE" ]; then
    if grep -q "connectorSecrets:" "$CONNECTOR_VALUES_FILE" && ! grep -q "^#.*connectorSecrets:" "$CONNECTOR_VALUES_FILE"; then
        if grep -q "tls-certs-jms-inbound" "$CONNECTOR_VALUES_FILE"; then
            print_info "Checking for TLS secret 'tls-certs-jms-inbound'..."
            if ! kubectl get secret tls-certs-jms-inbound -n "${NAMESPACE}" &>/dev/null; then
                print_warning "TLS secret 'tls-certs-jms-inbound' not found in namespace ${NAMESPACE}"
                CHART_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
                TLS_CERTS_DIR="${CHART_ROOT}/examples/tls/tls-certs"
                if [ -d "$TLS_CERTS_DIR" ]; then
                    print_info "Creating TLS secret from ${TLS_CERTS_DIR}..."
                    if kubectl create secret generic tls-certs-jms-inbound --from-file="${TLS_CERTS_DIR}" -n "${NAMESPACE}" 2>/dev/null; then
                        print_info "✅ TLS secret created successfully"
                    else
                        print_warning "Failed to create TLS secret. Continuing anyway..."
                    fi
                else
                    print_warning "TLS secret 'tls-certs-jms-inbound' is required but ${TLS_CERTS_DIR} not found."
                    print_info "  kubectl create secret generic tls-certs-jms-inbound --from-file=<path-to-tls-certs> -n ${NAMESPACE}"
                fi
            else
                print_info "✅ TLS secret 'tls-certs-jms-inbound' already exists"
            fi
            echo ""
        fi
    fi
fi

# Check for existing deployments and clean up if needed
print_info "Checking for existing deployments..."
EXISTING_HELM=$(helm list -n "${NAMESPACE}" --short 2>/dev/null | grep -E "(${CONNECTOR_RELEASE}|${RABBITMQ_RELEASE})" || true)
EXISTING_CLUSTERS=$(kubectl get aerospikecluster -n "${NAMESPACE}" -o name 2>/dev/null | grep -E "${DST_CLUSTER}" || true)

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
    kubectl delete statefulset rabbitmq-jms-inbound -n "${NAMESPACE}" 2>/dev/null || true
    kubectl delete service rabbitmq-jms-inbound rabbitmq-jms-inbound-headless -n "${NAMESPACE}" 2>/dev/null || true
    
    if kubectl get aerospikecluster "${DST_CLUSTER}" -n "${NAMESPACE}" &>/dev/null; then
        print_info "Deleting existing ${DST_CLUSTER}..."
        kubectl delete aerospikecluster "${DST_CLUSTER}" -n "${NAMESPACE}" 2>/dev/null || true
    fi
    
    print_info "Waiting for cleanup to complete (10 seconds)..."
    sleep 10
    echo ""
fi

# Step 1: Deploy RabbitMQ broker
print_info "Step 1: Deploying RabbitMQ broker..."
kubectl apply -f "$SCRIPT_DIR/rabbitmq-deployment.yaml" > /dev/null 2>&1
kubectl wait --for=condition=ready pod -l app=rabbitmq-jms-inbound -n "${NAMESPACE}" --timeout=10m > /dev/null 2>&1 || print_warning "RabbitMQ pods may still be starting"
sleep 10
print_info "✅ RabbitMQ broker deployed"
echo ""

# Step 2: Deploy Aerospike destination cluster
print_info "Step 2: Deploying Aerospike destination cluster..."
kubectl apply -f "$SCRIPT_DIR/aerocluster-dst.yaml" > /dev/null 2>&1
timeout=120
elapsed=0
while [ $elapsed -lt $timeout ]; do
    if kubectl get pod "${DST_CLUSTER}-0-0" -n "${NAMESPACE}" &>/dev/null; then
        break
    fi
    sleep 2
    elapsed=$((elapsed + 2))
done
kubectl wait --for=condition=ready pod "${DST_CLUSTER}-0-0" -n "${NAMESPACE}" --timeout=3m > /dev/null 2>&1
print_info "✅ Destination cluster ready"
echo ""

# Step 3: Deploy JMS Inbound connector
print_info "Step 3: Deploying JMS Inbound connector..."
helm install "${CONNECTOR_RELEASE}" "$SCRIPT_DIR/../.." -n "${NAMESPACE}" -f "$SCRIPT_DIR/jms-inbound-integration-values.yaml" --wait --timeout=2m > /dev/null 2>&1
print_info "✅ JMS Inbound connector deployed"
echo ""

# Step 4: Install Aerospike tools
print_info "Step 4: Installing Aerospike tools..."
ARCH=$(kubectl exec -n "${NAMESPACE}" "${DST_CLUSTER}-0-0" -- uname -m 2>/dev/null || echo "aarch64")
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
#LOCAL_TOOLS_PATH="/Users/vbayana/aerospike-connect-resources/aerospike-server"
LOCAL_TOOLS_FILE=""
if [ -f "${LOCAL_TOOLS_PATH}/${TOOLS_PKG}" ]; then
    LOCAL_TOOLS_FILE="${LOCAL_TOOLS_PATH}/${TOOLS_PKG}"
fi

if [ -n "$LOCAL_TOOLS_FILE" ] && [ -f "$LOCAL_TOOLS_FILE" ]; then
    print_info "Found local tools file: $LOCAL_TOOLS_FILE"
    print_info "Copying tools file into pod..."
    kubectl cp "${LOCAL_TOOLS_FILE}" "${NAMESPACE}/${DST_CLUSTER}-0-0:/tmp/tools.tgz" || {
        print_warning "Failed to copy local tools file, falling back to download"
        LOCAL_TOOLS_FILE=""
    }
fi

if [ -n "$LOCAL_TOOLS_FILE" ] && [ -f "$LOCAL_TOOLS_FILE" ]; then
    # Install from copied local file
    kubectl exec -n "${NAMESPACE}" "${DST_CLUSTER}-0-0" -- bash -c "
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
    kubectl exec -n "${NAMESPACE}" "${DST_CLUSTER}-0-0" -- bash -c "
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
RABBITMQ_POD=$(kubectl get pods -n "${NAMESPACE}" -l app=rabbitmq-jms-inbound -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$RABBITMQ_POD" ]; then
    print_error "RabbitMQ pod not found!"
    echo "INTEGRATION_TEST_FAILED"
    exit 1
fi

# Generate test message with timestamp
TEST_KEY="test-key-$(date +%s)"
TEST_MESSAGE="{\"key\":\"${TEST_KEY}\",\"name\":\"Test Record\",\"value\":100}"

print_info "Sending test message to RabbitMQ queue '${JMS_QUEUE}'..."
print_info "Test key: ${TEST_KEY}"

print_info "Sending test message via JMS client (TextMessage for JSON format)..."
JMS_SENDER_POD="jms-sender-$(date +%s)"

kubectl run "${JMS_SENDER_POD}" \
    --image=eclipse-temurin:11-jdk \
    --restart=Never \
    --namespace="${NAMESPACE}" \
    --command -- sleep 300 > /dev/null 2>&1 || true

print_info "Waiting for pod to be ready..."
kubectl wait --for=condition=ready "pod/${JMS_SENDER_POD}" -n "${NAMESPACE}" --timeout=60s > /dev/null 2>&1 || {
    print_error "Pod ${JMS_SENDER_POD} failed to start"
    kubectl describe "pod/${JMS_SENDER_POD}" -n "${NAMESPACE}" | tail -20
    echo "INTEGRATION_TEST_FAILED"
    exit 1
}

# Base64 encode the message for safe passing through shell
TEST_MESSAGE_B64=$(echo -n "${TEST_MESSAGE}" | base64 | tr -d '\n')
# Write base64 string to a file first, then copy it into the pod to avoid shell interpretation issues
echo -n "${TEST_MESSAGE_B64}" > /tmp/jms_msg_b64_$$.txt

SEND_OUTPUT=$(kubectl cp "/tmp/jms_msg_b64_$$.txt" "${NAMESPACE}/${JMS_SENDER_POD}:/tmp/msg_b64.txt" > /dev/null 2>&1 && \
kubectl exec -n "${NAMESPACE}" "${JMS_SENDER_POD}" -- sh -c "
        echo 'Installing dependencies...' >&2
        apt-get update -qq > /dev/null 2>&1 && apt-get install -y -qq wget > /dev/null 2>&1
        echo 'Downloading JMS libraries...' >&2
        wget -q https://repo1.maven.org/maven2/javax/jms/javax.jms-api/2.0.1/javax.jms-api-2.0.1.jar -O /tmp/jms-api.jar
        wget -q https://repo1.maven.org/maven2/org/slf4j/slf4j-api/1.7.36/slf4j-api-1.7.36.jar -O /tmp/slf4j-api.jar
        wget -q https://repo1.maven.org/maven2/org/slf4j/slf4j-simple/1.7.36/slf4j-simple-1.7.36.jar -O /tmp/slf4j-simple.jar
        wget -q https://repo1.maven.org/maven2/com/rabbitmq/jms/rabbitmq-jms/2.3.0/rabbitmq-jms-2.3.0.jar -O /tmp/rabbitmq-jms.jar
        wget -q https://repo1.maven.org/maven2/com/rabbitmq/amqp-client/5.20.0/amqp-client-5.20.0.jar -O /tmp/amqp-client.jar
        echo 'Creating Java program...' >&2
        cat > /tmp/Send.java << 'EOFSEND'
import javax.jms.*;
import com.rabbitmq.jms.admin.RMQConnectionFactory;
import java.util.Base64;
import java.nio.file.Files;
import java.nio.file.Paths;
public class Send {
    public static void main(String[] a) throws Exception {
        if (a.length < 5) {
            System.err.println(\"Usage: Send <host> <port> <username> <password> <queue> [base64file]\");
            System.exit(1);
        }
        RMQConnectionFactory cf = new RMQConnectionFactory();
        cf.setHost(a[0]); 
        cf.setPort(Integer.parseInt(a[1]));
        cf.setUsername(a[2]); 
        cf.setPassword(a[3]);
        Connection c = cf.createConnection(); 
        c.start();
        Session s = c.createSession(false, Session.AUTO_ACKNOWLEDGE);
        Queue queue = s.createQueue(a[4]);
        MessageProducer p = s.createProducer(queue);
        try {
            String jsonMessage;
            if (a.length >= 6 && a[5] != null && !a[5].isEmpty()) {
                // Read base64 from file if provided
                String base64Str = new String(Files.readAllBytes(Paths.get(a[5]))).trim();
                jsonMessage = new String(Base64.getDecoder().decode(base64Str));
            } else {
                // Fallback: try to read from /tmp/msg_b64.txt
                String base64Str = new String(Files.readAllBytes(Paths.get(\"/tmp/msg_b64.txt\"))).trim();
                jsonMessage = new String(Base64.getDecoder().decode(base64Str));
            }
            TextMessage msg = s.createTextMessage(jsonMessage);
            p.send(msg);
            System.out.println(\"SUCCESS\");
        } catch (Exception e) {
            System.err.println(\"ERROR: Failed to send message\");
            e.printStackTrace();
            System.exit(1);
        } finally {
            p.close(); 
            s.close(); 
            c.close();
        }
    }
}
EOFSEND
        echo 'Compiling...' >&2
        javac -cp /tmp/jms-api.jar:/tmp/slf4j-api.jar:/tmp/rabbitmq-jms.jar:/tmp/amqp-client.jar /tmp/Send.java 2>&1
        echo 'Running JMS sender...' >&2
        java -cp /tmp:/tmp/jms-api.jar:/tmp/slf4j-api.jar:/tmp/slf4j-simple.jar:/tmp/rabbitmq-jms.jar:/tmp/amqp-client.jar Send \
            '${RABBITMQ_RELEASE}.${NAMESPACE}.svc.cluster.local' 5672 guest guest '${JMS_QUEUE}' /tmp/msg_b64.txt 2>&1
" 2>&1 || echo "")

# Clean up local temp file
rm -f "/tmp/jms_msg_b64_$$.txt" 2>/dev/null || true

kubectl delete "pod/${JMS_SENDER_POD}" -n "${NAMESPACE}" > /dev/null 2>&1 || true

if echo "$SEND_OUTPUT" | grep -q "SUCCESS"; then
    print_info "✅ Test message sent successfully via JMS TextMessage"
else
    print_error "❌ Failed to send message via JMS client"
    echo "$SEND_OUTPUT" | head -30
    print_error "Please check the error above and ensure JMS libraries are available"
    echo "INTEGRATION_TEST_FAILED"
    exit 1
fi

# Wait for connector to process message
print_info "Waiting for connector to process message (20 seconds)..."
sleep 20
echo ""

# Step 7: Verify data in Aerospike DB
print_info "Step 7: Verifying data in Aerospike DB..."
FOUND_RECORD=false

print_info "Running AQL query: SELECT * FROM test WHERE PK='${TEST_KEY}'"
for i in 1 2 3; do
    QUERY_OUTPUT=$(kubectl exec -n "${NAMESPACE}" "${DST_CLUSTER}-0-0" -- aql -h localhost -p 3050 -c \
      "SELECT * FROM test WHERE PK='${TEST_KEY}'" 2>&1 || echo "")
    
    print_info "AQL Query Result (attempt $i):"
    if echo "$QUERY_OUTPUT" | grep -q "AEROSPIKE_ERR_RECORD_NOT_FOUND"; then
        if [ $i -lt 3 ]; then
            print_info "Record not found yet, waiting 5 more seconds..."
            sleep 5
        else
            print_error "❌ Test FAILED: Data not found in Aerospike DB"
            echo "$QUERY_OUTPUT"
            echo ""
            print_warning "This may indicate:"
            print_warning "  - JMS Inbound connector is not processing messages correctly"
            print_warning "  - Message format mismatch"
            print_warning "  - Network connectivity issues"
            echo ""
            echo "INTEGRATION_TEST_FAILED"
            exit 1
        fi
    elif echo "$QUERY_OUTPUT" | grep -qE "(\+---|row in set)"; then
        print_info "✅ Test PASSED: Data found in Aerospike DB!"
        echo "$QUERY_OUTPUT"
        echo ""
        FOUND_RECORD=true
        break
    elif [ $i -lt 3 ]; then
        print_info "Record not found yet, waiting 5 more seconds..."
        sleep 5
    fi
done

if [ "$FOUND_RECORD" = false ]; then
    print_error "❌ Test FAILED: Unable to verify data in Aerospike DB"
    print_info "Checking all records in test namespace..."
    ALL_RECORDS=$(kubectl exec -n "${NAMESPACE}" "${DST_CLUSTER}-0-0" -- aql -h localhost -p 3050 -c \
      "SELECT * FROM test" 2>&1 || echo "")
    echo "----------------------------------------"
    echo "$ALL_RECORDS"
    echo "----------------------------------------"
    echo ""
    echo "INTEGRATION_TEST_FAILED"
    exit 1
fi
echo ""

# Step 8: Display Metrics
print_info "Step 8: Component metrics..."

print_info "JMS Inbound Connector Pod Metrics:"
POD_INDEX=0
while IFS= read -r POD_NAME; do
    if [ -n "$POD_NAME" ]; then
        echo "JMS Inbound Pod ${POD_INDEX} (${POD_NAME}):"
        METRICS=$(kubectl logs -n "${NAMESPACE}" "${POD_NAME}" --tail=50 2>/dev/null | \
          grep "metrics-ticker" | \
          grep -E "(queue:aerospike-success.*count=|queue:aerospike-errors-parsing.*count=|queue:aerospike-errors-conversion.*count=|queue:aerospike-errors-aerospike.*count=|queue:aerospike-consumers-active.*count=|jms-connections.*count=|jms-connections-active.*count=)" | \
          tail -10 || echo "")
        if [ -n "$METRICS" ]; then
            echo "$METRICS" | grep -E "(queue:aerospike-success.*count=|queue:aerospike-errors-parsing.*count=|queue:aerospike-errors-conversion.*count=|queue:aerospike-errors-aerospike.*count=|queue:aerospike-consumers-active.*count=|jms-connections.*count=|jms-connections-active.*count=)" | \
              sed 's/.*metrics-ticker - //' | sed 's/^/  /'
        else
            echo "  No metrics found yet"
        fi
        POD_INDEX=$((POD_INDEX + 1))
    fi
done < <(kubectl get pods -n "${NAMESPACE}" \
  --selector=app.kubernetes.io/name=aerospike-jms-inbound \
  --no-headers -o custom-columns=":metadata.name" 2>/dev/null || echo "")
echo ""

# Check RabbitMQ queue statistics
print_info "RabbitMQ Queue Statistics:"
QUEUE_STATS=$(kubectl exec -n "${NAMESPACE}" "${RABBITMQ_POD}" -- rabbitmqctl list_queues name messages messages_ready messages_unacknowledged consumers 2>&1 | grep -E "^${JMS_QUEUE}|^name" || echo "")
if [ -n "$QUEUE_STATS" ]; then
    echo "$QUEUE_STATS"
fi
echo ""

# Step 9: Final Status Check
print_info "Step 9: Final status..."
kubectl get pods -n "${NAMESPACE}" -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready" \
  | grep -E "(NAME|aerocluster|jms-inbound|rabbitmq)" || true
echo ""

print_info "✅ Integration test complete!"
if [ "$FOUND_RECORD" = true ]; then
    print_info "   Test key: ${TEST_KEY} | Queue: ${JMS_QUEUE} | Broker: rabbitmq-jms-inbound.aerospike-test.svc.cluster.local:5672"
    print_info "   ✅ Data successfully written to Aerospike DB"
    echo ""
    echo "INTEGRATION_TEST_PASSED"
else
    print_info "   Test key: ${TEST_KEY} | Queue: ${JMS_QUEUE} | Broker: rabbitmq-jms-inbound.aerospike-test.svc.cluster.local:5672"
    print_warning "   ⚠️  Data verification failed - check connector logs"
    echo ""
    echo "INTEGRATION_TEST_FAILED"
    exit 1
fi
