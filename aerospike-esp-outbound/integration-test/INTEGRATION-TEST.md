# Integration Test: Source DB -> ESP Outbound -> XDR Proxy -> Destination DB

This guide walks you through setting up a complete integration test to verify the data flow:
**Source Aerospike DB → ESP Outbound Connector → XDR Proxy → Destination Aerospike DB**

## Quick Start

**Automated Test (Recommended):**
```bash
# Run the complete integration test script (sets up environment, runs tests, and displays metrics)
cd integration-test
./run-integration-test.sh
```

**Manual Deployment Order:**
1. Destination Aerospike Cluster
2. XDR Proxy (aerospike-xdr-proxy chart)
3. ESP Outbound Connector
4. Source Aerospike Cluster (with XDR pointing to ESP Outbound)

**Manual Quick Test:**
```bash
# After all components are deployed and tools installed:
kubectl exec -n aerospike-test aerocluster-src-0-0 -- aql -h localhost -p 3000 -c "INSERT INTO test.demo (PK, name, value) VALUES ('test-key', 'Test', 100)"
sleep 10
kubectl exec -n aerospike-test aerocluster-dst-0-0 -- aql -h localhost -p 3000 -c "SELECT * FROM test.demo WHERE PK='test-key'"
```

## Architecture

```
┌─────────────────┐         ┌──────────────────┐         ┌──────────────┐         ┌─────────────────┐
│  Source DB      │  XDR    │  ESP Outbound    │  HTTP/2 │  XDR Proxy   │  XDR    │  Destination DB │
│  (aerocluster-  │ ──────> │  Connector       │ ──────> │              │ ──────> │  (aerocluster-  │
│   src)          │         │  (Port 8901)     │         │  (Port 8901) │         │   dst)          │
└─────────────────┘         └──────────────────┘         └──────────────┘         └─────────────────┘
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
helm uninstall test-esp-outbound xdr-proxy -n aerospike-test 2>&1 | grep -v "not found" || true

# Delete Aerospike clusters
kubectl delete aerospikecluster aerocluster-src aerocluster-dst -n aerospike-test 2>&1 | grep -v "not found" || true

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

### Step 3: Deploy Destination Aerospike Cluster

```bash
# Deploy destination cluster
kubectl apply -f integration-test/aerocluster-dst.yaml

# Wait for cluster to be ready
kubectl wait --for=condition=ready pod -l app=aerospike-cluster,statefulset.kubernetes.io/pod-name=aerocluster-dst-0-0 \
  --namespace aerospike-test --timeout=2m

# Verify cluster is running
kubectl get pods -n aerospike-test -l app=aerospike-cluster
```

### Step 4: Deploy XDR Proxy

```bash
# Deploy XDR Proxy using the aerospike-xdr-proxy chart
helm install xdr-proxy ../aerospike-xdr-proxy \
  --namespace aerospike-test \
  --values integration-test/xdr-proxy-values.yaml \
  --wait --timeout 2m

# Verify proxy is running
kubectl get pods -n aerospike-test -l app.kubernetes.io/name=aerospike-xdr-proxy

# Check proxy logs for any errors
kubectl logs -n aerospike-test -l app.kubernetes.io/name=aerospike-xdr-proxy --tail=10
```

### Step 5: Deploy ESP Outbound Connector

Deploy ESP Outbound pointing to XDR Proxy:

```bash
# Deploy ESP Outbound with configuration pointing to XDR Proxy
helm install test-esp-outbound . \
  --namespace aerospike-test \
  --values integration-test/esp-outbound-integration-values.yaml \
  --wait --timeout 2m

# Verify ESP pods are running
kubectl get pods -n aerospike-test -l app.kubernetes.io/name=aerospike-esp-outbound

# Check ESP logs for any errors
kubectl logs -n aerospike-test -l app.kubernetes.io/name=aerospike-esp-outbound --tail=10
```

### Step 6: Deploy Source Aerospike Cluster

The source cluster YAML already includes ESP pod DNS names. Deploy it:

```bash
# Deploy source cluster (XDR configured to point to ESP Outbound pods)
kubectl apply -f integration-test/aerocluster-src.yaml

# Wait for cluster to be ready
kubectl wait --for=condition=ready pod -l app=aerospike-cluster,statefulset.kubernetes.io/pod-name=aerocluster-src-0-0 \
  --namespace aerospike-test --timeout=2m

# Verify all components are running
kubectl get pods -n aerospike-test

# Check source cluster logs
kubectl logs -n aerospike-test aerocluster-src-0-0 --tail=10
```

## Testing Data Flow

### Prerequisites: Install Aerospike Tools in DB Pods

Aerospike tools (aql) need to be installed in both source and destination DB pods for testing:

```bash
# Download and install tools in source DB pod
kubectl exec -n aerospike-test aerocluster-src-0-0 -- bash -c "
  cd /tmp && \
  curl -sL https://download.aerospike.com/artifacts/aerospike-server-enterprise/8.0.0.8/aerospike-server-enterprise_8.0.0.8_tools-11.2.2_ubuntu20.04_aarch64.tgz -o tools.tgz && \
  tar -xzf tools.tgz && \
  dpkg -i aerospike-server-enterprise_8.0.0.8_tools-11.2.2_ubuntu20.04_aarch64/aerospike-tools_11.2.2-ubuntu20.04_arm64.deb && \
  apt-get update -qq && apt-get install -y -qq libreadline8 > /dev/null 2>&1
"

# Download and install tools in destination DB pod
kubectl exec -n aerospike-test aerocluster-dst-0-0 -- bash -c "
  cd /tmp && \
  curl -sL https://download.aerospike.com/artifacts/aerospike-server-enterprise/8.0.0.8/aerospike-server-enterprise_8.0.0.8_tools-11.2.2_ubuntu20.04_aarch64.tgz -o tools.tgz && \
  tar -xzf tools.tgz && \
  dpkg -i aerospike-server-enterprise_8.0.0.8_tools-11.2.2_ubuntu20.04_aarch64/aerospike-tools_11.2.2-ubuntu20.04_arm64.deb && \
  apt-get update -qq && apt-get install -y -qq libreadline8 > /dev/null 2>&1
"
```

**Note:** For x86_64 architecture, use the appropriate package:
- `aerospike-server-enterprise_8.0.0.8_tools-11.2.2_ubuntu20.04_amd64.tgz`

### Step 1: Insert Data into Source Cluster

```bash
# Insert test record directly in source DB pod
kubectl exec -n aerospike-test aerocluster-src-0-0 -- aql -h localhost -p 3000 -c "INSERT INTO test.demo (PK, name, value) VALUES ('test-key-1', 'Test Record', 100)"

# Verify record in source
kubectl exec -n aerospike-test aerocluster-src-0-0 -- aql -h localhost -p 3000 -c "SELECT * FROM test.demo WHERE PK='test-key-1'"
```

### Step 2: Verify Data in Destination Cluster

```bash
# Wait a few seconds for data to flow through the pipeline
sleep 10

# Check if record replicated to destination
kubectl exec -n aerospike-test aerocluster-dst-0-0 -- aql -h localhost -p 3000 -c "SELECT * FROM test.demo WHERE PK='test-key-1'"
```

### Step 3: Check Component Metrics

```bash
# ESP Outbound metrics
kubectl logs -n aerospike-test -l app.kubernetes.io/name=aerospike-esp-outbound --tail=5 | grep -E "(requests-total|requests-success)"

# XDR Proxy metrics
kubectl logs -n aerospike-test -l app.kubernetes.io/name=aerospike-xdr-proxy --tail=5 | grep -E "(requests-total|requests-success)"

# Check all component status
kubectl get pods -n aerospike-test -o wide
```

## Troubleshooting

### ESP Outbound not receiving data

1. Check XDR configuration in source cluster:
   ```bash
   kubectl exec -n aerospike-test $SRC_POD -- asinfo -v "get-dc-config"
   ```

2. Verify ESP pods are accessible:
   ```bash
   kubectl exec -n aerospike-test $SRC_POD -- nc -zv test-esp-outbound-aerospike-esp-outbound-0.test-esp-outbound-aerospike-esp-outbound 8901
   ```

### XDR Proxy not receiving data

1. Check ESP Outbound logs for connection errors
2. Verify XDR Proxy service is accessible:
   ```bash
   kubectl exec -n aerospike-test test-esp-outbound-aerospike-esp-outbound-0 -- nc -zv xdr-proxy-aerospike-xdr-proxy.aerospike-test.svc.cluster.local 8901
   ```

### Data not reaching destination

1. Check XDR Proxy logs
2. Verify XDR Proxy can connect to destination cluster:
   ```bash
   kubectl exec -n aerospike-test $(kubectl get pods -n aerospike-test -l app.kubernetes.io/name=aerospike-xdr-proxy -o jsonpath='{.items[0].metadata.name}') -- nc -zv aerocluster-dst-0-0.aerocluster-dst.aerospike-test.svc.cluster.local 3000
   ```

## Cleanup

```bash
# Delete source cluster
kubectl delete -f integration-test/aerocluster-src.yaml

# Delete destination cluster
kubectl delete -f integration-test/aerocluster-dst.yaml

# Uninstall XDR Proxy
helm uninstall xdr-proxy --namespace aerospike-test

# ESP Outbound can remain or be uninstalled
# helm uninstall test-esp-outbound --namespace aerospike-test
```

