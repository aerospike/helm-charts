# Integration Test: Aerospike DB -> Kafka Outbound Connector -> Kafka Broker

This guide walks you through setting up a complete integration test to verify the data flow:
**Aerospike DB → Kafka Outbound Connector → Kafka Broker**

## Quick Start

**Automated Test (Recommended):**
```bash
# Run the complete integration test script (sets up environment, runs tests, and displays metrics)
cd integration-test
./run-integration-test.sh
```

**Manual Deployment Order:**
1. Kafka Broker
2. Kafka Outbound Connector
3. Aerospike Cluster (source) with XDR pointing to Kafka connector

**Manual Quick Test:**
```bash
# After all components are deployed and tools installed:
# Insert test data
kubectl exec -n aerospike-test aerocluster-src-0-0 -- aql -h localhost -p 3020 -c "INSERT INTO test.demo (PK, name, value) VALUES ('test-key', 'Test', 100)"

# Wait for replication
sleep 10

# Verify data in Kafka
kubectl exec -n aerospike-test kafka-0 -- kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic aerospike --from-beginning --max-messages 10
```

## Architecture

```
┌─────────────────┐         ┌──────────────────────┐         ┌──────────────┐
│  Aerospike DB   │  XDR    │  Kafka Outbound      │  Kafka  │  Kafka       │
│  (aerocluster-  │ ──────> │  Connector           │ ──────> │  Broker      │
│   src)          │         │  (Port 8080)         │         │  (Port 9092) │
└─────────────────┘         └──────────────────────┘         └──────────────┘
```

## Prerequisites

1. **Kubernetes cluster** (kind cluster already set up)
2. **Aerospike Kubernetes Operator** installed
3. **Helm v3** installed
4. **Aerospike features.conf** secret created in `aerospike-test` namespace
5. **Namespace** `aerospike-test` created
6. **Bitnami Helm repository** (will be added automatically by script)

## Step-by-Step Setup

### Step 1: Clean Up Existing Deployments (Optional)

If you have existing deployments, clean them up first:

```bash
# Uninstall Helm releases
helm uninstall test-kafka-outbound kafka -n aerospike-test 2>&1 | grep -v "not found" || true

# Delete Aerospike clusters
kubectl delete aerospikecluster aerocluster-src -n aerospike-test 2>&1 | grep -v "not found" || true

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

### Step 3: Deploy Kafka Broker

```bash
# Add Bitnami Helm repository (if not already added)
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Deploy Kafka broker
helm install kafka bitnami/kafka \
  --namespace aerospike-test \
  --values integration-test/kafka-values.yaml \
  --wait --timeout=5m

# Verify Kafka is running
kubectl get pods -n aerospike-test -l app.kubernetes.io/name=kafka
```

### Step 4: Deploy Kafka Outbound Connector

```bash
# Deploy Kafka Outbound connector
helm install test-kafka-outbound . \
  --namespace aerospike-test \
  --values integration-test/kafka-outbound-integration-values.yaml \
  --wait --timeout=2m

# Verify connector is running
kubectl get pods -n aerospike-test -l app.kubernetes.io/name=aerospike-kafka-outbound
```

### Step 5: Deploy Source Aerospike Cluster

The script automatically generates the source cluster configuration with connector pod DNS names:

```bash
# The script generates aerocluster-src-generated.yaml with connector pod DNS
# Deploy source cluster
kubectl apply -f integration-test/aerocluster-src-generated.yaml

# Wait for cluster to be ready
kubectl wait --for=condition=ready pod -l app=aerospike-cluster,statefulset.kubernetes.io/pod-name=aerocluster-src-0-0 \
  --namespace aerospike-test --timeout=3m
```

### Step 6: Install Aerospike Tools

```bash
# Install tools in source DB pod (architecture will be auto-detected)
kubectl exec -n aerospike-test aerocluster-src-0-0 -- bash -c "
cd /tmp && \
apt-get update -qq && \
apt-get install -y -qq wget curl > /dev/null 2>&1 && \
wget -q https://download.aerospike.com/artifacts/aerospike-server-enterprise/8.0.0.8/aerospike-server-enterprise_8.0.0.8_tools-11.2.2_ubuntu20.04_aarch64.tgz -O tools.tgz && \
tar -xzf tools.tgz > /dev/null 2>&1 && \
apt-get install -y -qq libreadline8 > /dev/null 2>&1 && \
dpkg -i aerospike-server-enterprise_8.0.0.8_tools-11.2.2_ubuntu20.04_aarch64/aerospike-tools_11.2.2-ubuntu20.04_arm64.deb > /dev/null 2>&1 && \
echo '✅ Tools installed successfully'
"
```

### Step 7: Create Kafka Topic

```bash
# Create topic for testing
kubectl exec -n aerospike-test kafka-0 -- kafka-topics.sh \
  --create \
  --bootstrap-server localhost:9092 \
  --topic aerospike \
  --partitions 3 \
  --replication-factor 1
```

### Step 8: Test Data Flow

```bash
# Insert test data
TEST_KEY="test-key-$(date +%s)"
kubectl exec -n aerospike-test aerocluster-src-0-0 -- aql -h localhost -p 3020 -c \
  "INSERT INTO test.demo (PK, name, value) VALUES ('${TEST_KEY}', 'Test Record', 100)"

# Wait for replication
sleep 10

# Verify data in Kafka
kubectl exec -n aerospike-test kafka-0 -- kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic aerospike \
  --from-beginning \
  --max-messages 10
```

## Monitoring and Troubleshooting

### View Logs

```bash
# Kafka Outbound connector logs
kubectl logs -n aerospike-test -l app.kubernetes.io/name=aerospike-kafka-outbound --tail=100 -f

# Kafka broker logs
kubectl logs -n aerospike-test kafka-0 --tail=100 -f

# Aerospike cluster logs
kubectl logs -n aerospike-test aerocluster-src-0-0 --tail=100 -f
```

### Check Metrics

```bash
# Check connector metrics
kubectl logs -n aerospike-test test-kafka-outbound-aerospike-kafka-outbound-0 --tail=20 | \
  grep -E "(records-sent|records-failed|requests-total)"

# Check Kafka topic messages
kubectl exec -n aerospike-test kafka-0 -- kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic aerospike \
  --from-beginning \
  --max-messages 100
```

### Common Issues

1. **Connector not receiving data**
   - Check XDR configuration: `kubectl exec -n aerospike-test aerocluster-src-0-0 -- asinfo -v "get-dc-config"`
   - Verify connector pods are accessible from Aerospike cluster

2. **Data not reaching Kafka**
   - Check connector logs for Kafka connection errors
   - Verify Kafka broker is accessible: `kubectl exec -n aerospike-test test-kafka-outbound-aerospike-kafka-outbound-0 -- nc -zv kafka.aerospike-test.svc.cluster.local 9092`
   - Check Kafka topic exists: `kubectl exec -n aerospike-test kafka-0 -- kafka-topics.sh --list --bootstrap-server localhost:9092`

3. **Kafka broker not starting**
   - Check Kafka pod logs: `kubectl logs -n aerospike-test kafka-0`
   - Verify Zookeeper is running: `kubectl get pods -n aerospike-test -l app.kubernetes.io/name=zookeeper`

## Cleanup

```bash
# Uninstall Helm releases
helm uninstall test-kafka-outbound kafka --namespace aerospike-test

# Delete Aerospike cluster
kubectl delete aerospikecluster aerocluster-src --namespace aerospike-test

# Delete namespace (optional)
kubectl delete namespace aerospike-test
```

## Files

- `kafka-values.yaml` - Kafka broker configuration (Bitnami Kafka chart values)
- `kafka-outbound-integration-values.yaml` - Kafka Outbound connector configuration
- `aerocluster-src.yaml` - Template for Aerospike source cluster (will be generated with actual pod DNS)
- `aerocluster-src-generated.yaml` - Generated source cluster configuration (created by script)
- `run-integration-test.sh` - Automated integration test script

## Notes

- The script uses Bitnami Kafka Helm chart for easy Kafka deployment
- Kafka topic `aerospike` is created automatically by the script
- The connector configuration uses the default topic name `aerospike` (as specified in routing.destination)
- For production use, configure proper Kafka authentication, TLS, and persistence

