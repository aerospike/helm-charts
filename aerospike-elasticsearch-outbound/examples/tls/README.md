# TLS ElasticSearch Outbound Connector Example

This example demonstrates how to deploy the Aerospike ElasticSearch Outbound Connector with TLS configuration.

## Prerequisites

- Kubernetes cluster
- Helm v3
- An ElasticSearch endpoint reachable from the pods in the Kubernetes cluster
- An Aerospike cluster that can connect to Pods in the Kubernetes cluster
- TLS certificates for mutual TLS authentication

## NOTE: these steps need to be run from examples/clear-text folder

## Deploy connectors

### Create a new Kubernetes namespace
Create the namespace if it doesn't exist:
```shell
kubectl create namespace aerospike
```

### Create TLS Secret

Before deploying, create a secret containing your TLS certificates. 
There are sample TLS certificates, keys and keystores in the [tls-certs](tls-certs) folder that the following command uses.
Use a folder with your TLS files.

```shell
kubectl -n aerospike create secret generic tls-certs --from-file=tls-certs
```

### Deploy the connector

1. Deploy the connector:
```shell
helm install --namespace aerospike as-es-outbound -f as-elasticsearch-outbound-tls-values.yaml ../../../aerospike-elasticsearch-outbound
```

2. Verify the deployment:
```shell
kubectl get pods --namespace aerospike --selector=app=as-es-outbound-aerospike-elasticsearch-outbound
```

## Configuration

The example configuration includes:

- 3 replica connectors
- Service port 8901 and management port 8902
- Static multi-destination routing to 'dc1'
- HTTP/2 protocol with mutual TLS
- Trust store and key store configuration
- Health checks and connection pooling
- Console logging enabled
- TLS secrets mounted to `/etc/aerospike-elasticsearch-outbound/secrets/tls-certs`

## Update ElasticSearch endpoint

Edit the `as-elasticsearch-outbound-tls-values.yaml` file and update the `<TODO>` to point to your ElasticSearch endpoint:

```yaml
<TODO>: Add es-client
```

## Cleanup

To remove the deployment:
```shell
helm uninstall --namespace aerospike as-es-outbound
kubectl delete secret tls-certs --namespace aerospike
``` 