# Clear Text XDR Proxy Example

This example demonstrates how to deploy the Aerospike XDR Proxy Connector with clear text configuration.

## Prerequisites

- Kubernetes cluster
- Helm v3
- A destination Aerospike cluster reachable from the pods in the Kubernetes cluster
- A source Aerospike cluster that can connect to Pods in the Kubernetes cluster

## Docker Image

Pull the XDR Proxy image:

```shell
docker pull aerospike/aerospike-xdr-proxy:3.2.13
```

## Deploy the proxy

1. Create the namespace if it doesn't exist:
```shell
kubectl create namespace aerospike-test
```

2. Deploy the proxy:
```shell
helm install --namespace aerospike-test xdr-proxy -f as-xdr-proxy-values.yaml ../../aerospike-xdr-proxy
```

3. Verify the deployment:
```shell
kubectl get pods --namespace aerospike-test --selector=app=xdr-proxy-aerospike-xdr-proxy
```

## Configuration

The example configuration includes:

- 1 replica proxy
- Service port 8901 and management port 8902
- XDR protocol (protocol: null) - accepts XDR protocol directly from Aerospike servers
- Connection to destination Aerospike cluster
- Console logging enabled

**Note:** When XDR Proxy receives XDR protocol directly from Aerospike servers, set `protocol: null`. Use `protocol: HTTP_2` only when receiving HTTP/2 from connectors (e.g., ESP Outbound).

## Update Aerospike destination cluster

Edit the `as-xdr-proxy-values.yaml` file and update the `aerospike.seeds` to point to your destination Aerospike cluster:

```yaml
aerospike:
  seeds:
    - your-destination-cluster-0-0.your-namespace.svc.cluster.local:
        port: 3000
```

## Cleanup

To remove the deployment:
```shell
helm uninstall --namespace aerospike-test xdr-proxy
```

