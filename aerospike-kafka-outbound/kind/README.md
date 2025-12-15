# Local Kind Installation for Kafka Outbound Integration Test

This directory contains scripts to set up a complete local Kind cluster environment for testing the Aerospike Kafka Outbound connector integration test.

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
- Kind cluster (`kafka-test-cluster`)
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
# Add Bitnami Helm repository
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Deploy Kafka broker
helm install kafka bitnami/kafka \
  --namespace aerospike-test \
  --values ../tests/integration-test/kafka-values.yaml

# Deploy Kafka Outbound connector
helm install test-kafka-outbound ../aerospike-kafka-outbound \
  --namespace aerospike-test \
  --values ../tests/integration-test/kafka-outbound-integration-values.yaml

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
- Uninstall all Helm releases (Kafka Outbound connector and Kafka broker)
- Delete Aerospike clusters
- Remove secrets and RBAC resources
- Uninstall AKO and OLM
- Delete the Kind cluster

## Manual Steps

If you prefer to set up manually, see [INTEGRATION-TEST.md](../tests/integration-test/INTEGRATION-TEST.md) for step-by-step instructions.
