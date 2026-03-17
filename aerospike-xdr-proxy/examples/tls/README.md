# TLS XDR Proxy Example

This example demonstrates how to deploy the Aerospike XDR Proxy Connector with TLS configuration.

## Prerequisites
- Kubernetes cluster
- Helm v3
- A destination Aerospike cluster reachable from the pods in the Kubernetes cluster
- A source Aerospike cluster that can connect to Pods in the Kubernetes cluster
- TLS certificates for mutual TLS authentication

## NOTE: these steps need to be run from examples/tls folder

## Deploy connectors

### Create a new Kubernetes namespace
Create the namespace if it doesn't exist:
```shell
kubectl create namespace aerospike-test
```

### Create a secret for TLS artifacts
Before deploying, create a secret containing your TLS certificates. 
There are sample TLS certificates, keys and keystores in the [tls-certs](tls-certs) folder that the following command uses.
Use a folder with your TLS files.
```shell
kubectl -n aerospike-test create secret generic tls-certs --from-file=tls-certs
```

## Deploy connectors
1. Update the [as-xdr-proxy-values.yaml](as-xdr-proxy-values.yaml) file:
   - Change XDR Proxy configuration to point to your destination Aerospike cluster

2. Deploy the connectors.
```shell
helm install --namespace aerospike-test xdr-proxy -f as-xdr-proxy-tls-values.yaml ../../../aerospike-xdr-proxy
```

3. Verify the deployment:
```shell
kubectl get pods --namespace aerospike-test --selector=app=xdr-proxy-aerospike-xdr-proxy
```

## Configuration

The example configuration includes:

- 1 replica proxy
- Service port 8901 and TLS port 8943
- Management port 8902
- XDR protocol (protocol: null) - accepts XDR protocol directly from Aerospike servers
- TLS configuration for secure communication
- Key store configuration for TLS
- Connection to destination Aerospike cluster
- Console logging enabled
- TLS secrets mounted to `/etc/aerospike-xdr-proxy/secrets/tls-certs`

**Note:** When XDR Proxy receives XDR protocol directly from Aerospike servers, set `protocol: null`. Use `protocol: HTTP_2` only when receiving HTTP/2 from connectors (e.g., ESP Outbound).

## Update Aerospike destination cluster

Edit the `as-xdr-proxy-tls-values.yaml` file and update the `aerospike.seeds` to point to your destination Aerospike cluster:

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
kubectl delete secret tls-certs --namespace aerospike-test
```
