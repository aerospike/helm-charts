# Aerospike Vector Search Quote Search example

This example deploys Aerospike Vector Search cluster along with an Aerospike cluster and runs `quote-search` example app.

## Prerequisites
- Kubernetes cluster
- Helm v3
- An Aerospike cluster that can connect to Pods in the Kubernetes cluster
  The Aerospike cluster can be deployed in the same Kubernetes cluster using [Aerospike Kubernetes Operator](https://docs.aerospike.com/cloud/kubernetes/operator)
- Aerospike Vector Search [Helm chart](../../README.md#configuration)

## Clone this repository.
- A clone of this git repository

## Deploy Aerospike Vector Search Cluster.

All subsequent commands are run from this directory.

### Install and Configure Load-Balancer
Aerospike Vector Search cluster can be reach outside of Kubernetes cluster using a Load-Balancer in this example we're using Metallb but it could be any L4 Load-Balancer of your choice.
#### Deploy MetalLB
```shell
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.4/config/manifests/metallb-native.yaml
```
Wait for a few minutes until everything is set up
#### Deploy MetalLB Configuration
```shell
kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: example
  namespace: metallb-system
spec:
  addresses:
    - 172.18.255.200-172.18.255.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: empty
  namespace: metallb-system
EOF
```
The following ip range `172.18.255.200-172.18.255.250` is defined for Kind Kubernetes cluster you might need to choose another ip range.

## Deploy the Aerospike cluster
If you do not have a preexisting Aerospike server, install [Aerospike Kubernetes Operator](https://docs.aerospike.com/cloud/kubernetes/operator/install-operator).
The steps below will deploy an Aerospike cluster using Aerospike Kubernetes Operator and this [sample](aerospike.yaml) custom resource.

### Create secrets
Create the secret for aerospike using your Aerospike licence file
```shell
kubectl --namespace aerospike create secret generic aerospike-secret --from-file=features.conf=features.conf
```

### Launch the Aerospike cluster
```shell
kubectl -n aerospike create -f aerospike.yaml 
```

### Create a new Kubernetes namespace
Create a Kubernetes namespace if not already done
```shell
kubectl create namespace aerospike
```

### Deploy Aerospike Vector Search.
Update the [quote-search-values.yaml](quote-search-values.yaml) file to change Aerospike Vector Search configuration.

Deploy the Aerospike Vector Search cluster using configuration from [quote-search-values.yaml](quote-search-values.yaml)
```shell
helm install --namespace aerospike as-quote-search -f quote-search-values.yaml ../../../aerospike-vector-search
```

### Deploy `quote-search` app
#### Build Docker Image
Follow this [manual](https://github.com/aerospike/aerospike-vector-search-examples/blob/main/quote-semantic-search/README.md#1-build-the-image) to build `qoute-search` app.
#### Download sample data set
```shell
mkdir -p ./data
curl -L -o ./data/quotes.csv.tgz https://github.com/aerospike/aerospike-vector-search-examples/raw/main/quote-semantic-search/container-volumes/quote-search/data/quotes.csv.tgz
```
#### Run tha app
```shell
docker run -d \
--name "quote-search" \
-v "./data:/container-volumes/quote-search/data" \
--network "kind" -p "8080:8080" \
-e "AVS_HOST=$(kubectl -n aerospike get svc/as-quote-search-aerospike-vector-search-lb -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')" \
-e "AVS_PORT=80" \
-e "APP_NUM_QUOTES=5000" \
-e "GRPC_DNS_RESOLVER=native" \
-e "AVS_IS_LOADBALANCER=True" quote-search
```
## Cleanup
### Stop `quote-search` app
```shell
docker stop quote-search
docker rm quote-search
```
### Uninstall Aerospike Vector Search cluster
```shell
helm delete as-quote-search --namespace aerospike
```

### Remove the Aerospike cluster
```shell
kubectl -n aerospike delete -f aerospike.yaml
```

### Delete the secrets
```shell
kubectl -n aerospike delete secrets aerospike-secret
```