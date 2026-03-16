# Clear Text ElasticSearch Outbound Connector Example

This example demonstrates how to deploy the Aerospike ElasticSearch Outbound Connector with clear text configuration.

## Prerequisites

- Kubernetes cluster
- Helm v3
- An ESP endpoint reachable from the pods in the Kubernetes cluster
- An Aerospike cluster that can connect to Pods in the Kubernetes cluster

## Deploy the connector

1. Create the namespace if it doesn't exist:
```shell
kubectl create namespace aerospike
```

2. Deploy the connector:
```shell
helm install --namespace aerospike as-es-outbound -f as-elastic-outbound-values.yaml ../../../aerospike-elasticsearch-outbound
```

3. Verify the deployment:
```shell
kubectl get pods --namespace aerospike --selector=app=as-es-outbound-aerospike-elasticsearch-outbound
```

## Configuration

The example configuration includes:

- 3 replica connectors
- Service port 8901 and management port 8902
- Static multi-destination routing to 'dc1'
- HTTP/2 protocol without TLS (clear-text)
- Health checks and connection pooling
- Console logging enabled

## Update ElasticSearch endpoint

Edit the `as-elasticsearch-outbound-values.yaml` file and update the `<TODO>` to point to your ElasticSearch endpoint:

```yaml
<TODO> Add example with es-client
```

**Note:** This example uses HTTP (clear-text). For HTTPS connections, use the [TLS example](../tls/README.md).

## Cleanup

To remove the deployment:
```shell
helm uninstall --namespace aerospike as-es-outbound
``` 