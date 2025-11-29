# Local Kind Installation for XDR Proxy Integration Test

This directory contains scripts to set up a complete local Kind cluster environment for testing the Aerospike XDR Proxy integration test.

## Prerequisites

- `kubectl` - Kubernetes command-line tool
- `kind` - Kubernetes in Docker
- `docker` - Docker daemon running
- `helm` - Helm v3
- `features.conf` - Aerospike license file (place in `kind/config/features.conf`)

## Setup

### 1. Prepare License File

Copy your Aerospike `features.conf` license file to:

```bash
cp /path/to/your/features.conf kind/config/features.conf
```

### 2. Install Complete Environment

The `install-kind.sh` script sets up:

- Kind cluster (`xdr-proxy-test-cluster`)
- Operator Lifecycle Manager (OLM)
- Aerospike Kubernetes Operator (AKO)
- Namespace (`aerospike-test`) with proper permissions
- Secrets for Aerospike cluster

```bash
cd kind
./install-kind.sh
```

### 3. Run Integration Test

After installation, you can run the integration test:

```bash
cd ../integration-test
./run-integration-test.sh
```

Or deploy components manually:

```bash
# Deploy XDR Proxy
helm install test-xdr-proxy .. \
  --namespace aerospike-test \
  --values integration-test/xdr-proxy-values.yaml

# Deploy Aerospike clusters
kubectl apply -f integration-test/aerocluster-dst.yaml
kubectl apply -f integration-test/aerocluster-src.yaml
```

## Cleanup

To completely remove the Kind cluster and all resources:

```bash
cd kind
./uninstall-kind.sh
```

This will:

- Uninstall all Helm releases
- Delete Aerospike clusters
- Remove secrets and RBAC resources
- Uninstall AKO and OLM
- Delete the Kind cluster

## Manual Steps

If you prefer to set up manually, see [INTEGRATION-TEST.md](../integration-test/INTEGRATION-TEST.md) for step-by-step instructions.

