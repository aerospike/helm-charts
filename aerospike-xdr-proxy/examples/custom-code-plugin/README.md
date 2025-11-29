# Custom Code Plugin XDR Proxy Example

This example demonstrates how to deploy the Aerospike XDR Proxy Connector with custom code plugin using clear-text (non-TLS) configuration.

## Prerequisites

- Kubernetes cluster
- Helm v3
- A destination Aerospike cluster reachable from the pods in the Kubernetes cluster
- A source Aerospike cluster that can connect to Pods in the Kubernetes cluster
- A container image containing custom code plugin jars. See [Custom Code Plugin](https://docs.aerospike.com/connect/streaming/outbound-message-transformer#develop-a-custom-code-plugin) for more details.

## Docker Image

Pull the XDR Proxy image:

```shell
docker pull aerospike/aerospike-xdr-proxy:3.2.13
```

Pull the custom transformers image (or use your own):

```shell
docker pull aerospike/aerospike-connect-custom-transformers:1.0.0
```

## Deploy the proxy

1. Create the namespace if it doesn't exist:
```shell
kubectl create namespace aerospike-test
```

2. Update the [as-xdr-proxy-values.yaml](as-xdr-proxy-values.yaml) file:
   - Change XDR Proxy configuration to point to your destination Aerospike cluster
   - Update the `initContainers` section to use your custom code plugin image

3. Deploy the proxy:
```shell
helm install --namespace aerospike-test xdr-proxy -f as-xdr-proxy-values.yaml ../../aerospike-xdr-proxy
```

Or use the deploy script from the chart root:
```shell
cd ../../aerospike-xdr-proxy
./deploy-test.sh --values examples/custom-code-plugin/as-xdr-proxy-values.yaml
```

4. Verify the deployment:
```shell
kubectl get pods --namespace aerospike-test --selector=app=xdr-proxy-aerospike-xdr-proxy
```

5. Check that the custom transformer jar is mounted:
```shell
kubectl exec -n aerospike-test xdr-proxy-aerospike-xdr-proxy-0 -- ls -la /opt/aerospike-xdr-proxy/usr-lib/aerospike-xdr-proxy-custom-transformers.jar
```

## Configuration

The example configuration includes:

- 1 replica proxy
- Service port 8901 and management port 8902
- XDR protocol (protocol: null) - accepts XDR protocol directly from Aerospike servers
- Custom code plugin loaded via initContainer
- Connection to destination Aerospike cluster
- Console logging enabled

**Note:** When XDR Proxy receives XDR protocol directly from Aerospike servers, set `protocol: null`. Use `protocol: HTTP_2` only when receiving HTTP/2 from connectors (e.g., ESP Outbound).

## Custom Code Plugin

The custom code plugin jar is loaded from an initContainer image. The jar is copied to `/opt/aerospike-xdr-proxy-init` and mounted at `/opt/aerospike-xdr-proxy/usr-lib/aerospike-xdr-proxy-custom-transformers.jar` in the proxy container.

To use your own custom transformer:
1. Build a Docker image containing your custom transformer jar
2. Update the `initContainers[].image` field in `as-xdr-proxy-values.yaml`
3. Update the `initContainers[].args` to copy your jar file(s) to `/opt/aerospike-xdr-proxy-init`

## Update Aerospike destination cluster

Edit the `as-xdr-proxy-values.yaml` file and update the `aerospike.seeds` to point to your destination Aerospike cluster:

```yaml
aerospike:
  seeds:
    - your-destination-cluster-0-0.your-namespace.svc.cluster.local:
        port: 3000
```

## Configure Aerospike cluster to use XDR Proxy

Configure your Aerospike cluster's XDR to point to the XDR Proxy service. The XDR Proxy will forward requests to the destination Aerospike cluster.

## Cleanup

To remove the deployment:
```shell
helm uninstall --namespace aerospike-test xdr-proxy
```

