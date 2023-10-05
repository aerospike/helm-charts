# Aerospike JMS Inbound TLS example

This example deploys Aerospike JMS Inbound connector and an Aerospike cluster with TLS configured. 

## Prerequisites
 - Kubernetes cluster
 - Helm v3
 - A JMS cluster with brokers reachable from the pods in the Kubernetes cluster
 - An Aerospike cluster reachable from the connectors pods in the Kubernetes cluster.
   The Aerospike cluster can be deployed in the same Kubernetes cluster using [Aerospike Kubernetes Operator](https://docs.aerospike.com/cloud/kubernetes/operator)
 - Aerospike JMS Connector [Helm chart](../../README.md#adding-the-helm-chart-repository)

## Clone this repository.
 - A clone of this git repository

## Deploy connectors.

All subsequent commands are run from this directory.

### Create a new Kubernetes namespace
Create a Kubernetes namespace if not already done 
```shell
kubectl create namespace aerospike
```

## Deploy the Aerospike cluster
If you do not have a preexisting Aerospike server, install [Aerospike Kubernetes Operator](https://docs.aerospike.com/cloud/kubernetes/operator/install-operator).
The steps below will deploy an Aerospike cluster using Aerospike Kubernetes Operator and this [sample](aerospike.yaml) custom resource.

### Create secrets
Create the secret for aerospike using your Aerospike licence file
```shell
kubectl  -n aerospike create secret generic aerospike-secret --from-file=<path to features.conf>
```
### Create a secret for TLS artifacts
Create a secret containing your TLS certificates and files.
There are few sample TLS certificates, keys and keystores in the [tls-certs](tls-certs) folder that the following command uses.
Use a folder with your TLS files.
```shell
kubectl -n aerospike create secret generic tls-certs --from-file=tls-certs
```

### Launch the Aerospike cluster
```shell
kubectl -n aerospike create -f aerospike.yaml 
```

### Deploy the connectors.
Update the [as-jms-inbound-tls-values.yaml](as-jms-inbound-tls-values.yaml) file to change `connectorConfig` to consume messages from JMS cluster with broker and update `aerospike` section to point to your destination cluster.

Deploy the connectors using configuration from [as-jms-inbound-tls-values.yaml](as-jms-inbound-tls-values.yaml)
```shell
helm install --namespace aerospike as-jms-inbound-tls -f as-jms-inbound-tls-values.yaml aerospike/aerospike-jms-inbound
```

## Write data to Aerospike

You can write data into JMS queue or topic using tools of your choice or using your own code. An Aerospike record corresponding
to each message show up in your Aerospike database.

## Cleanup

### Remove the Aerospike cluster
```shell
kubectl -n aerospike delete -f aerospike.yaml 
```

### Remove the connectors
```shell
helm -n aerospike uninstall as-jms-inbound-tls
```

### Delete the secrets
```shell
kubectl -n aerospike delete secrets aerospike-secret tls-certs 
```

