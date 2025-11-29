# Aerospike XDR Proxy Connector

This Helm chart allows you to configure and run our official [Aerospike XDR Proxy Connector](https://hub.docker.com/repository/docker/aerospike/aerospike-xdr-proxy) 
docker image on a Kubernetes cluster.

This helm chart sets up a `StatefulSet` for each proxy deployment. We use a `StatefulSet` instead of a `Deployment`, to have stable DNS names for the  
deployed proxy pods.

**_NOTE:_** The helm chart appends `-aerospike-xdr-proxy` suffix to all created Kubernetes resources to prevent name clashes with other applications.

## Prerequisites

- **Kubernetes Cluster**: A running Kubernetes cluster (v1.19+)
  - Local options: [kind](https://kind.sigs.k8s.io/), [minikube](https://minikube.sigs.k8s.io/), [Docker Desktop](https://www.docker.com/products/docker-desktop)
  - Cloud options: GKE, EKS, AKS, or any Kubernetes cluster
- **Helm**: v3.x installed ([Install Helm](https://helm.sh/docs/intro/install/))
- **kubectl**: Configured to connect to your cluster
- **Destination Aerospike Cluster**: A destination Aerospike cluster reachable from the pods in the Kubernetes cluster
- **Source Aerospike Cluster**: A source Aerospike cluster that can connect to Pods in the Kubernetes cluster.
  The Aerospike cluster can be deployed in the same Kubernetes cluster using [Aerospike
  Kubernetes Operator](https://docs.aerospike.com/cloud/kubernetes/operator)

## Quick Start

### Option 1: Using the Deployment Script

```bash
# Deploy with default values
./deploy-test.sh

# Deploy with custom values file
./deploy-test.sh --values examples/clear-text/as-xdr-proxy-values.yaml

# Deploy with TLS configuration
./deploy-test.sh --values examples/tls/as-xdr-proxy-tls-values.yaml

# Deploy to custom namespace
./deploy-test.sh --namespace my-namespace --release-name my-release

# Uninstall
./deploy-test.sh --uninstall
```

### Option 2: Using Helm Directly

```bash
# Create namespace
kubectl create namespace aerospike-test

# Deploy with default values
helm install test-xdr-proxy . \
  --namespace aerospike-test \
  --wait --timeout 5m

# Deploy with custom values
helm install test-xdr-proxy . \
  --namespace aerospike-test \
  --values examples/clear-text/as-xdr-proxy-values.yaml \
  --wait --timeout 5m
```

## Install the helm chart

Add the `aerospike` helm repository if not already done

```shell
helm repo add aerospike https://aerospike.github.io/helm-charts
```

Install the Aerospike XDR Proxy connector helm chart

```shell
helm install aerospike-xdr-proxy aerospike/aerospike-xdr-proxy
```

## Docker Image

The default image used is `aerospike/aerospike-xdr-proxy:3.2.13`. You can pull it manually:

```shell
docker pull aerospike/aerospike-xdr-proxy:3.2.13
```

## Supported configuration

## Configuration

| Parameter          | Description                                                                                                                                                                          | Default                        |
|--------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------|
| `replicaCount`     | Configures the number Aerospike XDR Proxy pods to run.                                                                                                                              | '1'                            |
| `image`            | Configures Aerospike XDR Proxy image repository, tag and pull policy.                                                                                                                | see [values.yaml](values.yaml) |
| `proxyConfig`      | Proxy configuration deployed to `/etc/aerospike-xdr-proxy/aerospike-xdr-proxy.yml`.                                                                                                | see [values.yaml](values.yaml) |
| `proxySecrets`     | List of secrets mounted to `/etc/aerospike-xdr-proxy/secrets` for each proxy pod.                                                                                                    | `[]`                           |
| `autoscaling`      | Enable the horizontal pod auto-scaler.                                                                                                                                             | see [values.yaml](values.yaml) |
| `serviceAccount`   | Service Account details like name and annotations.                                                                                                                                   | see [values.yaml](values.yaml) |
| `podAnnotations`   | Additional pod [annotations](https://kubernetes.io/docs/concepts/overview/working-with-objects/annotations/). Should be specified as a map of annotation names to annotation values. | `{}`                           |
| `securityContext`  | Pod [security context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)                                                                                 | `{}`                           |
| `resources`        | Resource [requests and limits](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) for the proxy pods.                                                 | `{}`                           |
| `affinity`         | [Affinity](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#affinity-and-anti-affinity)  rules if any for the pods.                                          | `{}`                           |
| `nodeSelector`     | [Node selector](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#nodeselector)  for the pods.                                                                | `{}`                           |
| `tolerations`      | [Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)  for the pods.                                                                        | `{}`                           |

## Examples

See the [examples](examples) directory for example configurations:
- [Clear Text Example](examples/clear-text/) - Basic configuration without TLS
- [TLS Example](examples/tls/) - Configuration with TLS enabled

## Documentation

For detailed XDR Proxy configuration options, visit:
https://www.aerospike.com/docs/connectors/enterprise/xdr-proxy/configuration/index.html

