# Local Kind Installation for JMS Outbound Integration Test

This directory contains scripts to set up a complete local Kind cluster environment for testing the Aerospike JMS Outbound connector integration test.

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
- Kind cluster (`jms-test-cluster`)
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
cd ../tests/integration-test
./run-integration-test.sh
```

Or deploy components manually:

```bash
# Deploy RabbitMQ broker
kubectl apply -f ../tests/integration-test/rabbitmq-deployment.yaml

# Deploy JMS Outbound connector
helm install test-jms-outbound ../aerospike-jms-outbound \
  --namespace aerospike-test \
  --values ../tests/integration-test/jms-outbound-integration-values.yaml

# Deploy Aerospike cluster (after connector pods are ready)
kubectl apply -f ../tests/integration-test/aerocluster-src-generated.yaml
```

## Cleanup

To completely remove the Kind cluster and all resources:

```bash
cd kind
./uninstall-kind.sh
```

This will:
- Uninstall all Helm releases (JMS Outbound connector and RabbitMQ broker)
- Delete Aerospike clusters
- Remove secrets and RBAC resources
- Uninstall AKO and OLM
- Delete the Kind cluster

## Manual Steps

If you prefer to set up manually, see [INTEGRATION-TEST.md](../tests/integration-test/INTEGRATION-TEST.md) for step-by-step instructions.
