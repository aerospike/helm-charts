# Aerospike Vector Search EKS example

## Prerequisites
- EKS cluster
- Helm v3
- An Aerospike cluster that can connect to Pods in the Kubernetes cluster
  The Aerospike cluster can be deployed in the same Kubernetes cluster using [Aerospike Kubernetes Operator](https://docs.aerospike.com/cloud/kubernetes/operator)
- Aerospike Vector Search [Helm chart](../../README.md#configuration)

## Adding the helm chart repository

Add the `aerospike` helm repository if not already done

```shell
helm repo add aerospike https://aerospike.github.io/helm-charts
```

## Deploy Aerospike Vector Search Cluster.

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

### EKS LoadBalancer configuration
In this example we configure internal facing L4 LoadBalancer (NLB) for more details please refer to AWS [documentation](https://docs.aws.amazon.com/eks/latest/userguide/network-load-balancing.html).

### Deploy Aerospike Vector Search.
Update the [avs-eks-values.yaml](avs-eks-values.yaml) file to change Aerospike Vector Search configuration.


Deploy the Aerospike Vector Search cluster using configuration from [avs-eks-values.yaml](avs-eks-values.yaml)
```shell
helm install --namespace aerospike avs-eks -f avs-eks-values.yaml ../../../aerospike-vector-search
```
