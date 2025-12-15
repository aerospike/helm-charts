# Integration Test: Aerospike DB -> Pulsar Outbound Connector -> Pulsar Broker

This guide walks you through setting up a complete integration test to verify the data flow:
**Aerospike DB → Pulsar Outbound Connector → Pulsar Broker**

## Quick Start

**Automated Test (Recommended):**
```bash
# Run the complete integration test script (sets up environment, runs tests, and displays metrics)
cd tests/integration-test
./run-integration-test.sh
```

**Manual Deployment Order:**
1. Pulsar Broker
2. Pulsar Outbound Connector
3. Aerospike Cluster (source) with XDR pointing to Pulsar connector

**Manual Quick Test:**
```bash
# After all components are deployed and tools installed:
# Insert test data
kubectl exec -n aerospike-test aerocluster-src-0-0 -- aql -h localhost -p 3030 -c "INSERT INTO test.demo (PK, name, value) VALUES ('test-key', 'Test', 100)"

# Wait for replication
sleep 10

# Verify data in Pulsar
kubectl exec -n aerospike-test pulsar-0 -- bin/pulsar-client consume persistent://public/default/aerospike -s test-subscription -n 10
```

## Architecture

```
┌─────────────────┐         ┌──────────────────────┐         ┌──────────────┐
│  Aerospike DB   │  XDR    │  Pulsar Outbound      │  Pulsar │  Pulsar      │
│  (aerocluster-  │ ──────> │  Connector           │ ──────> │  Broker      │
│   src)          │         │  (Port 8080)         │         │  (Port 6650) │
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
helm uninstall test-pulsar-outbound pulsar -n aerospike-test 2>&1 | grep -v "not found" || true

# Delete Aerospike clusters
kubectl delete aerospikecluster aerocluster-src -n aerospike-test 2>&1 | grep -v "not found" || true

# Delete Pulsar StatefulSet
kubectl delete statefulset pulsar -n aerospike-test 2>&1 | grep -v "not found" || true

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

### Step 3: Deploy Pulsar Broker

```bash
# Deploy Pulsar broker (standalone mode)
kubectl apply -f tests/integration-test/pulsar-deployment.yaml

# Wait for Pulsar to be ready
kubectl wait --for=condition=ready pod \
  -l app=pulsar \
  -n aerospike-test \
  --timeout=10m

# Verify Pulsar is running
kubectl get pods -n aerospike-test -l app=pulsar
```

### Step 4: Deploy Pulsar Outbound Connector

```bash
# Deploy Pulsar Outbound connector
helm install test-pulsar-outbound . \
  --namespace aerospike-test \
  --values tests/integration-test/pulsar-outbound-integration-values.yaml \
  --wait --timeout=2m

# Verify connector is running
kubectl get pods -n aerospike-test -l app.kubernetes.io/name=aerospike-pulsar-outbound
```

### Step 5: Deploy Source Aerospike Cluster

The script automatically generates the source cluster configuration with connector pod DNS names:

```bash
# The script generates aerocluster-src-generated.yaml with connector pod DNS
# Deploy source cluster
kubectl apply -f tests/integration-test/aerocluster-src-generated.yaml

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

### Step 7: Create Pulsar Topic

```bash
# Create namespace if it doesn't exist
kubectl exec -n aerospike-test pulsar-0 -- bin/pulsar-admin namespaces create public/default 2>/dev/null || echo "Namespace already exists"

# Create topic for testing
kubectl exec -n aerospike-test pulsar-0 -- bin/pulsar-admin topics create persistent://public/default/aerospike
```

### Step 8: Test Data Flow

```bash
# Insert test data
TEST_KEY="test-key-$(date +%s)"
kubectl exec -n aerospike-test aerocluster-src-0-0 -- aql -h localhost -p 3030 -c \
  "INSERT INTO test.demo (PK, name, value) VALUES ('${TEST_KEY}', 'Test Record', 100)"

# Wait for replication
sleep 10

# Verify data in Pulsar
kubectl exec -n aerospike-test pulsar-0 -- bin/pulsar-client consume \
  persistent://public/default/aerospike \
  -s test-subscription \
  -n 10
```

## Monitoring and Troubleshooting

### View Logs

```bash
# Pulsar Outbound connector logs
kubectl logs -n aerospike-test -l app.kubernetes.io/name=aerospike-pulsar-outbound --tail=100 -f

# Pulsar broker logs
kubectl logs -n aerospike-test pulsar-0 --tail=100 -f

# Aerospike cluster logs
kubectl logs -n aerospike-test aerocluster-src-0-0 --tail=100 -f
```

### Check Metrics

```bash
# Check connector metrics
kubectl logs -n aerospike-test test-pulsar-outbound-aerospike-pulsar-outbound-0 --tail=20 | \
  grep -E "(records-sent|records-failed|requests-total|requests-success)"

# Check Pulsar topic messages
kubectl exec -n aerospike-test pulsar-0 -- bin/pulsar-client consume \
  persistent://public/default/aerospike \
  -s test-subscription \
  -n 100
```

### Common Issues

1. **Connector not receiving data**
   - Check XDR configuration: `kubectl exec -n aerospike-test aerocluster-src-0-0 -- asinfo -v "get-dc-config"`
   - Verify connector pods are accessible from Aerospike cluster

2. **Data not reaching Pulsar**
   - Check connector logs for Pulsar connection errors
   - Verify Pulsar broker is accessible: `kubectl exec -n aerospike-test test-pulsar-outbound-aerospike-pulsar-outbound-0 -- nc -zv pulsar.aerospike-test.svc.cluster.local 6650`
   - Check Pulsar topic exists: `kubectl exec -n aerospike-test pulsar-0 -- bin/pulsar-admin topics list public/default`

3. **Pulsar broker not starting**
   - Check Pulsar pod logs: `kubectl logs -n aerospike-test pulsar-0`
   - Verify Pulsar is ready: `kubectl get pods -n aerospike-test -l app=pulsar`

## Cleanup

```bash
# Uninstall Helm releases
helm uninstall test-pulsar-outbound pulsar --namespace aerospike-test

# Delete Pulsar StatefulSet
kubectl delete statefulset pulsar --namespace aerospike-test
kubectl delete service pulsar pulsar-headless --namespace aerospike-test

# Delete Aerospike cluster
kubectl delete aerospikecluster aerocluster-src --namespace aerospike-test

# Delete namespace (optional)
kubectl delete namespace aerospike-test
```

## Files

- `pulsar-deployment.yaml` - Pulsar broker deployment configuration (Apache Pulsar 4.0.7 standalone)
- `pulsar-outbound-integration-values.yaml` - Pulsar Outbound connector configuration
- `aerocluster-src.yaml` - Template for Aerospike source cluster (will be generated with actual pod DNS)
- `aerocluster-src-generated.yaml` - Generated source cluster configuration (created by script)
- `run-integration-test.sh` - Automated integration test script

## Notes

- The script uses Apache Pulsar official image (standalone mode) for easy Pulsar deployment
- Pulsar topic `persistent://public/default/aerospike` is created automatically by the script
- The connector configuration uses the default topic name `persistent://public/default/aerospike` (as specified in routing.destination)
- For production use, configure proper Pulsar authentication, TLS, and persistence
- Pulsar standalone mode is suitable for testing; use Pulsar cluster mode for production

