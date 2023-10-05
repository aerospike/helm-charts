# Aerospike Pulsar Outbound clear text example

This example deploys Aerospike Pulsar Outbound connectors and an Aerospike cluster without TLS configured. 

## Prerequisites
 - Kubernetes cluster
 - Helm v3
 - A Pulsar cluster with brokers reachable from the pods in the Kubernetes cluster
 - An Aerospike cluster that can connect to Pods in the Kubernetes cluster
   The Aerospike cluster can be deployed in the same Kubernetes cluster using [Aerospike Kubernetes Operator](https://docs.aerospike.com/cloud/kubernetes/operator)
 - Aerospike Pulsar Connector [Helm chart](../../README.md#adding-the-helm-chart-repository)

## Clone this repository.
 - A clone of this git repository

## Deploy connectors.

All subsequent commands are run from this directory.

### Create a new Kubernetes namespace
Create a Kubernetes namespace if not already done 
```shell
kubectl create namespace aerospike
```

### Deploy the connectors.
Update the [as-pulsar-outbound-values.yaml](as-pulsar-outbound-values.yaml) file to change connector configuration to use your Pulsar cluster's service url.

Deploy the connectors using configuration from [as-pulsar-outbound-values.yaml](as-pulsar-outbound-values.yaml)
```shell
helm install --namespace aerospike as-pulsar-outbound -f as-pulsar-outbound-values.yaml aerospike/aerospike-pulsar-outbound
```

## Deploy the Aerospike cluster
If you do not have a preexisting Aerospike server, install [Aerospike Kubernetes Operator](https://docs.aerospike.com/cloud/kubernetes/operator/install-operator).
The steps below will deploy an Aerospike cluster using Aerospike Kubernetes Operator and this [sample](aerospike.yaml) custom resource.

### Create secrets
Create the secret for aerospike using your Aerospike licence file
```shell
kubectl -n aerospike create secret generic aerospike-secret --from-file=<path to features.conf>
```

### Launch the Aerospike cluster
```shell
kubectl -n aerospike create -f aerospike.yaml 
```
## Write data to Aerospike

You can write data to Aerospike using aql, asbench tools or using your own code. The record updates should
show up in your pulsar topics.

## Cleanup

### Remove the Aerospike cluster
```shell
kubectl -n aerospike delete -f aerospike.yaml 
```

### Remove the connectors
```shell
helm -n aerospike uninstall as-pulsar-outbound
```

### Delete the secrets
```shell
kubectl -n aerospike delete secrets aerospike-secret 
```

