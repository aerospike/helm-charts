# Aerospike Proximus GKE example

## Prerequisites
- GKE cluster
- Helm v3
- An Aerospike cluster that can connect to Pods in the Kubernetes cluster
  The Aerospike cluster can be deployed in the same Kubernetes cluster using [Aerospike Kubernetes Operator](https://docs.aerospike.com/cloud/kubernetes/operator)
- Aerospike Proximus [Helm chart](../../README.md#configuration)

## Adding the helm chart repository

Add the `aerospike` helm repository if not already done

```shell
helm repo add aerospike https://aerospike.github.io/helm-charts
```

## Deploy Proximus Cluster.

All subsequent commands are run from this directory.

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

### GKE LoadBalancer configuration
In this example we configure internal facing L4 LoadBalancer for more details please refer to GCP [documentation](https://cloud.google.com/kubernetes-engine/docs/concepts/service-load-balancer).

### Deploy Proximus.
Update the [avs-gke-values.yaml](avs-gke-values.yaml) file to change Proximus configuration.


Deploy the Proximus cluster using configuration from [avs-gke-values.yaml](avs-gke-values.yaml)
```shell
helm install --namespace aerospike as-proximus-gke -f avs-gke-values.yaml ../../../aerospike-proximus
```
