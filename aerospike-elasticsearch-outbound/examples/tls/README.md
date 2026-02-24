# TLS ElasticSearch Outbound Connector Example

This example demonstrates how to deploy the Aerospike ElasticSearch Outbound Connector with TLS configuration.

## Prerequisites

- Kubernetes cluster
- Helm v3
- An ElasticSearch endpoint reachable from the pods in the Kubernetes cluster
- An Aerospike cluster that can connect to Pods in the Kubernetes cluster
- TLS certificates for mutual TLS authentication

## Create TLS Secret

Before deploying, create a secret containing your TLS certificates. 
There are sample TLS certificates, keys and keystores in the [tls-certs](tls-certs) folder that the following command uses.
Use a folder with your TLS files.

```shell
kubectl -n aerospike create secret generic tls-certs --from-file=tls-certs
```

## Deploy the connector

1. Create the namespace if it doesn't exist:
```shell
kubectl create namespace aerospike
```

2. Deploy the connector:
```shell
helm install --namespace aerospike as-elastic-outbound -f as-elastic-outbound-tls-values.yaml ../../aerospike-elasticsearch-outbound
```

3. Verify the deployment:
```shell
kubectl get pods --namespace aerospike --selector=app=as-elastic-outbound-aerospike-elastic-outbound
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

Edit the `as-elastic-outbound-tls-values.yaml` file and update the `destinations.dc1.urls` to point to your ElasticSearch endpoint:

```yaml
destinations:
  dc1:
    urls:
      - https://your-elastic-endpoint:8443
```

## Cleanup

To remove the deployment:
```shell
helm uninstall --namespace aerospike as-elastic-outbound
kubectl delete secret tls-certs --namespace aerospike
``` 