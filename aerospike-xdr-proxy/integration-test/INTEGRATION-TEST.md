# Integration Test: Source DB -> XDR Proxy -> Destination DB

This guide walks you through setting up a complete integration test to verify the data flow:
**Source Aerospike DB → XDR Proxy → Destination Aerospike DB**

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
3. Source Aerospike Cluster (with XDR pointing to XDR Proxy)

**Manual Quick Test:**
```bash
# After all components are deployed and tools installed:
kubectl exec -n aerospike-test aerocluster-src-0-0 -- aql -h localhost -p 3000 -c "INSERT INTO test.demo (PK, name, value) VALUES ('test-key', 'Test', 100)"
sleep 15
kubectl exec -n aerospike-test aerocluster-dst-0-0 -- aql -h localhost -p 3000 -c "SELECT * FROM test.demo WHERE PK='test-key'"
```

## Architecture

```
┌─────────────────┐         ┌──────────────┐         ┌─────────────────┐
│  Source DB      │  XDR    │  XDR Proxy   │  XDR    │  Destination DB │
│  (aerocluster-  │ ──────> │              │ ──────> │  (aerocluster-  │
│   src)          │         │  (Port 8901) │         │   dst)          │
└─────────────────┘         └──────────────┘         └─────────────────┘
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
helm uninstall test-xdr-proxy -n aerospike-test 2>&1 | grep -v "not found" || true

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
kubectl wait --for=condition=ready pod aerocluster-dst-0-0 \
  --namespace aerospike-test --timeout=3m

# Verify cluster is running
kubectl get pods -n aerospike-test -l app=aerospike-cluster
```

### Step 4: Deploy XDR Proxy

```bash
# Deploy XDR Proxy using the aerospike-xdr-proxy chart
helm install test-xdr-proxy .. \
  --namespace aerospike-test \
  --values integration-test/xdr-proxy-values.yaml \
  --wait --timeout 2m

# Verify proxy is running
kubectl get pods -n aerospike-test -l app.kubernetes.io/name=aerospike-xdr-proxy

# Check proxy logs for any errors
kubectl logs -n aerospike-test -l app.kubernetes.io/name=aerospike-xdr-proxy --tail=10
```

### Step 5: Deploy Source Aerospike Cluster

The source cluster needs XDR Proxy pod DNS names. You have two options:

**Option A: Use the automated script (Recommended)**
The `run-integration-test.sh` script automatically generates `aerocluster-src-generated.yaml` with actual XDR Proxy pod DNS names.

**Option B: Manual deployment**
Update `aerocluster-src.yaml` with actual XDR Proxy pod DNS names:

```bash
# First, get XDR Proxy pod DNS names
PROXY_PODS=$(kubectl get pods -n aerospike-test \
  --selector=app.kubernetes.io/name=aerospike-xdr-proxy \
  --no-headers -o custom-columns=":metadata.name")

# Update aerocluster-src.yaml with actual pod DNS names, then deploy:
kubectl apply -f integration-test/aerocluster-src.yaml

# Wait for cluster to be ready
kubectl wait --for=condition=ready pod aerocluster-src-0-0 \
  --namespace aerospike-test --timeout=3m

# Verify all components are running
kubectl get pods -n aerospike-test

# Check source cluster logs
kubectl logs -n aerospike-test aerocluster-src-0-0 --tail=10
```

## Testing Data Flow

### Prerequisites: Install Aerospike Tools in DB Pods

Aerospike tools (aql) need to be installed in both source and destination DB pods for testing:

```bash
# Detect architecture
ARCH=$(kubectl exec -n aerospike-test aerocluster-dst-0-0 -- uname -m)

if [[ "$ARCH" == *"x86"* ]] || [[ "$ARCH" == *"amd64"* ]]; then
    TOOLS_PKG="aerospike-server-enterprise_8.0.0.8_tools-11.2.2_ubuntu20.04_amd64.tgz"
    DEB_PKG="aerospike-tools_11.2.2-ubuntu20.04_amd64.deb"
else
    TOOLS_PKG="aerospike-server-enterprise_8.0.0.8_tools-11.2.2_ubuntu20.04_aarch64.tgz"
    DEB_PKG="aerospike-tools_11.2.2-ubuntu20.04_arm64.deb"
fi

# Download and install tools in source DB pod
kubectl exec -n aerospike-test aerocluster-src-0-0 -- bash -c "
  cd /tmp && \
  apt-get update -qq && \
  apt-get install -y -qq wget curl > /dev/null 2>&1 && \
  wget -q https://download.aerospike.com/artifacts/aerospike-server-enterprise/8.0.0.8/${TOOLS_PKG} -O tools.tgz && \
  tar -xzf tools.tgz > /dev/null 2>&1 && \
  apt-get install -y -qq libreadline8 > /dev/null 2>&1 && \
  dpkg -i aerospike-server-enterprise_8.0.0.8_tools-11.2.2_ubuntu20.04_*/${DEB_PKG} > /dev/null 2>&1
"

# Download and install tools in destination DB pod
kubectl exec -n aerospike-test aerocluster-dst-0-0 -- bash -c "
  cd /tmp && \
  apt-get update -qq && \
  apt-get install -y -qq wget curl > /dev/null 2>&1 && \
  wget -q https://download.aerospike.com/artifacts/aerospike-server-enterprise/8.0.0.8/${TOOLS_PKG} -O tools.tgz && \
  tar -xzf tools.tgz > /dev/null 2>&1 && \
  apt-get install -y -qq libreadline8 > /dev/null 2>&1 && \
  dpkg -i aerospike-server-enterprise_8.0.0.8_tools-11.2.2_ubuntu20.04_*/${DEB_PKG} > /dev/null 2>&1
"
```

### Step 1: Insert Data into Source Cluster

```bash
# Insert test record directly in source DB pod
kubectl exec -n aerospike-test aerocluster-src-0-0 -- aql -h localhost -p 3000 -c "INSERT INTO test.demo (PK, name, value) VALUES ('test-key-1', 'Test Record', 100)"

# Verify record in source
kubectl exec -n aerospike-test aerocluster-src-0-0 -- aql -h localhost -p 3000 -c "SELECT * FROM test.demo WHERE PK='test-key-1'"
```

### Step 2: Verify Data in Destination Cluster

```bash
# Wait for data to flow through the pipeline (XDR replication may take some time)
sleep 15

# Check if record replicated to destination
kubectl exec -n aerospike-test aerocluster-dst-0-0 -- aql -h localhost -p 3000 -c "SELECT * FROM test.demo WHERE PK='test-key-1'"
```

**Expected Result:** The record should appear in the destination cluster, confirming that XDR Proxy successfully forwarded the data.

### Step 3: Check Component Metrics

```bash
# XDR Proxy metrics
kubectl logs -n aerospike-test -l app.kubernetes.io/name=aerospike-xdr-proxy --tail=30 | grep -E "(requests-total|requests-success|records)"

# Check all component status
kubectl get pods -n aerospike-test -o wide
```

## Troubleshooting

### XDR Proxy not receiving data

1. Check XDR configuration in source cluster:
   ```bash
   kubectl exec -n aerospike-test aerocluster-src-0-0 -- asinfo -v "get-dc-config"
   ```

2. Verify XDR Proxy pods are accessible:
   ```bash
   kubectl exec -n aerospike-test aerocluster-src-0-0 -- nc -zv test-xdr-proxy-aerospike-xdr-proxy-0.test-xdr-proxy-aerospike-xdr-proxy.aerospike-test.svc.cluster.local 8901
   ```

3. Check XDR Proxy logs:
   ```bash
   kubectl logs -n aerospike-test test-xdr-proxy-aerospike-xdr-proxy-0 --tail=50
   ```

### Data not reaching destination

1. Check XDR Proxy logs for connection errors:
   ```bash
   kubectl logs -n aerospike-test test-xdr-proxy-aerospike-xdr-proxy-0 --tail=50
   ```

2. Verify XDR Proxy can connect to destination cluster:
   ```bash
   kubectl exec -n aerospike-test test-xdr-proxy-aerospike-xdr-proxy-0 -- nc -zv aerocluster-dst-0-0.aerospike-test.svc.cluster.local 3000
   ```

3. Check destination cluster logs:
   ```bash
   kubectl logs -n aerospike-test aerocluster-dst-0-0 --tail=50
   ```

### Source cluster XDR configuration issues

1. Verify the source cluster YAML has correct XDR Proxy pod DNS names
2. Check that XDR is enabled for the `test` namespace:
   ```bash
   kubectl exec -n aerospike-test aerocluster-src-0-0 -- asinfo -v "get-config:context=xdr;dc=xdr-proxy"
   ```

## Cleanup

```bash
# Delete source cluster
kubectl delete aerospikecluster aerocluster-src -n aerospike-test

# Delete destination cluster
kubectl delete aerospikecluster aerocluster-dst -n aerospike-test

# Uninstall XDR Proxy
helm uninstall test-xdr-proxy --namespace aerospike-test

# Or use the cleanup script
cd ../kind
./uninstall-kind.sh
```

## Files Reference

- `aerocluster-dst.yaml` - Destination Aerospike cluster configuration (static)
- `aerocluster-src.yaml` - Source Aerospike cluster template (static, update with XDR Proxy pod DNS names)
- `aerocluster-src-generated.yaml` - Dynamically generated source cluster config (created by `run-integration-test.sh`)
- `xdr-proxy-values.yaml` - XDR Proxy Helm chart values
- `run-integration-test.sh` - Automated integration test script

## Test Success Criteria

✅ **Test is successful if:**
1. All pods are running (STATUS=Running, READY=true)
2. Data inserted in source DB appears in destination DB
3. XDR Proxy logs show successful request forwarding
4. No errors in any component logs

❌ **Test fails if:**
1. Data inserted in source DB does not appear in destination DB after reasonable wait time
2. XDR Proxy logs show connection errors
3. Any component pods are not running or ready

