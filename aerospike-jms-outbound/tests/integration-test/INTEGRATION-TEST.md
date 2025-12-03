# Integration Test: Aerospike DB -> JMS Outbound Connector -> RabbitMQ Broker

This guide walks you through setting up a complete integration test to verify the data flow:
**Aerospike DB → JMS Outbound Connector → RabbitMQ Broker**

## Quick Start

**Automated Test (Recommended):**
```bash
# Run the complete integration test script (sets up environment, runs tests, and displays metrics)
cd tests/integration-test
./run-integration-test.sh
```

The automated test script performs the following:
1. **Deploys components**: RabbitMQ broker, JMS Outbound connector, and Aerospike source cluster
2. **Inserts test data**: Creates a test record with a unique timestamp-based key
3. **Verifies Aerospike record**: Uses AQL SELECT to confirm the record exists in the database
4. **Checks queue statistics**: Verifies messages are present in RabbitMQ queue
5. **Decodes message content**: Extracts payload, decodes base64, and displays formatted JSON
6. **Validates test key**: Confirms the test key is present in the message payload
7. **Displays metrics**: Shows connector metrics (requests-total, requests-success, jms-connections)
8. **Final status**: Displays pod status for all components

**Manual Deployment Order:**
1. RabbitMQ Broker
2. JMS Outbound Connector
3. Aerospike Cluster (source) with XDR pointing to JMS connector

**Manual Quick Test:**
```bash
# After all components are deployed and tools installed:
# Insert test data
TEST_KEY="test-key-$(date +%s)"
kubectl exec -n aerospike-test aerocluster-src-0-0 -- aql -h localhost -p 3000 -c \
  "INSERT INTO test.demo (PK, name, value) VALUES ('${TEST_KEY}', 'Test Record', 100)"

# Verify record in Aerospike DB
kubectl exec -n aerospike-test aerocluster-src-0-0 -- aql -h localhost -p 3000 -c \
  "SELECT * FROM test.demo WHERE PK='${TEST_KEY}'"

# Wait for replication
sleep 10

# Check queue statistics
kubectl exec -n aerospike-test rabbitmq-0 -- rabbitmqctl list_queues name messages messages_ready messages_unacknowledged

# Get and decode message from queue (non-destructive - requeues)
kubectl exec -n aerospike-test rabbitmq-0 -- rabbitmqadmin get queue=aerospike ackmode=ack_requeue_true count=1 | \
  python3 -c "import sys; lines=sys.stdin.read().split('\n'); [print(lines[i+2].split('|')[4].strip()) for i, line in enumerate(lines) if 'payload' in line.lower() and 'routing_key' in line.lower()]" | \
  python3 -c "import sys, base64; print(base64.b64decode(sys.stdin.read().strip()).decode('utf-8', errors='ignore'))" | \
  python3 -c "import sys, re; text=sys.stdin.read(); matches=re.findall(r'\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}', text); print(matches[-1] if matches else text[:500])" | \
  python3 -m json.tool
```

## Architecture

```
┌─────────────────┐         ┌──────────────────────┐         ┌──────────────┐
│  Aerospike DB   │  XDR    │  JMS Outbound        │  JMS    │  RabbitMQ    │
│  (aerocluster-  │ ──────> │  Connector           │ ──────> │  (Port 5672) │
│   src)          │         │  (Port 8080)         │         │              │
└─────────────────┘         └──────────────────────┘         └──────────────┘
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
helm uninstall test-jms-outbound rabbitmq -n aerospike-test 2>&1 | grep -v "not found" || true

# Delete Aerospike clusters
kubectl delete aerospikecluster aerocluster-src -n aerospike-test 2>&1 | grep -v "not found" || true

# Delete direct Kubernetes resources
kubectl delete statefulset rabbitmq -n aerospike-test 2>&1 | grep -v "not found" || true
kubectl delete service rabbitmq rabbitmq-headless -n aerospike-test 2>&1 | grep -v "not found" || true

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
  -l app=rabbitmq \
  -n aerospike-test \
  --timeout=10m

# Wait a bit more for RabbitMQ to fully initialize
sleep 10

# Verify RabbitMQ is running
kubectl get pods -n aerospike-test -l app=rabbitmq
```

**RabbitMQ Configuration:**
- **Image**: `rabbitmq:3.8.7-management`
- **AMQP Port**: `5672`
- **HTTP Management Port**: `15672`
- **Default Credentials**: `guest/guest`
- **Queue**: `aerospike` (auto-created on first message)

### Step 4: Deploy JMS Outbound Connector

```bash
# Deploy JMS Outbound connector
helm install test-jms-outbound ../aerospike-jms-outbound \
  --namespace aerospike-test \
  --values tests/integration-test/jms-outbound-integration-values.yaml \
  --wait --timeout=2m

# Verify connector pods are running
kubectl get pods -n aerospike-test -l app.kubernetes.io/name=aerospike-jms-outbound
```

**Connector Configuration:**
- **Replicas**: 3
- **JMS Factory**: `com.rabbitmq.jms.admin.RMQConnectionFactory`
- **RabbitMQ Host**: `rabbitmq.aerospike-test.svc.cluster.local`
- **RabbitMQ Port**: `5672`
- **Queue Name**: `aerospike`
- **Format**: `flat-json`

### Step 5: Get Connector Pod DNS Names

```bash
# Get connector pod names
CONNECTOR_PODS=$(kubectl get pods -n aerospike-test \
  --selector=app.kubernetes.io/name=aerospike-jms-outbound \
  --no-headers -o custom-columns=":metadata.name" | head -3)

# Display pod DNS names
for pod in $CONNECTOR_PODS; do
  echo "${pod}.test-jms-outbound-aerospike-jms-outbound.aerospike-test.svc.cluster.local:8080"
done
```

### Step 6: Create Source Aerospike Cluster Configuration

Create `aerocluster-src-generated.yaml` with connector pod DNS names:

```yaml
apiVersion: asdb.aerospike.com/v1
kind: AerospikeCluster
metadata:
  name: aerocluster-src
  namespace: aerospike-test
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
        - name: jms
          connector: true
          namespaces:
            - name: test
          node-address-ports:
            - test-jms-outbound-aerospike-jms-outbound-0.test-jms-outbound-aerospike-jms-outbound.aerospike-test.svc.cluster.local:8080
            - test-jms-outbound-aerospike-jms-outbound-1.test-jms-outbound-aerospike-jms-outbound.aerospike-test.svc.cluster.local:8080
            - test-jms-outbound-aerospike-jms-outbound-2.test-jms-outbound-aerospike-jms-outbound.aerospike-test.svc.cluster.local:8080
```

### Step 7: Deploy Source Aerospike Cluster

```bash
# Deploy source cluster
kubectl apply -f tests/integration-test/aerocluster-src-generated.yaml

# Wait for cluster to be ready
kubectl wait --for=condition=ready pod \
  aerocluster-src-0-0 \
  -n aerospike-test --timeout=3m

# Verify cluster is running
kubectl get pods -n aerospike-test -l app=aerospike
```

### Step 8: Install Aerospike Tools

```bash
# Detect architecture
ARCH=$(kubectl exec -n aerospike-test aerocluster-src-0-0 -- uname -m)

# Install tools (adjust package name based on architecture)
if [[ "$ARCH" == *"x86"* ]] || [[ "$ARCH" == *"amd64"* ]]; then
    TOOLS_PKG="aerospike-server-enterprise_8.0.0.8_tools-11.2.2_ubuntu20.04_amd64.tgz"
    DEB_PKG="aerospike-tools_11.2.2-ubuntu20.04_amd64.deb"
else
    TOOLS_PKG="aerospike-server-enterprise_8.0.0.8_tools-11.2.2_ubuntu20.04_aarch64.tgz"
    DEB_PKG="aerospike-tools_11.2.2-ubuntu20.04_arm64.deb"
fi

# Install tools in pod
kubectl exec -n aerospike-test aerocluster-src-0-0 -- bash -c "
cd /tmp && \
apt-get update -qq && \
apt-get install -y -qq wget curl > /dev/null 2>&1 && \
wget -q https://download.aerospike.com/artifacts/aerospike-server-enterprise/8.0.0.8/${TOOLS_PKG} -O tools.tgz && \
tar -xzf tools.tgz > /dev/null 2>&1 && \
apt-get install -y -qq libreadline8 > /dev/null 2>&1 && \
dpkg -i aerospike-server-enterprise_8.0.0.8_tools-11.2.2_ubuntu20.04_*/${DEB_PKG} > /dev/null 2>&1
"
```

### Step 9: Test Data Flow

```bash
# Insert test data
TEST_KEY="test-key-$(date +%s)"
kubectl exec -n aerospike-test aerocluster-src-0-0 -- aql -h localhost -p 3000 -c \
  "INSERT INTO test.demo (PK, name, value) VALUES ('${TEST_KEY}', 'Test Record', 100)"

# Verify record was inserted in Aerospike DB
kubectl exec -n aerospike-test aerocluster-src-0-0 -- aql -h localhost -p 3000 -c \
  "SELECT * FROM test.demo WHERE PK='${TEST_KEY}'"

# Wait for data replication
sleep 10

# Check queue statistics
kubectl exec -n aerospike-test rabbitmq-0 -- rabbitmqctl list_queues name messages messages_ready messages_unacknowledged

# Get message from queue using rabbitmqadmin (peek - non-destructive, requeues)
kubectl exec -n aerospike-test rabbitmq-0 -- rabbitmqadmin get queue=aerospike ackmode=ack_requeue_true count=1

# Get and decode message content (consume - destructive, removes from queue)
# Extract payload, decode base64, extract JSON, and format
kubectl exec -n aerospike-test rabbitmq-0 -- rabbitmqadmin get queue=aerospike ackmode=ack_requeue_false count=1 | \
  python3 -c "
import sys
output = sys.stdin.read()
if 'payload' in output:
    lines = output.split('\n')
    for i, line in enumerate(lines):
        if 'payload' in line.lower() and 'routing_key' in line.lower():
            for j in range(i+2, len(lines)):
                if '|' in lines[j] and lines[j].strip() and not lines[j].strip().startswith('+'):
                    cols = lines[j].split('|')
                    if len(cols) > 4:
                        print(cols[4].strip())
                        break
            break
" | python3 -c "import sys, base64; print(base64.b64decode(sys.stdin.read().strip()).decode('utf-8', errors='ignore'))" | \
  python3 -c "import sys, re; text=sys.stdin.read(); matches=re.findall(r'\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}', text); print(matches[-1] if matches else text[:500])" | \
  python3 -m json.tool
```

## Verification

### Check Connector Metrics

```bash
# View connector logs for metrics
kubectl logs -n aerospike-test test-jms-outbound-aerospike-jms-outbound-0 --tail=50 | \
  grep -E "(messages-sent|messages-failed|requests-total|requests-success)"
```

### Check RabbitMQ Queue Statistics

```bash
# Queue statistics
kubectl exec -n aerospike-test rabbitmq-0 -- rabbitmqctl list_queues name messages messages_ready messages_unacknowledged

# Detailed queue info
kubectl exec -n aerospike-test rabbitmq-0 -- rabbitmqctl list_queues name messages consumers memory
```

### Verify Record in Aerospike DB

```bash
# After inserting a record, verify it exists
TEST_KEY="test-key-$(date +%s)"
kubectl exec -n aerospike-test aerocluster-src-0-0 -- aql -h localhost -p 3000 -c \
  "SELECT * FROM test.demo WHERE PK='${TEST_KEY}'"
```

### Peek Messages (Non-Destructive)

```bash
# Peek at messages without consuming them (requeues message)
kubectl exec -n aerospike-test rabbitmq-0 -- rabbitmqadmin get queue=aerospike ackmode=ack_requeue_true count=1
```

### Consume and Decode Messages (Destructive)

```bash
# Consume messages and decode the payload to see JSON content
kubectl exec -n aerospike-test rabbitmq-0 -- rabbitmqadmin get queue=aerospike ackmode=ack_requeue_false count=1 | \
  python3 -c "
import sys
output = sys.stdin.read()
if 'payload' in output:
    lines = output.split('\n')
    for i, line in enumerate(lines):
        if 'payload' in line.lower() and 'routing_key' in line.lower():
            for j in range(i+2, len(lines)):
                if '|' in lines[j] and lines[j].strip() and not lines[j].strip().startswith('+'):
                    cols = lines[j].split('|')
                    if len(cols) > 4:
                        print(cols[4].strip())
                        break
            break
" | python3 -c "import sys, base64; print(base64.b64decode(sys.stdin.read().strip()).decode('utf-8', errors='ignore'))" | \
  python3 -c "import sys, re; text=sys.stdin.read(); matches=re.findall(r'\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}', text); print(matches[-1] if matches else text[:500])" | \
  python3 -m json.tool
```

## Troubleshooting

### Connector Not Receiving Data

1. **Check connector logs:**
   ```bash
   kubectl logs -n aerospike-test test-jms-outbound-aerospike-jms-outbound-0
   ```

2. **Verify XDR configuration:**
   ```bash
   kubectl exec -n aerospike-test aerocluster-src-0-0 -- asinfo -v "xdr"
   ```

3. **Check connector connectivity:**
   ```bash
   kubectl exec -n aerospike-test aerocluster-src-0-0 -- telnet test-jms-outbound-aerospike-jms-outbound-0.test-jms-outbound-aerospike-jms-outbound.aerospike-test.svc.cluster.local 8080
   ```

### RabbitMQ Connection Issues

1. **Check RabbitMQ logs:**
   ```bash
   kubectl logs -n aerospike-test rabbitmq-0
   ```

2. **Verify RabbitMQ is accessible:**
   ```bash
   kubectl exec -n aerospike-test rabbitmq-0 -- netstat -tlnp | grep 5672
   ```

3. **Test JMS connection:**
   ```bash
   kubectl exec -n aerospike-test rabbitmq-0 -- rabbitmqctl list_queues name messages
   ```

### Messages Not Appearing in Queue

1. **Check connector configuration:**
   ```bash
   kubectl get configmap -n aerospike-test test-jms-outbound-aerospike-jms-outbound -o yaml
   ```

2. **Verify queue name matches:**
   - Connector config: `routing.destination: aerospike`
   - RabbitMQ queue: `aerospike`

3. **Check connector metrics:**
   ```bash
   kubectl logs -n aerospike-test test-jms-outbound-aerospike-jms-outbound-0 | \
     grep -E "(messages-sent|messages-failed)"
   ```

## Cleanup

```bash
# Uninstall Helm releases
helm uninstall test-jms-outbound -n aerospike-test
helm uninstall rabbitmq -n aerospike-test 2>/dev/null || true

# Delete Kubernetes resources
kubectl delete statefulset rabbitmq -n aerospike-test
kubectl delete service rabbitmq rabbitmq-headless -n aerospike-test

# Delete Aerospike cluster
kubectl delete aerospikecluster aerocluster-src -n aerospike-test

# Wait for cleanup
sleep 10
```

## Files Reference

- `rabbitmq-deployment.yaml` - RabbitMQ broker deployment (RabbitMQ 3.8.7)
- `jms-outbound-integration-values.yaml` - JMS Outbound connector configuration
- `aerocluster-src.yaml` - Source Aerospike cluster template
- `aerocluster-src-generated.yaml` - Generated source cluster with connector pod DNS (created by script)
- `run-integration-test.sh` - Automated integration test script

## Additional Resources

- [RabbitMQ Documentation](https://www.rabbitmq.com/documentation.html)
- [RabbitMQ JMS Plugin](https://www.rabbitmq.com/jms-client.html)
- [Aerospike JMS Outbound Connector Documentation](https://docs.aerospike.com/connect/jms/from-asdb)
- [Aerospike Kubernetes Operator Documentation](https://docs.aerospike.com/kubernetes-operator)
