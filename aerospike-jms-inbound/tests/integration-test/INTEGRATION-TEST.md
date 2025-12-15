# Integration Test: RabbitMQ Broker -> JMS Inbound Connector -> Aerospike DB

This guide walks you through setting up a complete integration test to verify the data flow:
**RabbitMQ Broker → JMS Inbound Connector → Aerospike DB**

## Quick Start

**Automated Test (Recommended):**
```bash
# Run the complete integration test script (sets up environment, runs tests, and displays metrics)
cd tests/integration-test
./run-integration-test.sh
```

The automated test script performs the following:
1. **Deploys components**: RabbitMQ broker, Aerospike destination cluster, and JMS Inbound connector
2. **Sends test message**: Publishes a test message with a unique timestamp-based key to RabbitMQ queue
3. **Verifies Aerospike record**: Uses AQL SELECT to confirm the record exists in the database
4. **Displays metrics**: Shows connector metrics (messages-consumed, records-written, requests-total)
5. **Final status**: Displays pod status for all components

**Manual Deployment Order:**
1. RabbitMQ Broker
2. Aerospike Cluster (destination)
3. JMS Inbound Connector

**Manual Quick Test:**
```bash
# After all components are deployed:
# Note: The integration test uses JMS TextMessage for proper message format
# See run-integration-test.sh for the complete JMS client implementation
TEST_KEY="test-key-$(date +%s)"
TEST_MESSAGE="{\"key\":\"${TEST_KEY}\",\"name\":\"Test Record\",\"value\":100}"

# Wait for processing
sleep 20

# Verify data in Aerospike DB (connector writes to null set by default)
kubectl exec -n aerospike-test aerocluster-jms-inbound-dst-0-0 -- aql -h localhost -p 3050 -c "SELECT * FROM test WHERE PK='${TEST_KEY}'"
```

## Architecture

```
┌──────────────┐         ┌──────────────────────┐         ┌─────────────────┐
│  RabbitMQ    │  JMS    │  JMS Inbound         │  Write  │  Aerospike DB   │
│  (Port 5672) │ ──────> │  Connector           │ ──────> │  (aerocluster-  │
│              │         │  (Consumes Queue)    │         │   dst)          │
└──────────────┘         └──────────────────────┘         └─────────────────┘
```

## Prerequisites

1. **Kubernetes cluster** (kind cluster already set up)
2. **Aerospike Kubernetes Operator** installed
3. **Helm v3** installed
4. **Aerospike features.conf** secret created in `aerospike-test` namespace
5. **Namespace** `aerospike-test` created

## Step-by-Step Setup

### Step 1: Clean Up Existing Deployments (Optional)

If you have existing deployments, clean them up first:

```bash
# Uninstall Helm releases
helm uninstall test-jms-inbound rabbitmq-jms-inbound -n aerospike-test 2>&1 | grep -v "not found" || true

# Delete Aerospike clusters
kubectl delete aerospikecluster aerocluster-jms-inbound-dst -n aerospike-test 2>&1 | grep -v "not found" || true

# Delete direct Kubernetes resources
kubectl delete statefulset rabbitmq-jms-inbound -n aerospike-test 2>&1 | grep -v "not found" || true
kubectl delete service rabbitmq-jms-inbound rabbitmq-jms-inbound-headless -n aerospike-test 2>&1 | grep -v "not found" || true

# Wait for cleanup
sleep 10
```

### Step 2: Verify Prerequisites

```bash
# Check Aerospike Kubernetes Operator
kubectl get crd aerospikeclusters.asdb.aerospike.com > /dev/null 2>&1 && echo "✅ Operator installed" || echo "❌ Operator not found"

# Check aerospike-secret (create if needed)
kubectl get secret aerospike-secret -n aerospike-test > /dev/null 2>&1 && echo "✅ Secret exists" || echo "❌ Secret not found - create it with features.conf"

# Ensure namespace exists
kubectl get namespace aerospike-test > /dev/null 2>&1 || kubectl create namespace aerospike-test
```

### Step 3: Deploy RabbitMQ Broker

```bash
# Deploy RabbitMQ broker using Kubernetes manifests
kubectl apply -f tests/integration-test/rabbitmq-deployment.yaml

# Wait for RabbitMQ to be ready
kubectl wait --for=condition=ready pod \
  -l app=rabbitmq-jms-inbound \
  -n aerospike-test \
  --timeout=10m

# Wait a bit more for RabbitMQ to fully initialize
sleep 10

# Verify RabbitMQ is running
kubectl get pods -n aerospike-test -l app=rabbitmq-jms-inbound
```

**RabbitMQ Configuration:**
- **Image**: `rabbitmq:3.8.7-management`
- **AMQP Port**: `5672`
- **HTTP Management Port**: `15672`
- **Default Credentials**: `guest/guest`
- **Queue**: `aerospike` (auto-created on first message)

### Step 4: Deploy Aerospike Destination Cluster

```bash
# Deploy Aerospike destination cluster
kubectl apply -f tests/integration-test/aerocluster-dst.yaml

# Wait for cluster to be ready
kubectl wait --for=condition=ready pod \
  aerocluster-jms-inbound-dst-0-0 \
  -n aerospike-test --timeout=3m

# Verify cluster is running
kubectl get pods -n aerospike-test -l app=aerospike
```

### Step 5: Deploy JMS Inbound Connector

```bash
# Deploy JMS Inbound connector
helm install test-jms-inbound ../aerospike-jms-inbound \
  --namespace aerospike-test \
  --values tests/integration-test/jms-inbound-integration-values.yaml \
  --wait --timeout=2m

# Verify connector pods are running
kubectl get pods -n aerospike-test -l app.kubernetes.io/name=aerospike-jms-inbound
```

**Connector Configuration:**
- **Replicas**: 1
- **JMS Factory**: `com.rabbitmq.jms.admin.RMQConnectionFactory`
- **RabbitMQ Host**: `rabbitmq-jms-inbound.aerospike-test.svc.cluster.local`
- **RabbitMQ Port**: `5672`
- **Queue Name**: `aerospike`
- **Aerospike Cluster**: `aerocluster-jms-inbound-dst.aerospike-test.svc.cluster.local:3050`
- **Namespace**: `test`
- **Set**: null set (default)
- **Format**: `json`

### Step 6: Install Aerospike Tools

```bash
# Detect architecture
ARCH=$(kubectl exec -n aerospike-test aerocluster-jms-inbound-dst-0-0 -- uname -m)

# Install tools (adjust package name based on architecture)
if [[ "$ARCH" == *"x86"* ]] || [[ "$ARCH" == *"amd64"* ]]; then
    TOOLS_PKG="aerospike-server-enterprise_8.0.0.8_tools-11.2.2_ubuntu20.04_x86_64.tgz"
    DEB_PKG="aerospike-tools_11.2.2-ubuntu20.04_amd64.deb"
else
    TOOLS_PKG="aerospike-server-enterprise_8.0.0.8_tools-11.2.2_ubuntu20.04_aarch64.tgz"
    DEB_PKG="aerospike-tools_11.2.2-ubuntu20.04_arm64.deb"
fi

# Install tools in pod
kubectl exec -n aerospike-test aerocluster-jms-inbound-dst-0-0 -- bash -c "
cd /tmp && \
apt-get update -qq && \
apt-get install -y -qq wget curl > /dev/null 2>&1 && \
wget -q https://download.aerospike.com/artifacts/aerospike-server-enterprise/8.0.0.8/${TOOLS_PKG} -O tools.tgz && \
tar -xzf tools.tgz > /dev/null 2>&1 && \
(apt-get install -y -qq libreadline8 > /dev/null 2>&1 || apt-get install -y -qq libreadline9 > /dev/null 2>&1 || true) && \
dpkg -i aerospike-server-enterprise_8.0.0.8_tools-11.2.2_ubuntu20.04_*/${DEB_PKG} > /dev/null 2>&1
"
```

### Step 7: Test Data Flow

**Note:** The integration test script uses a Java-based JMS client to send proper JMS TextMessage objects. For manual testing, you can use the script's approach or send messages via a JMS client.

```bash
# Generate test message
TEST_KEY="test-key-$(date +%s)"
TEST_MESSAGE="{\"key\":\"${TEST_KEY}\",\"name\":\"Test Record\",\"value\":100}"

# Wait for connector to process (if using automated script)
sleep 20

# Verify data in Aerospike DB (connector writes to null set by default)
kubectl exec -n aerospike-test aerocluster-jms-inbound-dst-0-0 -- aql -h localhost -p 3050 -c "SELECT * FROM test WHERE PK='${TEST_KEY}'"
```

For sending messages manually, see `run-integration-test.sh` for the complete JMS client implementation using TextMessage format.

## Verification

### Check Connector Metrics

```bash
# View connector logs for metrics
kubectl logs -n aerospike-test test-jms-inbound-aerospike-jms-inbound-0 --tail=50 | \
  grep -E "(messages-consumed|messages-processed|records-written|requests-total|requests-success)"
```

### Check RabbitMQ Queue Statistics

```bash
# Queue statistics
kubectl exec -n aerospike-test rabbitmq-jms-inbound-0 -- rabbitmqctl list_queues name messages messages_ready messages_unacknowledged consumers

# Detailed queue info
kubectl exec -n aerospike-test rabbitmq-jms-inbound-0 -- rabbitmqctl list_queues name messages consumers memory
```

### Query Aerospike Records

```bash
# Query all records in test namespace (null set)
kubectl exec -n aerospike-test aerocluster-jms-inbound-dst-0-0 -- aql -h localhost -p 3050 -c "SELECT * FROM test"

# Query specific record
kubectl exec -n aerospike-test aerocluster-jms-inbound-dst-0-0 -- aql -h localhost -p 3050 -c "SELECT * FROM test WHERE PK='test-key-1234567890'"
```

### Send More Test Messages

**Note:** For proper JMS message format, use the JMS client approach from `run-integration-test.sh`. The script uses TextMessage format which is required for JSON parsing.

```bash
# Wait for processing after sending messages
sleep 20

# Verify all records (connector writes to null set by default)
kubectl exec -n aerospike-test aerocluster-jms-inbound-dst-0-0 -- aql -h localhost -p 3050 -c "SELECT * FROM test"
```

## Troubleshooting

### Connector Not Consuming Messages

1. **Check connector logs:**
   ```bash
   kubectl logs -n aerospike-test test-jms-inbound-aerospike-jms-inbound-0
   ```

2. **Verify connector configuration:**
   ```bash
   kubectl get configmap -n aerospike-test test-jms-inbound-aerospike-jms-inbound -o yaml
   ```

3. **Check RabbitMQ connectivity:**
   ```bash
   kubectl exec -n aerospike-test test-jms-inbound-aerospike-jms-inbound-0 -- nc -zv rabbitmq-jms-inbound.aerospike-test.svc.cluster.local 5672
   ```

### Messages Not Appearing in Aerospike

1. **Check connector logs for errors:**
   ```bash
   kubectl logs -n aerospike-test test-jms-inbound-aerospike-jms-inbound-0 | grep -i error
   ```

2. **Verify Aerospike connectivity:**
   ```bash
   kubectl exec -n aerospike-test test-jms-inbound-aerospike-jms-inbound-0 -- telnet aerocluster-jms-inbound-dst.aerospike-test.svc.cluster.local 3000
   ```

3. **Check message format:**
   - Messages must be valid JSON
   - Must be sent as JMS TextMessage (not native RabbitMQ messages)
   - Must include `key` field for record key
   - Other fields become bins

4. **Verify namespace and set:**
   - Connector writes to namespace: `test`
   - Set defaults to null set (no set name specified)

### RabbitMQ Connection Issues

1. **Check RabbitMQ logs:**
   ```bash
   kubectl logs -n aerospike-test rabbitmq-jms-inbound-0
   ```

2. **Verify RabbitMQ is accessible:**
   ```bash
   kubectl exec -n aerospike-test rabbitmq-jms-inbound-0 -- netstat -tlnp | grep 5672
   ```

3. **Test JMS connection:**
   ```bash
   kubectl exec -n aerospike-test rabbitmq-jms-inbound-0 -- rabbitmqctl list_queues name messages
   ```

## Cleanup

```bash
# Uninstall Helm releases
helm uninstall test-jms-inbound -n aerospike-test
helm uninstall rabbitmq-jms-inbound -n aerospike-test 2>/dev/null || true

# Delete Kubernetes resources
kubectl delete statefulset rabbitmq-jms-inbound -n aerospike-test
kubectl delete service rabbitmq-jms-inbound rabbitmq-jms-inbound-headless -n aerospike-test

# Delete Aerospike cluster
kubectl delete aerospikecluster aerocluster-jms-inbound-dst -n aerospike-test

# Wait for cleanup
sleep 10
```

## Files Reference

- `rabbitmq-deployment.yaml` - RabbitMQ broker deployment (RabbitMQ 3.8.7)
- `jms-inbound-integration-values.yaml` - JMS Inbound connector configuration
- `aerocluster-dst.yaml` - Destination Aerospike cluster
- `run-integration-test.sh` - Automated integration test script

## Additional Resources

- [RabbitMQ Documentation](https://www.rabbitmq.com/documentation.html)
- [RabbitMQ JMS Plugin](https://www.rabbitmq.com/jms-client.html)
- [Aerospike JMS Inbound Connector Documentation](https://docs.aerospike.com/connect/jms/to-asdb)
- [Aerospike Kubernetes Operator Documentation](https://docs.aerospike.com/kubernetes-operator)
